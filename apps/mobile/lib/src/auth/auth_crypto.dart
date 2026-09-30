import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';

class BootstrapKeyMaterial {
  const BootstrapKeyMaterial({
    required this.seed,
    required this.publicKey,
    required this.slotId,
  });
  final String seed;
  final String publicKey;
  final String slotId;
}

/// Fixed framing is parsed for local binding only. This does not authenticate V
/// or establish ticket authorization; the authoritative C verifier does that.
class UnverifiedRegistrationTicket {
  const UnverifiedRegistrationTicket({
    required this.epoch,
    required this.admissionWindow,
    required this.slotId,
    required this.bootstrapPublicKey,
  });
  final int epoch;
  final int admissionWindow;
  final String slotId;
  final String bootstrapPublicKey;
}

class AuthCrypto {
  static final Random _random = Random.secure();
  static final Ed25519 _ed25519 = Ed25519();

  static String randomEncoded(int bytes) {
    if (bytes != 16 && bytes != 32) {
      throw ArgumentError(
        'Only protocol random lengths 16 and 32 are supported',
      );
    }
    return encode(List<int>.generate(bytes, (_) => _random.nextInt(256)));
  }

  static String encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List decode(String encoded, {int? bytes, int? maxBytes}) {
    final limit = maxBytes ?? bytes ?? 8192;
    if (limit < 1 ||
        encoded.length > (limit * 8 + 5) ~/ 6 ||
        (bytes != null && encoded.length != (bytes * 8 + 5) ~/ 6) ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(encoded) ||
        encoded.length % 4 == 1) {
      throw const FormatException('Invalid protocol byte encoding');
    }
    final decoded = base64Url.decode(base64Url.normalize(encoded));
    if (encode(decoded) != encoded ||
        (bytes != null && decoded.length != bytes) ||
        (maxBytes != null && decoded.length > maxBytes)) {
      throw const FormatException('Invalid protocol byte encoding');
    }
    return decoded;
  }

  static String domainDigest(String domain, List<int> bytes) => encode(
    hashes.sha256.convert([...ascii.encode(domain), 0, ...bytes]).bytes,
  );

  static String slotId(String publicKey) =>
      domainDigest('HNUHOLE/SLOT/V1', [1, ...decode(publicKey, bytes: 32)]);

  static String revocationSecret(String sessionToken) => domainDigest(
    'HNUHOLE/SESSION-REVOKE/V1',
    decode(sessionToken, bytes: 32),
  );

  static String closureStatusDigest(String statusSecret) =>
      domainDigest('HNUHOLE/CLOSE-STATUS/V1', decode(statusSecret, bytes: 32));

  static Future<BootstrapKeyMaterial> newBootstrapKey() async =>
      bootstrapKeyFromSeed(randomEncoded(32));

  static Future<BootstrapKeyMaterial> bootstrapKeyFromSeed(String seed) async {
    final key = await _ed25519.newKeyPairFromSeed(decode(seed, bytes: 32));
    final public = encode((await key.extractPublicKey()).bytes);
    return BootstrapKeyMaterial(
      seed: seed,
      publicKey: public,
      slotId: slotId(public),
    );
  }

  static UnverifiedRegistrationTicket parseRegistrationTicket(String wire) {
    final bytes = decode(wire, bytes: 156);
    final prefix = [...ascii.encode('HNUHOLE/REGISTER/V2'), 0];
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) {
        throw const FormatException('Unsupported registration ticket framing');
      }
    }
    final public = encode(bytes.sublist(60, 92));
    final slot = encode(bytes.sublist(28, 60));
    if (slotId(public) != slot) {
      throw const FormatException('Registration ticket slot binding mismatch');
    }
    final data = ByteData.sublistView(bytes);
    return UnverifiedRegistrationTicket(
      epoch: data.getUint32(20),
      admissionWindow: data.getUint32(24),
      slotId: slot,
      bootstrapPublicKey: public,
    );
  }

  static Uint8List bootstrapMessage({
    required String registrationTicket,
    required String intentId,
    required String challenge,
  }) {
    final ticket = parseRegistrationTicket(registrationTicket);
    return Uint8List.fromList([
      ...ascii.encode('HNUHOLE/BOOTSTRAP-POP/V1'),
      0,
      ...decode(ticket.slotId, bytes: 32),
      ...decode(intentId, bytes: 32),
      ...decode(challenge, bytes: 32),
      ...hashes.sha256.convert(decode(registrationTicket, bytes: 156)).bytes,
    ]);
  }

  static Future<String> signBootstrap({
    required String seed,
    required String registrationTicket,
    required String intentId,
    required String challenge,
  }) async {
    final material = await bootstrapKeyFromSeed(seed);
    final ticket = parseRegistrationTicket(registrationTicket);
    if (ticket.slotId != material.slotId ||
        ticket.bootstrapPublicKey != material.publicKey) {
      throw const FormatException(
        'Registration ticket does not match bootstrap key',
      );
    }
    final key = await _ed25519.newKeyPairFromSeed(decode(seed, bytes: 32));
    final signature = await _ed25519.sign(
      bootstrapMessage(
        registrationTicket: registrationTicket,
        intentId: intentId,
        challenge: challenge,
      ),
      keyPair: key,
    );
    return encode(signature.bytes);
  }
}
