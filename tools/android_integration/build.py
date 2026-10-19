#!/usr/bin/env python3
"""One configured main.dart Android candidate; credentials and fixture defines are never inputs."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'prerelease'))
from candidate import run, sha, require
from device_candidate import load_config
from policy import bind_public_configuration, owned_tool_environment

BASE='1a810944787eacb66e2115e1ce77de08190c366a'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',type=Path,required=True)
    p.add_argument('--tool-root',type=Path,required=True)
    p.add_argument('--lab-root',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True)
    p.add_argument('--signing-dir',type=Path,required=True)
    a=p.parse_args()
    owned_tool_environment(a.tool_root,os.environ)
    config_path=a.lab_root/'public-config.json';config=load_config(config_path)
    state=json.loads((a.lab_root/'state.private.json').read_text())
    require(state.get('integrationScope')=='android-integration-20261019' and state['sourceSha']==BASE,'fixed configured task backend required')
    require(state['target']=='restore','targeted new-data restore must finish first')
    evidence=json.loads((a.lab_root/'integration-restore-evidence.json').read_text())
    bind_public_configuration(config,state,evidence,(a.lab_root/'material/dev-ca.pem').read_text())
    require(evidence['result']=='PASS_SCOPED_NEW_COMMENT_MODERATION_RESTORE','new-impact evidence required before single build')
    require(not a.out.exists(),'candidate already exists; reuse the fixed artifact')
    env=dict(os.environ)
    relay=json.loads((a.tool_root/'relay-owner.json').read_text())
    env.update(HTTPS_PROXY='http://127.0.0.1:'+str(relay['port']),https_proxy='http://127.0.0.1:'+str(relay['port']))
    for name in list(env):
        if 'FIXTURE' in name or name in ('DART_DEFINES','ORG_GRADLE_PROJECT_hnuholeCommentsValidation') or name.startswith('HNUHOLE_TEST_'):
            del env[name]
    builder=a.source/'tools/prerelease/device_candidate.py'
    subprocess.run([sys.executable,str(builder),'--source',str(a.source),'--source-sha',BASE,'--out',str(a.out),'--config',str(config_path),'--tool-root',str(a.tool_root),'--signing-dir',str(a.signing_dir),'--build-number','2026101901'],env=env,check=True)
    manifest=json.loads((a.out/'manifest.json').read_text())
    key_env=dict(env,HNUHOLE_TEST_STORE_PASSWORD=(a.signing_dir/'password.private').read_text())
    cert=run([Path(env['JAVA_HOME'])/'bin/keytool','-exportcert','-keystore',a.signing_dir/'test.jks','-storepass:env','HNUHOLE_TEST_STORE_PASSWORD','-alias','prerelease-device-test'],a.source/'apps/mobile',key_env,binary=True)
    require(hashlib.sha256(cert).hexdigest()==manifest['signingCertificateSha256'],'public signing certificate mismatch')
    (a.out/'test-signing-certificate.der').write_bytes(cert)
    shutil.copyfile(config_path,a.out/'public-config.json')
    manifest.update(result='PASS_CONFIGURED_FIXED_ANDROID_CANDIDATE',createdAtUtc=datetime.now(timezone.utc).isoformat(),
                    productSourceSha=BASE,deliveryRecipeSha256=sha(Path(__file__)),baseBuilderSha256=sha(builder),
                    fixtureCredentialsEmbedded=False,compileConfigurationKeys=['AUTH_COMMUNITY_BASE_URL','AUTH_VERIFIER_BASE_URL','AUTH_DEV_CA_BASE64'],
                    publicConfigurationSha256=sha(a.out/'public-config.json'),backendSourceSha=BASE,
                    backendBinarySha256={p.name:sha(p) for p in (a.lab_root/'bin').glob('candidate-*')},
                    backendPrivateConfigurationSha256={party:sha(a.lab_root/'material'/(party+'.json')) for party in 'cv'},
                    migrationSha256=state['migrationSha256'],migrationVersions={'C':18,'V':4},
                    newImpactEvidenceSha256=sha(a.lab_root/'integration-restore-evidence.json'),
                    deviceIntegration='NOT_RUN: new App governance entry/web disposition/App notice and appeal only; await actual device window',
                    inheritedCommentsEvidence='docs/design/comments-connected-verification-20261019.json',
                    inheritedModerationEvidence='docs/design/comment-report-verification-20261019.json',
                    pre0018BackendRollback='INCOMPATIBLE_REJECTED; keep fixed backend or forward repair; no Down',productionRelease=False)
    (a.out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    (a.out/'INSTALL.md').write_text('''# HnuHole Android 集成测试候选

真实 main.dart，固定产品源码1a810944，Android ARM64 / API29起，0.1.0+2026101901。
这是独立测试签名的普通App候选，debug模式用于App内CA；未包含合成账号、密码、token或私有验收fixture。不是正式发布包。

先检查SHA256SUMS和manifest，确认applicationId及测试签名证书摘要，再安装APK。
同包其他签名存在时不要覆盖或清数据；须先取得当时用户对卸载旧App及数据的明确授权。
通过本任务专用ADB server分别建立public-config.json中C/V两个loopback端口的reverse，再打开App。
不得暴露PG、内部mTLS、SMTP和Mailpit端口，不添加手机系统CA，不修改安全键盘或系统安全设置。

后端与运行材料单独私有保留，凭据由操作者另行取得，不编译进APK。
使用tools/android_integration/lab.py的start / recover / health / stop入口，只操作本任务标记的隔离实例；先核对配置、证书有效期和固定源码。
迁移为C18/V4，旧0018前后端回滚已被实测拒绝；保留当前后端或向前修复，不执行Down。
测试结束仅删除本任务reverse和临时文件，停止本任务服务/ADB；保留候选和证据。

评论既有原生恢复/单图等验收沿用原版本证据，本包设备阶段仅补新增治理连接。
跨设备Passkey、iOS、多机型和生产验证不在本轮。
''',encoding='utf-8')
    files=sorted(p for p in a.out.iterdir() if p.name!='SHA256SUMS')
    (a.out/'SHA256SUMS').write_text(''.join(sha(p)+'  '+p.name+'\n' for p in files))
    print('Single configured fixture-free integration APK built and verified; actual device integration still NOT_RUN',flush=True)


if __name__=='__main__':main()
