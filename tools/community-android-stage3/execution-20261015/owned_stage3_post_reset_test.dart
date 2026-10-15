import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';

class _ReadOnlyFixtureVault implements AuthVault {
  _ReadOnlyFixtureVault(this.file);
  final File file;
  @override Future<String?> read() => file.readAsString();
  @override Future<void> write(String value) => throw StateError('Original fixture evidence is read only');
}

void main() {
  late HttpAuthApi api;
  late Map<String,dynamic> original;
  late String oldToken;
  late Directory root;
  setUpAll(() async {
    root=Directory('/home/hnuhole/community-android-stage3-execution-20261015/lab');
    final cfg=jsonDecode(await File('${root.path}/lab.json').readAsString()) as Map<String,dynamic>;
    final f=jsonDecode(await File('${root.path}/fixture/accounts.private.json').readAsString()) as Map<String,dynamic>;
    final reset=jsonDecode(await File('${root.path}/fixture/reset-from-phone.private.json').readAsString()) as Map<String,dynamic>;
    original=f['positive'] as Map<String,dynamic>;
    expect(reset['status'],'C_COMMITTED_UI_CONFIRMED');expect(reset['accountId'],original['accountId']);
    final trust=SecurityContext(withTrustedRoots:false)..setTrustedCertificates('${root.path}/material/dev-ca.pem');
    api=HttpAuthApi(communityBaseUri:Uri.parse('https://127.0.0.1:${cfg['ports']['proxy']}'),verifierBaseUri:Uri.parse('https://127.0.0.1:${cfg['ports']['v']}'),client:HttpClient(context:trust),passkeyRpId:'hnuhole-community-passkey.pages.dev');
    final store=AuthStore(_ReadOnlyFixtureVault(File('${root.path}/fixture/positive.vault.private.json')),scope:'owned-stage3-fixture-positive');
    oldToken=(await store.read()).session!.token;store.dispose();
  });
  test('real C rejects original password after actual native recovery reset',() async {
    final id=AuthCrypto.randomEncoded(16),key=AuthCrypto.randomEncoded(32);
    final journal=File('${root.path}/fixture/old-password-check.private.json');expect(await journal.exists(),isFalse);
    await journal.writeAsString(jsonEncode({'installationId':id,'idempotencyKey':key,'status':'STARTED_DO_NOT_REPLAY_IF_UNKNOWN'}),flush:true);
    await expectLater(api.login(username:original['username'] as String,password:original['password'] as String,installationId:id,idempotencyKey:key),throwsA(isA<AuthFailure>().having((e)=>e.unauthorized,'real C unauthorized',true)));
    await journal.writeAsString(jsonEncode({'installationId':id,'idempotencyKey':key,'status':'KNOWN_UNAUTHORIZED'}),flush:true);
  });
  test('real C rejects original recovery code after confirmed replacement',() async {
    await expectLater(api.createCodeResetIntent(original['recoveryCode'] as String),throwsA(isA<AuthFailure>().having((e)=>e.unauthorized,'real C unauthorized',true)));
  });
  test('old registration session is unauthorized; it was already replaced before reset',() async {
    await expectLater(api.currentSession(oldToken),throwsA(isA<AuthFailure>().having((e)=>e.unauthorized,'real C unauthorized',true)));
  });
}
