# Android候选与隔离预发布

2026-10-18：本地隔离演练、独立CI后台演练、测试签名Android候选实际构建/验签/摘要核对通过；未合并、未正式发布。结果必须对应精确源码SHA；
GitHub Actions的Android制品和后台演练证据分开保存，手机验收NOT_RUN。

后续核对main已到`1b78f422dccff1f5598e3a52a9dc2ae7a928e4d1`（PR #18），正式迁移为C0015/V0004。
本任务已同步，正在新root重跑迁移/权限/恢复/回滚并准备手机包；下方schema14记录保留原SHA。
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

手机安装/原生存储/Picker/Gal/物理UX和本候选Passkey均NOT_RUN；跨设备Passkey和iOS延期。
schema13快照仅合成目录/迁移历史，不含真实用户历史数据。真实云、正式签名、生产主体独立、
外部独立备份运营与正式发布不属于已获批准的本地演练。媒体仍沿用现有SQL存储。

## 2026-10-18实际发布记录（候选交付，未正式发布）

任务为 [PR #16](https://github.com/zewbby/HnuHole/pull/16)，创建基线8fa9cbc；已同步实际合入的
PR #13/main 986477b。当前正式迁移C0014/V0004；0015/0016没有进入本轮源码，不预建占位表。

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

当前与回滚版本的业务源码及迁移相同；这证明本轮二进制切换/故障拒绝和schema14兼容，
不证明未来0015/0016或未知历史数据库兼容。完整业务/动画多图/跨账号访问、原生Picker/Gal/vault/物理设备、
固定生产端点/正式签名/安装升级及生产灾备仍未验。APK当前默认.invalid不连接本地服务，后台smoke不冒充APK链路通过。

失败历史保留：首轮工作流runner上下文解析失败；6426918的API35缺失与libpq空格编码失败；
dee7fdc后台PASS但Android缺CMake3.22.1失败；4c9477a的release dev插件注册失败。
后者采用Flutter官方[issue169336](https://github.com/flutter/flutter/issues/169336)的config-only路径，
保留先行enforce-lockfile和配置前后锁/源码一致性校验，不手改生成代码。均修复后重跑，失败不计PASS。
本地早期源码提取、libpq、Mailpit版本参数和审计匹配守卫失败保留在同任务私有目录，后续精确SHA回执取代其验收结论。

## 下一设备窗口方案

用户指定设备为vivo S18 / OriginOS 5，当前不能配合验证，已授权先准备测试包；
实际Android版本/API/ABI、安装和APK服务链路仍NOT_RUN。先保留本轮非手机证据并离线构建专属debug/pinned-CA候选：
仅loopback HTTPS、专属测试签名、明确的USB服务/key和单机端口映射；不装系统CA、不开放数据库/内部mTLS。
安装前核对目标包现状，避免覆盖其他任务App或数据。验证安装启动、合成注册/登录、文字/图片最小链路和重开，
逐项保存当前APK/源码/证书摘要；结束后只撤本任务映射并停止本任务服务。跨设备Passkey和iOS继续延期。
此方案尚未执行手机操作，等待本session设备窗口；手机专属工具只下载到本任务独立目录，不借用其他session工具。

### 离线准备手机测试包

`device_candidate.py`只构建/验签，不运行ADB、服务或设备探测。与release候选分开归档，
仍使用真实`lib/main.dart`、原applicationId和认证逻辑；`HNUHOLE_PRERELEASE_DEVICE=1`显式选择测试label和签名，
替换debug Manifest以去掉历史GoogleFido诊断Activity及DAL元数据声明。旧诊断类/资源可能仍被打包，
不宣称已移除其全部代码。不开启RP override，不装系统CA，不放宽TLS或Gate。

所有HOME/Flutter/JDK/Android SDK/Pub/Gradle缓存必须落在指定的私有`--tool-root`；
版本沿用Flutter3.47.5、JDK17、Android35/36、build-tools36.0.0、NDK28.2.13676358、CMake3.22.1。
先在同一独立环境执行`flutter pub get --enforce-lockfile`。配置文件只接受以下三个公开字段：

```json
{"communityOrigin":"https://127.0.0.1:49291","verifierOrigin":"https://127.0.0.1:59947","caPem":"-----BEGIN CERTIFICATE-----\n本任务公有CA的PEM内容\n-----END CERTIFICATE-----\n"}
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

保留lab-07为恢复后的非空数据库，`target=restore`；不要重跑`init`或包含初始化的`run-local.sh`。
C/V固定端口49291/59947，公有CA PEM SHA256为`1be676311b5b88adac3ea10bc9987498231086a7c8f390b82eb9a7af5a43bef0`。
现有C/V叶证书到2026-10-25 17:18:53（上海）到期，CA到11-17；窗口前重新检查实际证书有效期。
叶证书到期必须使用本任务CA续签并验证，不得跳过证书校验；CA更换则重建并重新核包摘要。
当前进程已停止。窗口内先start/recover/health并严格核验Windows到WSL HTTPS，再建立本任务两条USB映射。
不映射数据库、邮件或内部mTLS；设备端口冲突同样阻断，结束只撤本任务映射并停本任务进程。
