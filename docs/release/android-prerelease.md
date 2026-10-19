# Android候选与隔离预发布

2026-10-19：本地隔离演练、独立CI后台演练、测试签名候选构建，以及vivo S18最小文字/单PNG手机链路均有实际限定证据；未合并、未正式发布。结果必须对应精确源码SHA。
设备实测详见[手机报告](android-device-validation-20261019.md)及[机器记录](android-device-validation-20261019.json)；CI release、手机debug包和后台演练分开归档。下方历史NOT_RUN保留其原时点。

后续核对main已到`1b78f422dccff1f5598e3a52a9dc2ae7a928e4d1`（PR #18），正式迁移为C0015/V0004。
本任务已同步；14f5096的新root已实际通过13项检查、75份恢复摘要和五实例停机，专属手机包也已构建验签。下方schema14记录保留原SHA。
环境启用实际合入的`moderation=true`及`grant-moderation.sql`，没有创建管理员或部署管理网页，
不新增治理业务。新增精确治理表/列/sequence/function权限矩阵和不可变证据列的实际越权负审计，
备份摘要覆盖全部非系统schema；治理业务端到端范围另按既有CI/实际测试记录，不由文字图片smoke代替。

## 候选构建

独立 [workflow](../../.github/workflows/android-prerelease.yml) 在相关PR运行，合入main后也可手动指定SHA，
指定提交checkout后保留Pub锁，构建真实 `lib/main.dart` ARM64 release APK并临时测试签名。
最终APK读取包名/版本/minSdk/备份排除/证书摘要，附制品SHA256及锁文件摘要。
输出只上传APK、manifest和SHA256SUMS；私钥不上传且构建后删除。
测试证书每次不同，不能用作相同包的稳定升级签名。

当前编译默认API为 `.invalid`，未连接真实服务，release保持正常系统TLS验证；
这只验构建交付，不等于手机业务闭环。设备窗口前须准备本任务专属debug/pinned-CA候选、
独立端口和测试签名，不改变正式包的Passkey身份或系统信任设置。

## 私有Linux环境

先显式准备 Go1.22.2、Goose3.22.1、PG16、Mailpit1.21.8、Python3和独立venv，
venv按 `services/api/media/requirements.txt` 安装固定Pillow。工具不隐式安装依赖。
所有Go缓存变量显式指向本任务目录；先 `go mod download`，演练内固定GOPROXY=off。
使用非root用户、Linux文件系统、规范绝对新路径，父目录先存在。

```sh
export GOCACHE=/absolute/owned/go-build
export GOMODCACHE=/absolute/owned/go-mod
export GOPATH=/absolute/owned/go-path
export PRERELEASE_IMAGE_PYTHON=/absolute/owned/python/bin/python
export GOTOOLCHAIN=local GOPROXY=off
# 当前已合入main的完整SHA，作为实际回滚二进制来源
python tools/prerelease/environment.py --root /absolute/new-lab init --rollback-sha FULL_MAIN_SHA
python tools/prerelease/environment.py --root /absolute/new-lab rehearse
```

`init`从正式迁移初始化C/V，另外将schema13实际备份装入新C实例再前向升级；
不添加业务迁移、占位表或运行down。源库、升级库、恢复库均归该root，PG只监听loopback及私有socket。
`rehearse`运行真实HTTPS合成注册/登录/目录/文字/图片上传和原字节读取，
冻结拒绝、停写备份、两个新实例恢复、全表/sequence数据摘要及schema/权限检查、旧token拒绝与重新登录，
再运行实际失败部署、旧main二进制回滚和候选重部署。只保留开发同机证明范围。

手动启停可复用同一root：

```sh
python tools/prerelease/environment.py --root /absolute/new-lab start
# init后仍FROZEN；仅显式recover才开放Gate并推进代次
python tools/prerelease/environment.py --root /absolute/new-lab recover
python tools/prerelease/environment.py --root /absolute/new-lab health
python tools/prerelease/environment.py --root /absolute/new-lab stop
```

仅 `evidence.json`可脱敏发布；root里的其他文件包括合成密码、密钥、库、邮件和大日志，均不能提交。
备份恢复保留同任务的加密/HMAC/协议key和Gate锚点，只改目标DSN；新建key不能冒充旧数据恢复。
应用回滚与数据库兼容分别核验；旧二进制若不能通过当前schema/权限/startup检查，阻止回滚并前向修复或恢复。

## 未验范围

本轮仅指定debug包的安装/注册登录/中文输入/文字与单PNG/Picker/Gal原字节/进程重开通过；完整原生存储安全、物理UX全套、多图动画、同包升级、系统重启/OEM及本候选Passkey仍NOT_RUN；跨设备Passkey和iOS延期。
schema13快照仅合成目录/迁移历史，不含真实用户历史数据。真实云、正式签名、生产主体独立、
外部独立备份运营与正式发布不属于已获批准的本地演练。媒体仍沿用现有SQL存储。

## 2026-10-18首轮schema14发布记录（历史候选，未正式发布）

任务为 [PR #16](https://github.com/zewbby/HnuHole/pull/16)，创建基线8fa9cbc；已同步实际合入的
PR #13/main 986477b。该轮正式迁移C0014/V0004；0015/0016未进入该轮源码，不预建占位表。

| 检查 | 被测版本与实际结果 | 证据 |
| --- | --- | --- |
| 本地完整隔离演练 | 0d107191556b650fb0e8363e46dc6fc2f510baf0；11检查PASS、60份表/sequence恢复摘要一致 | [本地机器回执](android-prerelease-local-20261018.json) |
| 独立CLI启停 | 同一0d10719，start/recover/health/stop四个独立进程调用均exit0 | [启停回执](android-prerelease-manual-lifecycle-20261018.json) |
| 独立CI后台 | 6b2927c；原Go test/build/vet、真实PostSchema/image SQL、11项实际进程演练PASS | [CI机器回执](android-prerelease-ci-rehearsal-20261018.json)、[运行39115461923](https://github.com/zewbby/HnuHole/actions/runs/39115461923) |
| 工具回归 | Linux6/6 PASS；Windows5 PASS、1项POSIX明确SKIP | tools/prerelease/tests |
| 独立审查 | REVIEW_PASS_SCOPED，清理错误路径等阻断已修复 | [审查记录](android-prerelease-review-20261018.json) |
| Android候选 | 6b2927c，实际main.dart ARM64 release构建/测试签名/验签/元数据核对PASS；下载后再次核APK SHA256与大小 | [制品manifest](android-candidate-20261018.json)、[运行39115461923](https://github.com/zewbby/HnuHole/actions/runs/39115461923) |

首个成功候选：0.1.0+2026101801、包名org.hnuhole.hnuhole_mobile、minSdk29/targetSdk36，
APK22531056字节，SHA256 `f7a723c304c6a832e025eb2290263fa774a36dc0a8477a1f73f3d9e2d4ae8890`；
测试证书SHA256 `85175259ca806c6ad43a687e080904a6622cf8850f6bdc4745a1cba43c2a783c`。
[下载CI制品](https://github.com/zewbby/HnuHole/actions/runs/39115461923/artifacts/12132147995)（30天保留）；
本地副本位于 `E:/HnuHole-android-prerelease-20261018/runtime/candidate-6b2927c/`，不进入Git。
证据提交后的最终head另以PR当前检查和对应manifest为准；每轮临时证书不同，勿将不同制品摘要混用。

演练使用非root Linux目录下独立Go1.22.2、Goose3.22.1、PG16.15、Mailpit1.21.8、Pillow12.3.0。
源C/V、恢复C/V、旧快照升级C共五个新实例，所有进程/数据库/缓存/私钥均属于本任务。
实际路径为 `/home/hnuhole/android-prerelease-20261018-runtime/lab-07`；当前五个PG和应用/邮件/证据进程均已停，
私有材料保留供后续设备准备。不得将这些材料上传或连接其他任务库。

执行内容包括：正式迁移及重复up，schema13真实dump装入新实例后up至当前schema并保留七目录；
完整角色矩阵拒绝额外immutable列UPDATE、实际cmd拒绝缺失图片INSERT权限；合成账号注册/登录/身份/七目录，
真实worker公开文字和单张PNG、受保护读取原字节、上传token拒读；Gate冻结503；停写后的C/V实际备份，
分别恢复两个新实例并核对全表和sequence数据摘要及schema/权限检查；显式recover后旧token401、重新登录读取原文字和图片；
错误validator摘要候选实际启动失败，旧main 986477b的C/V二进制在当前恢复库通过健康/原图读取，
随后重新切回候选并通过健康/读取。只切换应用二进制，不执行down迁移。

该历史轮次的候选与回滚版本业务源码及迁移相同；这证明本轮二进制切换/故障拒绝和schema14兼容，
不证明未来0015/0016或未知历史数据库兼容。完整业务/动画多图/跨账号访问、原生Picker/Gal/vault/物理设备、
固定生产端点/正式签名/安装升级及生产灾备仍未验。APK当前默认.invalid不连接本地服务，后台smoke不冒充APK链路通过。

失败历史保留：首轮工作流runner上下文解析失败；6426918的API35缺失与libpq空格编码失败；
dee7fdc后台PASS但Android缺CMake3.22.1失败；4c9477a的release dev插件注册失败。
后者采用Flutter官方[issue169336](https://github.com/flutter/flutter/issues/169336)的config-only路径，
保留先行enforce-lockfile和配置前后锁/源码一致性校验，不手改生成代码。均修复后重跑，失败不计PASS。
本地早期源码提取、libpq、Mailpit版本参数和审计匹配守卫失败保留在同任务私有目录，后续精确SHA回执取代其验收结论。

## 2026-10-19设备窗口执行前方案（历史准备快照）

用户指定设备为vivo S18 / OriginOS 5，当前不能配合验证，已授权先准备测试包；
实际Android版本/API/ABI、安装和APK服务链路仍NOT_RUN。已保留本轮非手机证据并构建专属debug/pinned-CA候选：
仅loopback HTTPS、专属测试签名、明确的USB服务/key和单机端口映射；不装系统CA、不开放数据库/内部mTLS。
安装前核对目标包现状，避免覆盖其他任务App或数据。验证安装启动、合成注册/登录、文字/图片最小链路和重开，
逐项保存当前APK/源码/证书摘要；结束后只撤本任务映射并停止本任务服务。跨设备Passkey和iOS继续延期。
此方案尚未执行手机操作，等待本session设备窗口；手机专属工具只下载到本任务独立目录，不借用其他session工具。

### 不连接手机准备测试包

`device_candidate.py`只构建/验签，不运行ADB、服务或设备探测。与release候选分开归档，
仍使用真实`lib/main.dart`、原applicationId和认证逻辑；`HNUHOLE_PRERELEASE_DEVICE=1`显式选择测试label和签名，
替换debug Manifest以去掉历史GoogleFido诊断Activity及DAL元数据声明。旧诊断类/资源可能仍被打包，
不宣称已移除其全部代码。不开启RP override，不装系统CA，不放宽TLS或Gate。

所有HOME/Flutter/JDK/Android SDK/Pub/Gradle缓存必须落在指定的私有`--tool-root`；
版本沿用Flutter3.47.5、JDK17、Android35/36、build-tools36.0.0、NDK28.2.13676358、CMake3.22.1。
先在同一独立环境执行`flutter pub get --enforce-lockfile`。配置文件只接受以下三个公开字段：

```json
{"communityOrigin":"https://127.0.0.1:52045","verifierOrigin":"https://127.0.0.1:37073","caPem":"-----BEGIN CERTIFICATE-----\n本任务公有CA的PEM内容\n-----END CERTIFICATE-----\n"}
```

```sh
python tools/prerelease/device_candidate.py --source /owned/clean-source --source-sha FULL_SHA \
  --config /owned/device-public-config.json --tool-root /owned/private-tool-root \
  --signing-dir /owned/private-signing --out /owned/new-device-artifact --build-number 2026101802
```

工具拒绝HTTP、非loopback、相同C/V origin、额外配置字段和私钥PEM；签名目录带归属marker，
私钥和密码保留在私有目录供本session后续构建，输出目录只有APK/manifest/SHA256SUMS。
最终元数据核对debug模式、原包名/版本/minSdk、备份排除、测试label、禁明文和诊断/DAL声明缺席。
安装前检查手机现有同包签名和归属；冲突时暂停，不卸载、清数据或强制覆盖。

当前lab-09为恢复后的非空数据库，`target=restore`；不要重跑`init`或包含初始化的`run-local.sh`。
C/V固定端口52045/37073，公有CA PEM SHA256为`da2215084e59bc56c6aeca048eefd2c6f8b1de2505ae46f5e8edcfa932c7a3ac`。
现有C/V叶证书到2026-10-25 23:38:00（上海）到期，CA到11-17；窗口前重新检查实际证书有效期。
叶证书到期必须使用本任务CA续签并验证，不得跳过证书校验；CA更换则重建并重新核包摘要。
当前进程已停止。窗口内先start/recover/health并严格核验Windows到WSL HTTPS，再建立本任务两条USB映射。
不映射数据库、邮件或内部mTLS；设备端口冲突同样阻断，结束只撤本任务映射并停本任务进程。

## 0015同步后的实际结果与2026-10-19设备包（下列手机NOT_RUN为准备时状态）

后端演练源码`14f5096bb65aa53743939031000d6df32e42ad4b`；设备包源码`8691eb49d3863b911e04c4678512c1eb8d54aaca`，仅追加debug准备复用已锁依赖的flag。
已同步PR #18/main1b78f42；正式迁移C0015/V0004，0016尚未进入该轮main。
新环境`/home/hnuhole/android-prerelease-20261018-runtime/lab-09`完整13项PASS、75份表/sequence摘要一致，
覆盖合成PENDING举报、原图片证据、通知及已读状态的真实HTTPS写入→备份→新实例恢复，
恢复后旧token拒绝、fresh login、已有main1b78f42二进制回滚和候选重部署读取均PASS，五个PG及其他进程已停。
见[本地回执](android-prerelease-schema15-local-20261018.json)。非空处罚/申诉/管理员角色/治理audit恢复仍NOT_RUN，
实际GoSQL和既有Dart/browser CI结果分别记录，不外推成手机或完整治理验收。环境回滚不执行down；
既有SQL回归只在自己的升级fixture核验0015 Down明确拒绝。

手机包`0.1.0+2026101802`、debug、Flutter目标`android-arm64`（含JNI附带的其他ABI库）、原包名`org.hnuhole.hnuhole_mobile`、测试label`HnuHole Prerelease Test`；
实际main.dart构建、测试签名验签、最终Manifest及源码/锁文件不变检查PASS，结果`PASS_NON_DEVICE_PREPARATION`。
C/V固定`https://127.0.0.1:52045`/`https://127.0.0.1:37073`，仅App内CA，无RP override、无系统CA。
APK SHA256 `d80c47283e22007dfbc5cebf6ccb96f82b70b917b9a1efe1a85af0cd971cd18a`，98479040字节；
测试证书SHA256 `09309fe3ac7e4f817e81cdadd406ccae28ca465ab591701d233ea1527660397c`。
完整公开元数据见[手机包manifest](android-device-candidate-20261019.json)；本地APK/manifest/SHA256SUMS保存在
`E:/HnuHole-android-prerelease-20261018/runtime/device-candidate-8691eb4/`，私有签名不进入Git。
该原始manifest中的`authenticationIdentityChanged=false`仅表示applicationId及RP配置未改；
测试签名证书与正式签名身份不同，不能据此声称Android凭据来源或Passkey身份等同。原始manifest及其摘要保留不改写。

用户目前不能测，目标仅由用户报告为vivo S18 / OriginOS 5；实际Android API/ABI、安装、重开、原生存储、Picker/Gal、
APK→服务文字图片与Passkey全部NOT_RUN。未运行ADB、未连接手机。仍需先核同包归属；冲突暂停，不覆盖其他任务数据。

新失败历史：lab-08恢复时精确审计发现`--no-privileges`丢失PUBLIC函数EXECUTE撤销，未放宽审计；
现由本任务恢复流程显式重建deny ACL后应用主线canonical grants，lab-09重跑通过。
本地回归初次缺图片fixture、随后提前设置Goose触发无DSN保护，均保留FAIL日志，纠正入口环境和顺序后重跑。

[宿主/真实SQL回归](android-prerelease-schema15-regression-20261018.json)及[Windows到WSL严格HTTPS与独立启停](android-prerelease-schema15-host-preflight-20261018.json)已通过；本地Dart/browser专用入口明确SKIP，既有治理CI单独核对，不计入本地通过项。
WSL官方Gradle下载超时后，从同一官方URL经Windows新下载并核对wrapper固定SHA256，放入本任务缓存。
后续Maven下载临时使用本任务loopback CONNECT转发至Windows网络，TLS仍端到端验证；构建后关闭转发，不修改系统代理/证书或原依赖仓库。

8691eb4的8个产品/协作检查全部SUCCESS，含既有治理Dart/browser专用CI；见[按源码保存的检查回执](android-prerelease-checks-8691eb4.json)。
该轮[CI运行39143627400](https://github.com/zewbby/HnuHole/actions/runs/39143627400)实际后台演练同样13项/75摘要PASS，
见[CI演练回执](android-prerelease-schema15-ci-8691eb4.json)。下载的release APK、manifest及SHA256SUMS已重新核验，
APK22924620字节，SHA256 `005f22bfc9cbce39b48d1a3bd32a0088bf4e8bcd4d525b02be69e4e0c3163618`；
完整来源/临时证书见[CI候选manifest](android-candidate-schema15-ci-8691eb4.json)，该release仍使用.invalid默认服务。
它与上方已配置CA/端点的手机debug包是不同制品，不混用摘要或安装说明。

[独立审查](android-prerelease-review-20261019.json)分别只读核对后端实物证据、APK及文档限定，无剩余阻断；
agent审查不等于GitHub成员批准。文档交付提交后的最终head仍须在[PR #16](https://github.com/zewbby/HnuHole/pull/16)核对全部检查，
上述8691结果只属于其精确源码。PR保留draft，未合并、未正式发布。


## 2026-10-19实际手机验收补充

用户开放vivo S18窗口，实际V2323A/Android15/API35、ARM64；使用既存8691eb4 debug包和14f5096 lab-09，
main仍为1b78f42/C0015/V0004。11项限定设备检查通过，详见[报告](android-device-validation-20261019.md)。
两个合成帖子、1张PNG、1身份/1活跃会话真实入库；PNG选图→SQL payload→Gal MediaStore原字节SHA256均为
`994bd517ee5da474608ad4aa8d5d50fd6a68a69e1ad6e11f80a5b2d049e62e27`，5049字节。
实际新进程重开保留登录，退出SQL会话0、重登后1；凭据版本保持1，没有重设密码或诊断写库。

自动输入曾截短40位密码为38位，用户看到“账号密码不正确”；保留FAIL，重新聚焦核对完整40位后通过正常UI重登。
没有以离线密码比较代证手机登录。旧“我的”路由在退出/重登后仍保守失效；返回首页重新进入通道后两个帖子和大图可读，
不声称旧路由自动恢复或全App无缺陷。手机端负TLS/Gate冻结、完整原生安全、多图/TalkBack全套仍未验。

原包名已有旧测试签名；用户明确授权卸载旧App及本机数据后才做全新安装，因此不证明同包升级。
Windows工具新下载在本任务目录，专用ADB5049仅使用既有OS profile USB身份，metadata不变；操作者未复制/读取/哈希key，
没有新建OS账号或改全局调试设置。只映射C52045/V37073，无PG/邮件/内部mTLS映射。

窗口已结束；本任务临时媒体/UI文件、两条reverse和专用ADB已收回，五个PG均status3、C/V及watch/mailpit等自有进程已停。
保留测试App及私有工具/库/签名，不能因保留安装而声称后台持续在线。后续新窗口先核归属、端点和证书，不自动沿用授权卸载其他包。
原准备manifest及CI release的NOT_RUN不改写；本轮手机结果仅属于8691/d80c包，证据提交后的最终head CI另在PR核对。
