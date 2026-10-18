# 第三项：准备工具与实测交接

2026-10-16补验已收口：[报告](../../docs/design/community-android-stage3-closure-20261016.md)/[机器记录](../../docs/design/community-android-stage3-closure-20261016.json)。第三项批准的单Android范围PASS；明确关联拒绝由当前Google provider证据核验，主动取消由用户操作，活跃旧会话由真实C/SQL补证。`check-association.py`使用真实HnuHole工具User-Agent并保持全部TLS/重定向/内容检查，不伪装浏览器或降低网站安全配置。手机窗口已结束，vivo设置已恢复；以下20261015部分完成及更早准备均保留历史，不能盲重放其ADB或一次性wrapper。

> 2026-10-15 后续实测已进行，状态 **PARTIAL**。用户批准的独立RP和额外正向包已落地，真实系统正向创建/可发现恢复及原键跨进程核对PASS；坏签名/未关联的明确拒绝与严格HTTPS403仍阻塞。最终七阶段及mobile334通过。当前入口为[实测报告](../../docs/design/community-android-stage3-device-validation-20261015.md)、[机器记录](../../docs/design/community-android-stage3-device-validation-20261015.json)、[实际执行源码归档](execution-20261015/README.md)和[当前公开关联](../../docs/design/community-android-stage3-applied-20261015/proposal.json)。设备窗口已结束，不再调用ADB；原默认守卫不放宽。**下方是此前无手机准备阶段的原范围，关于未审批/未部署/NOT_RUN的叙述仅适用当时。**

本目录只有本地构建、验证、草案生成与只读公开关联检查入口。没有 ADB、安装、域名登记、部署或安全配置应用入口。产品 Passkey 流程已在固定认证候选中实现，不重做页面。完整待确认范围见 `docs/design/community-android-stage3-rp-proposal-20261015.md`。

本机独立工作材料：`E:/HnuHole-community-f4-20261012/stage3-preparation-20261015` 与 `/home/hnuhole/community-android-stage3-20261015`，owner 都为 `HNUHOLE_COMMUNITY_ANDROID_STAGE3_V1`。现有社区专用 SDK 为 `/home/hnuhole/community-android-stage1-20261014-tools`；原共享 SDK 和认证环境不调用。当前材料按用户要求保留到后续窗口；Git只收源码、测试、小型脱敏证据及公开配置草案，APK/key/cache/原始日志留在外部。

## 构建基线

仅在没有并行 Flutter/Gradle 操作时，确认容量、owner、工具路径与全新 `PASSKEY_ROOT/source` 后运行。不要对已有未决构建/设备状态直接重跑或清除。

```bash
source /mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/env.sh
export PASSKEY_ROOT=/home/hnuhole/community-android-stage3-20261015
export PASSKEY_REPO=/mnt/e/HnuHole-community-f4-20261012/repo
export PASSKEY_SQLITE_ASSET=/mnt/e/HnuHole-community-f4-20261012/stage1-preparation-20261014/assets/libsqlite3.arm64.android.so
bash "$PASSKEY_REPO/tools/community-android-stage3/build-baseline.sh"
```

root须先由操作者确认归属并建立owner。本入口拒绝已有source，只以 applicationId overlay 构建独立 `lib/main.dart` Debug ARM64 包，使用本任务 HOME 新调试签名。control包 `org.hnuhole.hnuhole_mobile.communityf5.passkey`，unassociated包加 `.unassociated`；没有设置新 RP、CA 或 C/V地址。它们保留历史源码Debug资源，**尚非可做独立 RP 正向验收的候选**。域名/安全配置获准后必须用新的独立lab配置重建。

mobile `pub get --offline --enforce-lockfile` 保留原锁。Passkey库没有单独提交lock，其9项Dart测试通过mobile已锁定依赖图运行：

```bash
cd "$PASSKEY_ROOT/source/apps/mobile"
flutter test --no-pub --machine ../../packages/auth_passkey/test/native_passkey_client_test.dart
```

不为库重新解析/升级依赖，不生成新的仓库lock掩盖缺失。JVM入口编译产品Debug诊断policy和现有test，运行24项策略断言；它不访问 Android API或凭据provider。

## 核对和差异生成

`verify-baseline.py` 的参数为 `--work --repo --output --build-tools --jdk --source-commit`。本机完整命令保存在外部 `verify-and-propose.sh`，固定source snapshot为 `e0c128033682923d519ea99546d72503b085a99e`。它从显式已提交快照读取源输入，对照199项镜像，核新签名、ARM64与SQLite；生成同包不同签名的负向包，逐个核对560个非签名条目。新调试 key 与负向 key 均留在当前 task3 私有材料中，公开证书摘要进入proof。Git只读归档命令的 `safe.directory`/换行选项均只作用于单次命令，不写全局配置。

检测到另一手机任务在本分支并行提交e0c1280（增加Windows key隔离阻断），原0c8e247到该提交改变4个runner/test运行输入，其余452项不变，产品均未改变。主机工具测试采用e0c1280的独立导出目录 `host-source`，只加入本轮新工具/测试；不复制或计入其后续未提交USB代码。导出须禁用命令级autocrlf转换，保持历史 byte-exact lock fixture 原始字节，不修改校验常量或仓库锁。

```powershell
& E:/acanda/python.exe -B tools/community-android-stage3/proposal.py `
  --work E:/HnuHole-community-f4-20261012/stage3-preparation-20261015 `
  --repo E:/HnuHole-community-f4-20261012/repo `
  --proof E:/HnuHole-community-f4-20261012/stage3-preparation-20261015/artifacts/baseline-proof.json `
  --output-name review-bundle-final
```

这个命令只允许全新输出目录，拒绝旧认证RP、错误包名、未核对的同载荷签名对照和覆写。草案不代表注册/托管控制权或审批。正式本机目录为 `review-bundle-final`；早先 `review-bundle` 因drvfs chmod中断，仅有不完整公开文件，删除被自动审批拒绝，已保留，不作为正式方案或证据。

## 获准部署后才可进行的只读检查

```powershell
& E:/acanda/python.exe -B tools/community-android-stage3/check-association.py `
  --bundle E:/HnuHole-community-f4-20261012/stage3-preparation-20261015/review-bundle-final `
  --confirmed-approved-domain-control-and-deployment
```

当前没有该项审批，**本轮未执行上述网络检查**。缺确认会在读manifest或联网前退出。检查只GET精确 `https://<rp>/.well-known/assetlinks.json`，校验公有TLS和主机名、拒绝redirect、要求200/JSON、限制64KiB、核精确审阅文件。不会改代理/证书/系统配置，不调用Google验证器或设备；成功也只代表HTTP关联文档，不能代证provider或系统ceremony。

## 后续配置与设备范围

先确认独立域名可用/控制权及公开部署，审阅唯一package/cert、两关系与新C配置，再建立新的task3一次性C/V环境、正式迁移/最小权限和固定来源。新候选要重建/核摘要、实际RP、APK签名、插件和运行配置；这部分依赖安全配置授权，目前BLOCKED，不应写成只差手机。旧B3/B4工具的硬编码路径、账号和设备不直接执行，旧认证22/0/2不计为本轮结果。

目前没有可以把新联合源码、独立RP和上述全套单机Passkey场景一键跑完的统一runner；不用旧脚本名冒充。产品实际UI/控制器的正向绑定、可发现恢复、完整新凭据确认、原键结果核对已存在，逐项人工/受控操作及断言见方案。后续如果为获准的新lab适配故障代理与统一采证，必须保持只转发/丢弃真实响应、不得伪造证明、SQL结果或关闭Gate，并补主机测试后再使用。

手机须另确认窗口、认证释放、包/数据影响及可验证的USB身份方案；Windows已提交的前置阻断不能靠旧四项flags绕过。明确获准并验证的新USB方案应以新的固定提交交付后再采用，本轮不读profile key、不建OS账户、不触碰既存5037或任何ADB/手机。

错误签名同包与控制包不能直接换签名覆盖；不得未经授权卸载/清数据。系统创建的测试Passkey也需要人工配合和明确授权；取消/超时后可能产生孤立凭据，不盲重试。真实provider创建/恢复、用户UV、取消/拒绝、原生60秒与C五分钟自然到期、丢提交响应后原锚点恢复，以及任务1/2设备全流程都仍NOT_RUN；任务4双实体、iOS、生产另行待验。
