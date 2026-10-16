import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/src/auth/auth_crypto.dart';

List<int> _hex(String value) => [
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
];

void main() {
  final vectors = jsonDecode(
    File('../../packages/auth-protocol-vectors/v1.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final positives = vectors['positiveSignatures'] as List;
  final registration = positives.firstWhere(
    (value) => value['id'] == 'SIG_REGISTER_CURRENT',
  ) as Map;
  final pop = positives.firstWhere(
    (value) => value['id'] == 'SIG_BOOTSTRAP_POP',
  ) as Map;
  final key = (vectors['keys'] as List).firstWhere(
    (value) => value['id'] == 'bootstrap_rfc8032_test3',
  ) as Map;
  final wire = registration['wireBase64url'] as String;
  final seed = AuthCrypto.encode(_hex(key['testSeedHex'] as String));
  final fields = pop['fields'] as Map;
  final intent = AuthCrypto.encode(_hex(fields['intentIdHex'] as String));
  final challenge = AuthCrypto.encode(_hex(fields['challengeHex'] as String));

  test(
    'bootstrap key and domain slot match the independent protocol vector',
    () async {
      final material = await AuthCrypto.bootstrapKeyFromSeed(seed);
      expect(
        AuthCrypto.decode(material.publicKey),
        _hex(key['publicKeyHex'] as String),
      );
      final slot = (vectors['slotDerivations'] as List).first as Map;
      expect(
        AuthCrypto.decode(material.slotId),
        _hex(slot['slotIdHex'] as String),
      );
      final ticket = AuthCrypto.parseRegistrationTicket(wire);
      expect(ticket.epoch, 0x01020304);
      expect(ticket.admissionWindow, 1000000);
      expect(ticket.slotId, material.slotId);
      expect(ticket.bootstrapPublicKey, material.publicKey);
    },
  );

  test(
    'bootstrap Pure Ed25519 signs the fixed 153 byte original message',
    () async {
      final message = AuthCrypto.bootstrapMessage(
        registrationTicket: wire,
        intentId: intent,
        challenge: challenge,
      );
      expect(message.length, 153);
      expect(message, _hex(pop['messageHex'] as String));
      expect(
        await AuthCrypto.signBootstrap(
          seed: seed,
          registrationTicket: wire,
          intentId: intent,
          challenge: challenge,
        ),
        pop['wireBase64url'],
      );
    },
  );

  test('PoP rejects substituted key or slot and changes when the ticket signature changes', () async {
    final attacker = AuthCrypto.encode(
      List<int>.generate(32, (index) => index),
    );
    await expectLater(
      AuthCrypto.signBootstrap(
        seed: attacker,
        registrationTicket: wire,
        intentId: intent,
        challenge: challenge,
      ),
      throwsFormatException,
    );
    final original = AuthCrypto.bootstrapMessage(
      registrationTicket: wire,
      intentId: intent,
      challenge: challenge,
    );
    final bytes = AuthCrypto.decode(wire, bytes: 156);
    bytes[155] ^= 1;
    final changed = AuthCrypto.bootstrapMessage(
      registrationTicket: AuthCrypto.encode(bytes),
      intentId: intent,
      challenge: challenge,
    );
    expect(changed, isNot(original));
    expect(changed.take(121), original.take(121));
    bytes[28] ^= 1;
    expect(
      () => AuthCrypto.parseRegistrationTicket(AuthCrypto.encode(bytes)),
      throwsFormatException,
    );
  });

  test('canonical wire rejects aliases padding wrong lengths and trailing frame bytes', () {
    final good = AuthCrypto.encode(List<int>.filled(32, 0));
    for (final bad in [
      '$good=',
      ' $good',
      '$good\n',
      '${good.substring(0, 42)}B',
      '+$good',
      'A',
    ]) {
      expect(
        () => AuthCrypto.decode(bad, bytes: 32),
        throwsFormatException,
        reason: 'wire must be canonical',
      );
    }
    expect(() => AuthCrypto.decode(good, bytes: 16), throwsFormatException);
    final frame = AuthCrypto.decode(wire);
    expect(
      () =>
          AuthCrypto.parseRegistrationTicket(AuthCrypto.encode([...frame, 0])),
      throwsFormatException,
    );
    frame[18] = 49;
    expect(
      () => AuthCrypto.parseRegistrationTicket(AuthCrypto.encode(frame)),
      throwsFormatException,
    );
  });

  test('logout and closure domain hashes match published fixed vectors', () {
    final domains = vectors['domainHashes'] as List;
    for (final id in ['HASH_CLOSE_STATUS', 'HASH_SESSION_REVOKE']) {
      final vector = domains.firstWhere((value) => value['id'] == id) as Map;
      final input = AuthCrypto.encode(_hex(vector['inputHex'] as String));
      final digest = id == 'HASH_CLOSE_STATUS'
          ? AuthCrypto.closureStatusDigest(input)
          : AuthCrypto.revocationSecret(input);
      expect(AuthCrypto.decode(digest), _hex(vector['digestHex'] as String));
    }
    final token = AuthCrypto.encode(List<int>.filled(32, 1));
    expect(
      AuthCrypto.closureStatusDigest(token),
      isNot(AuthCrypto.revocationSecret(token)),
    );
  });

  test(
    'installation IDs and bootstrap seeds have the fixed random lengths',
    () async {
      final one = AuthCrypto.randomEncoded(16);
      final two = AuthCrypto.randomEncoded(16);
      expect(one, isNot(two));
      expect(AuthCrypto.decode(one, bytes: 16), hasLength(16));
      final material = await AuthCrypto.newBootstrapKey();
      expect(AuthCrypto.decode(material.seed, bytes: 32), hasLength(32));
      expect(material.slotId, AuthCrypto.slotId(material.publicKey));
      expect(() => AuthCrypto.randomEncoded(64), throwsArgumentError);
    },
  );

  test('protocol decoders bound byte allocations before decoding', () {
    final oversized = 'A' * 20000;
    expect(() => AuthCrypto.decode(oversized), throwsFormatException);
    expect(
      () => AuthCrypto.decode(oversized, bytes: 32),
      throwsFormatException,
    );
    expect(() => AuthCrypto.decode('AAAA', maxBytes: 1), throwsFormatException);
    expect(AuthCrypto.decode('AA', maxBytes: 1), [0]);
  });
}
