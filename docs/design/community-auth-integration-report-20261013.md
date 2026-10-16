# 社区与认证候选联合验证报告

2026-10-13，Asia/Shanghai，codex/community-flutter-pages。**联合主机回归和原生构建PASS；单台Android设备验收由用户明确延期。**第二实体Android、iOS、生产部署不纳入本轮通过。没有使用手机/ADB，没有部署或发布Release。

原HEAD：4d58116bdde2c1d2d406b965590bc1625a5c7955。20文件已审查、保存并正常推送为7452dadefb52e7b695cdd1079d21083fcb6cae02。固定认证候选：d859cb05c772cdf8d8b75e439a2bfedf0414dd46，共同祖先0eff47a21cd4f4ab1636b4468f7d5df9769a264f。整合使用三方merge，处理main/settings和四份交接冲突，保留社区布局、AuthFlows闭号owner/callback、业务vault、0013及最小权限。没有访问认证变化中工作树或整枝覆盖。整合后源码提交为28cee4656edd710d60676a81794c20cd49f45351，已正常推送并核对远端；后续仅补入文档/台账回执，运行输入不变。测试执行时HEAD仍为社区保存提交、合并源码未提交，随后逐项摘要核对443项输入与已提交整合源码一致。

[机器记录](community-auth-integration-20261013.json)、[源码指纹](community-auth-integration-source-fingerprint-20261013.json)、[固定SHA差异清单](community-flutter-f4-auth-integration-diff-20261012.md)、[设备清单](community-single-android-acceptance-20261013.md)。最终443项源码/测试/配置输入指纹599757bf3bb84043d5903e8dad375b0650b469dc5088fcc82a16f1b45e1173c7。平台文件被纳入指纹不代表平台执行；原311和认证22/0/2不计联合运行结果。

## 当前实际验证

| 检查 | 结果及范围 |
|---|---|
| checks | mobile分析0问题，21文件320项非隐藏测试PASS、FAIL0/SKIP0 |
| auth-regression/R05 | 新PG，真实Dart/TLS C/V handler/SQL复合流程与日志隐私PASS；vault主机替身 |
| integration | 两个Flutter主机进程、生产HnuholeApp、文件SQLite、真实TLS/SQL，F4-H01至H08本轮8项PASS；CREATE/DELETE各一次，丢提交响应2、查询响应2 |
| server | 完整go test -race -count=1 -timeout=20m -p 1 ./...及内置vet，6包PASS；authprivacy1022.300s。mobile opt-in和受限posts runtime由独立stage执行 |
| posts-privileges | 真实受限C runtime，9顶层及4生命周期子例PASS，0失败；业务/recovery越权拒绝 |
| auth-runtime/R03 | 真实cmd/api、cmd/verifier、正式Goose迁移/受限角色、HTTPS/mTLS、Gate、重启/升级/关闭/日志，25个命名断言PASS，含新增文字12至13升级和实际worker/SQL；仅清其自身project/目录 |
| 最终vet | 08:13:23Z结束，退出0，覆盖最终Go源码 |
| 插件/工具/契约 | auth_passkey/auth_vault分析PASS；Passkey Dart9；vault无独立Dart测试目录不计PASS。109宿主守卫、诊断构建8、JVM策略24、合成runner guard17、完整OpenAPI5份PASS |
| 原生构建 | 标准main Debug ARM64和未配置生产签名的Release ARM64均PASS；Release manifest/DEX无GoogleFido诊断类。两个独立包名instrumentation APK构建/签名/runner核对PASS，实际原生用例尚未执行 |
| 设备候选 | org.hnuhole.hnuhole_mobile.communityf5独立包构建PASS；195项产品/测试输入与最终源码一致，仅applicationId构建overlay不同，使用本任务新调试签名与自建CA/loopback配置，尚未启动对应数据库/服务或使用设备 |

首轮checks/R05/integration之后只有完整server预算和两项宿主测试输入/guard改变；App、Go产品、SQL和协议源码未改，逐文件对照PASS。受影响宿主109/runner17和server重跑，后续posts/R03/final vet在最终代码执行。标准/隔离APK没有将构建overlay写回仓库。pubspec.lock、go.mod、go.sum及实际构建pubspec/lock保持原版本。机器记录保留每个命令、时间、退出码、输入范围与日志；不能把指纹包含范围当作全文件运行覆盖。

原F4 fixture的raw summary仍输出固定null/BLOCKED_DEPENDENCY交接字段，该字段不执行候选真实性检查；原始输出原样保留。当前来源由固定Git S/D、三方差异及443项指纹独立绑定，不借此字段宣称设备/完整App通过。

## 命令、日志与隔离

实际命令模式：

```powershell
wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/integration-20261013/run-stage.sh checks
```

依次替换为auth-regression、integration、server、posts-privileges、auth-runtime、vet；wrapper调用仓库tools/run-community-flutter-f4-linux.sh同名入口。新R03入口将当前compose复制到专用源码镜像，使用原已有postgres16.6-alpine/Mailpit1.21.8缓存镜像及Goose3.22.1，不拉新镜像。

日志目录：E:/HnuHole-community-f4-20261012/integration-20261013/logs。每stage有console.log、exit-code及详细log；另外有mobile-tests.jsonl、joint-mobile-counts.json、main-https-summary.json、host-guards.log、runner-guards.log、passkey-tests.jsonl、openapi.log、jvm-policy.log、标准/仪器/设备候选APK摘要与manifest、签名及边界记录。完整外部执行脚本在同一任务目录，小型脱敏结果进入仓库，APK/数据库/私钥/缓存和原始长日志不入Git。

C盘开始约3.5GiB余量，后续约3.2GiB；E盘约167GiB起始余量。WSL VHD在E盘。SDK/JDK/验证Python公开库只读复制到/home/hnuhole/community-auth-integration-20261013-tools，SDK bin/cache独立。任务根/home/hnuhole/hnuhole-community-flutter-f4-20261013，HOME/XDG/TMP/PUB/Go/Gradle/Android user均独立，PG私有socket端口55443/TCP关闭，R03动态端口及独立Docker project、新C/V库和合成材料。没有认证库/账号/签名/恢复材料、其他服务或全局PATH/代理/证书/系统变更。

## 保留的失败与修复

1. R05首次PG启动失败：socket108字节超Linux最大107。空的新一次性集群重现并保存日志；只缩短本任务目录，之后R05/integration通过。
2. 宿主守卫首次4项错误：历史认证构建器只接受其已审阅34依赖锁，测试误读了当前社区锁。测试夹具改为固定D的原锁，新增当前社区锁仍被该旧构建器拒绝的负向例；构建器允许名单和安全判断未改，产品锁未改，109通过。该历史构建器不能用来构建联合候选。
3. server首轮10分钟整包超时，当时当前用例21秒、栈在真实fsync；没有断言失败。完整包预算设20分钟，可配置范围仅1至30分钟，拒绝0/无限值；所有race/count1/p1、测试、Gate/SQL时限和同步仍保留。全量重跑通过，失败和栈保留。
4. Android Debug首次锁定SQLite3.7.0 arm64库GitHub下载超时；Windows取同一1.8MB官方文件，SHA256与包内固定0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161一致，置入本任务cache，hook再次校验。未改hook/锁/版本。Gradle9.3.1只读复制现有公开ZIP，核官方SHA256 b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06。
5. Release首次沿用--no-pub，debug integration_test注册表进入release。按认证交接已说明的正常release命令重新生成注册表，通过；锁/pubspec未变。SDK XML版本警告保留，未升级SDK掩盖问题。
6. 初次Linux archive静态检查读取了iOS Classes符号链接目标，而原Windows证据记录Git link文本。按精确Git blob及独立临时索引复验三个原认证交接检查器均PASS，没有改检查器/旧证据，不证明iOS。它们验证固定D原材料，不能在联合源码上将D历史摘要改成当前通过。

## 设备延期与后续条件

用户明确选择“暂不提供设备窗口；先提交推送整合成果，设备验收保持待执行”。手机安装/使用/重启、native business7/auth16/Passkey12、实际main启动/自动poll、中文输入及各业务路径均NOT_RUN/DEFERRED_BY_USER。构建或主机替身不代证原生运行；没有新增单设备PASS。

后续先从本分支固定整合SHA重建独占工具与本任务隔离包，核对源码/配置/APK/签名；再次确认具体设备、30至45分钟窗口、认证已释放、包名/数据影响与整机重启许可，再执行设备清单的CA-A01至A13。仅使用新一次性C/V库和合成账号，正式注销保持原七天期限/普通worker，测试可信时间推进与自然等待区分。

新任务签名/包名没有独立公开RP关联。系统Passkey正向需要先准备本任务RP/package/signature关联差异并获明确授权，不复用认证签名或以旧22项/codec替代。第二实体AndroidNI-X01/X02、iOS/macOS/Xcode/签名、生产分权/灾备/审计、Release发布和main合并仍不在本轮通过范围。评论、私信、图片、搜索、推送等未实现业务没有新增。

本轮只保留源码、测试及小型脱敏交接；专用缓存/SDK/APK/测试签名和合成材料的最终清理以机器记录与外部cleanup记录为准，不能将已清缓存作为下轮现成环境。共享SDK、现成工具、认证fresh环境、手机及原数据保留。
收尾回执：[Git交付与清理记录](community-auth-integration-delivery-20261013.json)。整合前提交7452dadefb52e7b695cdd1079d21083fcb6cae02、整合后源码28cee4656edd710d60676a81794c20cd49f45351均已正常推送；没有并行远端修改、强推或main合并。三处已核canonical/owner的任务根清理PASS，合计约11.07GiB逻辑文件；SDK副本、缓存、APK、合成签名/CA材料、静态候选tar与原生下载已删除，源码与小型证据/外部脚本保留。第一次清理因Go模块缓存只读目录阻止unlink而中断；重核marker/无进程后只给专用树目录恢复owner写/执行位，重试成功，初次记录保留。未清共用SDK、认证目录、未知Docker、设备或全局WSL，没有VHD压缩。之后文档回执提交不改运行输入；最终HEAD以Git历史及外部final-delivery.json为准。单台Android继续NOT_RUN_USER_DEFERRED，第二实体Android、iOS与生产继续不在通过范围。