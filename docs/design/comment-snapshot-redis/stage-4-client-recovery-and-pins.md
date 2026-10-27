# 第 4 阶段：客户端恢复和临时置顶衔接

日期：2026-10-25。任务 `COMMENT-SNAPSHOT-REDIS-01`，调度指定 GPT-6.1 Sol / high。本阶段完成客户端实现、组件/控制器回归、真实 Dart/TLS/Redis/SQL 联调及指定 Android 界面验收。第 5 阶段容量、P95、双 API 命令进程和长时间阅读尚未开展；本需求仍为本地未提交差异，无 PR、合并或发布。

## 最终行为

- 新增 `CommentSnapshotReader`，仅快照分页读取持有一次 250ms 短重试预算。TIMEOUT、TRANSPORT 或明确 COMMENT_SNAPSHOT_UNAVAILABLE 最多再请求一次；游标失效、429、单份过大、容量/完整性、授权失败不自动重试。request/runtime/HTTP 层不会再叠加分页自动重试。
- 首屏生成非零 16 字节 canonical nonce，通过 `X-Comment-Snapshot-Request` 送到服务端。同次短重试及首屏手动重试复用 nonce；显式刷新或失效后换名单才产生新 nonce。游标续页只重用原 cursor，不带 nonce，不套用新排序或新偏移。
- `CommentRuntime` 不再把快照专属三种 503 升格为全账号的 sessionUnavailable，避免清空整个阅读上下文或草稿；既有真正会话/授权失败处理仍保留。所有响应保留原 account/authority fence，关闭或切账号会取消后续自动尝试。
- 主评论 CURSOR_INVALID 保留旧列表和草稿并停止追加，用户刷新成功后才整体替换；临时失败保留原续页游标，手动重试原位置。单层回复失效只替换该层，保留主评论和其他楼层。失败入口放在实际失败处，续页错误不在顶部插入导致阅读位置变化；对保留的可见行使用锚点补偿。
- 本人主评论按提交顺序倒序临时置顶；本人回复在自己的根评论内部倒序置顶，根评论原位置不动，自动展开并定位。沿用持久提交即显示、无“发送中”标签及原任务失败/未知处理。服务器确认后按 ID 去重，翻页不会重复显示；主动刷新清除已确认的临时置顶并恢复服务器排序，仍在发送/未知的内容及原始材料保留。重进页面不重放历史发表事件。
- 主列表刷新后递增版本，回复读取和迟到的发表定位都校验版本，不能把旧名单或旧回调插回新名单。
- 空扫描且有 nextCursor 时展示继续加载；只有 cursor=null 且确实取得页面后显示空/末页。回复即使实时可见计数不超过 5，也会按 nextCursor 保留继续入口，不因计数误判末页。
- 评论刷新按钮、分层失效/重试、429 等待、规模超限及繁忙提示均使用已有页面组件。保留草稿原文、附件、身份、回复对象、账号隔离和共享限流的原键手动重试协议。

核心源码：`apps/mobile/lib/src/comments/comment_snapshot.dart`、`comment_http.dart`、`comment_runtime.dart`、`comment_views.dart`。测试为 `comment_snapshot_test.dart`、`comment_views_test.dart`、`comment_runtime_test.dart`、`comment_http_test.dart`；旧回归适配可选 nonce 参数，不放宽原有行为断言。

## 真实前后端联调

新增 `apps/mobile/integration/comment_snapshot_live_probe.dart`，编译为独立 Dart executable，使用产品 `CommentSnapshotReader` 和严格 `CommentHttp`，验证私有 P-256 CA、实际 TLS、生产 Go handler、独占一次性 PostgreSQL 和本测试创建且核对 process_id 的 Redis。

Go `TestCommentSnapshotHTTPSPostgres` 在显式 `COMMENT_SNAPSHOT_LIVE_PROBE` 下将首屏成功响应真正断开，Dart 以同 nonce 重试；服务端核对收到相同 nonce 且没有第二份快照额度消耗。live 阶段共 5 个请求：首屏两次、续页一次、配额 429 一次、篡改游标 400 一次。然后停止本测试 Redis 子进程，down 阶段明确 503，原 cursor 共请求两次，没有 nonce、PG 回退或隐式第三次请求。

最终 `stage4-final-dart-live.log` 为 PASS：live requests=5、down requests=2；Go race fixture 通过。普通 fixture 没有设置 probe 时仍只证明 Go/TLS，不能称 Dart 通过。CI 已增加 Flutter/Dart probe 编译与实际执行接点，客户端改动会触发 workflow；远端 CI 尚未运行。

## 客户端最终验证

| 项目 | 最终结果 | 边界 |
| --- | --- | --- |
| `flutter analyze --no-pub` | PASS，0 问题 | 整客户端 |
| `flutter test --no-pub --reporter expanded` | 964 PASS / 0 FAIL / 3 SKIP | 3 个既有 DM P2/设备/P3 实时 fixture 未配置；不计为通过 |
| `flutter build bundle --no-pub --target lib/main.dart --target-platform android-arm64` | PASS | 同一最终源码；使用现成 Linux SDK 与经包钩子核对哈希的官方 SQLite ARM64 缓存 |
| 真机验收 APK debug/ARM64 | 构建 PASS | `org.hnuhole.hnuhole_mobile.commentsnapshot` / `2026102501`，隔离包 |
| 完整后端 host/build/vet 与完整 API 契约 | PASS | Stage4 只扩充 Go 联调测试，后端产品逻辑沿用 Stage3；无 DSN host 不能冒充真实 SQL |

全量客户端最终快照与工作区 13 个客户端变更文件逐文件 SHA-256 相同；阶段 3 的产品差异完整保留，只有 HTTP 联调 fixture 和 snapshot CI 在本阶段追加。最终清单与聚合 hash 见 [stage-4-evidence.json](stage-4-evidence.json)。

## Android 真机结果及重试历史

真我 RMX3366 / API34，先核对并获取 `E:/Hnuhole-env/device-leases/7e0660f1.json` 独占 lease，仅安装 `.commentsnapshot` 包。APK SHA-256 `237abb46c43781fbef777eead0e8b09b06614a5415393d5ca53144f4d0bef069`；包名/版本由 aapt 复核。

第一次安装 `Failure [-99]`，观察到锁定界面，按原调度保留待验记录。用户随后明确要求“重试”；第二次观察到系统安装页，核对本测试版本并点正常“继续安装”，安装成功，应用原生启动成功。

`integration_test/comment_snapshot_device_test.dart` 在手机运行实际生产 CommentPostPane，共 **9 项场景 PASS / 0 FAIL / 0 SKIP**：主失效与草稿、单层回复失效、空主分页、楼层内新回复、刷新恢复原排序/去重、续页一次重试/手动重试、低计数空回复续页、失败阅读锚点、刷新后迟到发表回调。手机日志显示 `+10 All tests passed` 还包括 integration_test 自带 tearDownAll；业务场景只计 9 项。结果从本测试 app 的真实 `code_cache/comment-snapshot-device-result.json` 读取，并逐项验证 success，不依赖猜测路径或单个 marker。

这是手机运行的生产 widget 加内存页面/authority fixture，**不是手机连接真实后端、原生加密存储或全模块验收**；真实网络证据由上节独立 Dart executable 证明。没有把两者拼接成同一条端到端真机链路。原日常包仍为 `2026102427`，数据不变；测试包已 force-stop、独占 lease 已释放、自己的临时 UI XML 已清除，未改用户锁屏设置。原失败记录 `device-attempt.json` 保留，最终 `device-verification-r2.json` 覆盖此前“待用户真机验收”状态，范围仅此九项。

## 失败和修复记录

- r1/r2 静态分析为格式告警，按限定 lint 修正；无错误抑制。
- 首次组件回归中，新草稿用例误用只在 expanded 模式出现的收起按钮；另外旧“单个全局回复错误”断言改为多个楼层内提示，保留不批量预取断言。一次脚本误插测试步骤随后撤回，未更改原产品语义。
- 阅读锚点回归捕捉续页失败顶部提示导致 48px 位移；改为失败页脚入口，最终同一用例位置误差不超过 2px。
- 真实 Dart 首轮逻辑已 PASS 但未按既有 Go probe 协议落盘 result.json；补上输出文件后真实链路 PASS，没有放松业务断言。
- Android r1 为 NTFS Flutter Gradle chmod 失败，改用同版本本机 Linux SDK；r2 为官方 SQLite 下载超时，使用已有官方 ARM64 缓存，包自带 SHA-256 验证仍启用；r3 构建成功。首次 bundle 缺 Android SDK，指定实际 SDK 和 arm64 后成功。工具缓存不提交到仓库。
- 安装初次失败与错误 cache 路径的有界结果观察均保留；重试真实安装成功后，正确 code_cache 路径返回 9 项 success，且日志相符。

日志和 APK 在外层任务目录 `comment-snapshot-redis-20261024/stage-4-evidence/`；机器证据与静态校验分别为 [stage-4-evidence.json](stage-4-evidence.json)、[stage-4-validation.json](stage-4-validation.json)。提交源码不含 APK、日志、SDK、账户凭据或缓存。

下一阶段等待调度：第 5 阶段继续双独立 API 命令进程、故障/容量与 P95、实际 30 分钟阅读、端到端设备链路及发布边界；不因本阶段 UI/传输限定通过提高原全模块或生产结论。
