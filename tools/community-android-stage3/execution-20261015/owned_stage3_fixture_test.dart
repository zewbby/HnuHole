import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hnuhole_mobile/hnuhole_mobile.dart';
import '../integration_test/owned_auth_device_helpers.dart' show smtpOtp;

class _FixtureOnlyVault implements AuthVault {
  _FixtureOnlyVault(this.file);
  final File file;
  @override Future<String?> read() async => await file.exists() ? file.readAsString() : null;
  @override Future<void> write(String value) => file.writeAsString(value, flush: true);
}

void main() {
  test('create two fresh owned synthetic account fixtures through unchanged real AuthFlows', () async {
    final root = Directory('/home/hnuhole/community-android-stage3-execution-20261015/lab');
    final cfg = jsonDecode(await File('${root.path}/lab.json').readAsString()) as Map<String,dynamic>;
    final fixturesFile = File('${root.path}/fixture/accounts.private.json');
    final fixtures = jsonDecode(await fixturesFile.readAsString()) as Map<String,dynamic>;
    final ports=cfg['ports'] as Map<String,dynamic>;
    for (final tag in ['negative','positive']) {
      final f=fixtures[tag] as Map<String,dynamic>;
      expect(f['status'],'PREPARED_NOT_RUN');
      f['status']='STARTED_DO_NOT_REPLAY';await fixturesFile.writeAsString(jsonEncode(fixtures),flush:true);
      final trust=SecurityContext(withTrustedRoots:false)..setTrustedCertificates('${root.path}/material/dev-ca.pem');
      final api=HttpAuthApi(communityBaseUri:Uri.parse('https://127.0.0.1:${ports['proxy']}'),verifierBaseUri:Uri.parse('https://127.0.0.1:${ports['v']}'),client:HttpClient(context:trust),passkeyRpId:'hnuhole-community-passkey.pages.dev');
      final channels=HttpChannelRepository(baseUri:Uri.parse('https://127.0.0.1:${ports['proxy']}'),client:HttpClient(context:trust));
      final store=AuthStore(_FixtureOnlyVault(File('${root.path}/fixture/$tag.vault.private.json')),scope:'owned-stage3-fixture-$tag');
      final directory=ChannelDirectoryController(repository:channels);
      final sessions=AuthSessionController(api:api,store:store,directory:directory);
      final flows=AuthFlows(api:api,store:store,acceptRegistrationSession:sessions.acceptSession,clearCommunityAccess:sessions.clearCommunityAccess);
      await sessions.start();expect(sessions.status,AuthStatus.signedOut);
      await flows.requestOtp(f['email'] as String);expect(flows.status,AuthFlowStatus.otpRequested,reason:'Owned request status only: ${flows.status.name} ${flows.error?.code}');
      final code=await smtpOtp(Uri.parse('http://127.0.0.1:${ports['mail']}'),f['email'] as String);
      await flows.confirmOtp(code);expect(flows.status,AuthFlowStatus.eligibilityReady,reason:'Owned confirmation status only: ${flows.status.name} ${flows.error?.code}');
      await flows.createRegistration(f['username'] as String,f['password'] as String);expect(flows.status,AuthFlowStatus.registrationCodeShown,reason:'Owned registration status only: ${flows.status.name} ${flows.error?.code}');
      f['recoveryCode']=flows.recoveryCode!;f['status']='CODE_PREPARED_NOT_COMMITTED';await fixturesFile.writeAsString(jsonEncode(fixtures),flush:true);
      flows.hideRecoveryCode();await flows.commitRegistration(f['recoveryCode'] as String);
      expect(sessions.isAuthenticated,isTrue,reason:'Owned commit status only: ${flows.status.name} ${sessions.status.name}');
      f['status']='REGISTERED_REAL_AUTHFLOWS';f['accountId']=store.current!.session!.accountId;
      await fixturesFile.writeAsString(jsonEncode(fixtures),flush:true);
      flows.dispose();sessions.dispose();directory.dispose();store.dispose();
    }
  },timeout:const Timeout(Duration(minutes:3)));
}
