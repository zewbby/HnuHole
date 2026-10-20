# 原失败评论任务重试同步修复

工作项 `FEED-PERF-WORKER-SUPPORT-01`／`FA-D08`，分支 `codex/fix/comment-failure-reconcile`，[Draft PR #36](https://github.com/zewbby/HnuHole/pull/36)。从最新 main `30401b8` 独立建立，源码 `57dfe5f888986c41c54e073f5e66ba80b4e26371`；旧工作区、2010 包和失败历史保留。未合并、未正式发布，新 PR 没有合并授权。

真实 worker 在原 15 分钟期限后失败，失败页显示新的 FAILED，但前台 40 次自动轮询早已耗尽，本地 journal 仍为 ACCEPTED。2010 真机没有重启／resume／Pending 核对，直接点击原重试立即报“请核对任务结果后再操作”；SQL 确认 CREATE 1、RETRY 0。失败任务正文、原图和身份均保留。

本修复只调整失败页：先复用核心原 command reconcile 持久化核对，再读取 owner task；现有 entry 必须是已确认 FAILED、同 task／版本／绑定才允许操作。未知 RETRY／ABANDON 和 busy 提前返回不能因 raw FAILED 解锁。补图片读取后及操作后加载的账号围栏，不重发 CREATE、不改身份／目标；保留编辑内容和无 entry 的第二安装恢复。

## 实际验证

- 分析 0；六个受影响评论文件 76 项 PASS，含新增 10 项 Runtime／FailureView 回归；301 tasks 原生 Android 构建 PASS。命令、适配器边界和日志摘要见[机器记录](../design/comment-failure-reconcile-verification-20261020.json)。未在本地重跑旧 25／615 全量或旧红绿；最终 PR 必要 CI 仍按精确 head 核对。
- Max 独立只读复审无剩余阻断，COMMENT review `5586680776`。账号替身现走真实登录 B 并确认 ready；审查者没有执行测试或操作设备／共享环境，不冒充 GitHub 独立成员批准。
- Android 独立验包、保数据同签覆盖安装 debug 2011 后，在同一个原失败任务正常点击一次重试；原正文／图／B 身份保持。后端唯一任务 `7202fe80…` 保留 v1 的 `PUBLICATION_FAILED`（902.335425 秒），v2 在 0.616413 秒内 PUBLISHED；CREATE／RETRY 各一次，公开评论一条，原图 1840 bytes／完整 manifest 一致。
- **证明边界：覆盖安装会重启 App。** 设备证明存量任务恢复和真实发布；同进程轮询耗尽的陈旧 core 修复由确定性宿主用例证明。没有再造失败任务、再等 15 分钟或用重启成功冒充旧进程缺陷复验。
- 实际渲染与原文件 SHA 见机器记录的 `renders`；仅复制 Android 目视批准的自有合成数据原 PNG。原 2010 FAIL、fixture 失败过程和旧证据保持原版本。

## 候选与适用性

`comment-failure-reconcile-57dfe5f-2026102011.apk`，debug arm64，98,806,364 bytes；APK SHA256 `9815825f29fd57895f9d00ef7acfa6996dfd9cd09fc3c147ddcaf7527cfbf0f0`，kernel SHA256 `ed38ef8251458f721df0e07f538fc1b6dc4ead7dac96a8fa94d39ba1b039609d`。沿用 test cert，CA／public defines／原 C51245、V49747 相同，已实际核实编译 kernel 三项 defines。110 个运行输入仅 `comment_failure_view.dart` 不同，后端仍 c923fa5a／C21/V4；环境负责人只读适用性与最终单 task SQL 独立记录，无产品部署。

旧 FA15／迟到写／账号切换／图片／认证等证据只按未变输入及原范围复用，不替代这次失败页影响回归。最终文档提交若仅文档／原 PNG 变化，复用此源码、候选及设备证据，核对 diff 后不再换包或重测相同场景。最终 CI 和交付包的精确提交／摘要在 PR 回执确认。

## 性能补验仍阻塞

可信公网 C/V HTTPS 入口尚不可达；免费隧道分配了 URL，但没有注册 edge，外部 TLS 超时，不能烘焙这些 URL。profile／release APK **未构建**，真机性能 **NOT_RUN／BLOCKED**。标准 TLS、原 Gate 和开发 CA／RP debug guard 未降低，也没有用 debug 或 SurfaceView 帧数据冒充 Flutter UI／raster。

本地 profile/release 同测试证书签名前置检查已通过，原环境构建参数和采集准备留在独立 `HnuHole-feed-performance-support` 的 ignored build 材料；真正入口 ready 后再按 Android 预先确定的设备口径采集。profile 的 `Flutter.Frame` UI/raster 数据方案依据 [Flutter 性能说明](https://docs.flutter.dev/perf/ui-performance)及本机 SDK SchedulerBinding；此处不宣称任何性能数值或项目级 SLA。2011 原性能规划从未构建，现明确用于 debug 修复，后续模式版本重新排号。

相关入口：[HANDOFF](../design/HANDOFF.md) · [进度](../design/progress.md) · [模块交接](../design/module-acceptance-handoff.md) · [台账](../design/module-acceptance-ledger.json)。最终 CI 未通过、存在新阻断或未获新合并授权时保持 Draft；前端未操作设备、更新共享环境或正式发布。
