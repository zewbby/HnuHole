# DM-P1：可靠文字收发

- 分支：`feat/direct-message-text-reliability`；2026-10-22，本地实现及限定宿主/SQL检查通过，Android实发实收 BLOCKED。未提交PR、未合并、未发布。
- 基线：最新 `origin/main` `76af92b`；依赖未合并 PR #44 的界面提交 `60629f3`，已快进集成。后续 PR 须明确先合入 #44，不将该界面算作 P1 新实现。
- 范围：受保护文字接口、唯一身份对/同帖绑定/首发额度、持久 outbox/inbox、入库后 ACK、基础未读/草稿、账号和会话代次围栏、隔离开发装配。生产开放留到 P3。
- 验收：新增真实 PostgreSQL/API 并发和授权、客户端实盘故障恢复、Android 新增接线短流程。未改动的 #44 字体、配色、菜单、图标和布局验收直接引用原证据。
- 执行语义：稳定 UUID 意图；超时查询/重放同一幂等意图；明确失败才增加尝试版本，内容/身份不可更换。服务端同步事务持久受理即 SENT，收件失败不会反转发送结果。
- 首发：服务端按已受理双方文字推进；同方第二条须等对方有效文字。事务回滚不绑定/消耗额度。
- 文字限额：P1 暂定 4000 Unicode grapheme、16384 UTF-8 bytes，空白拒绝；待投上限达到时明确拒绝新受理，旧待投不删除。
- 换机：服务端只保留待投正文，ACK 清正文。已 ACK 未读的元数据保留，不伪造本地历史、不自动清读。完整换机交互在 P2 完成。
- 存储：复用既有原生 noBackup 路径/安全密钥通道，独立私信作用域及认证加密载荷；不得覆盖帖子数据库。
- 当前：见下方交付记录；不引用预览结果代证真实收发，不提升B08/B09完整模块验收结论。

## 实现与业务边界

原#44只有展示投影与内存预览。本次接入帖子/评论头像及昵称联系入口、目录、可靠文字outbox/inbox、基础未读、草稿、原消息重试及账号/身份/会话代次围栏。图片、完整历史搜索、撤回、隐藏/删除、备注、治理与生产开放留后续阶段；P1界面隐藏未支持操作。

6条API路径定义在 `packages/openapi/direct-message-text.yaml`：联系目标、命令GET/PUT、目录、待投、ACK、阅读。复用C最终业务事务、安全Gate、严格HTTPS和元数据续期，不向界面暴露私有账号标识。0022迁移新增唯一无方向身份对、永久回执、待投正文、未读元数据和同帖绑定受理依据；保留原评论绑定约束，首发文字/绑定/额度/序号同事务提交。

请求前先持久化unknown，超时查询原回执并重放同一意图；明确FAILED才能递增attempt，原身份/正文/UUID不变。SENT只表示事务受理。接收整批落盘后才ACK；ACK清待投正文而不清未读。当前前台视口中的已ACK入件才按明确ID进入阅读队列，避免误清后来消息。

本地独立账号/环境SQLite，FULL事务与AES-GCM载荷，状态/排序字段亦绑定认证；密钥漂移拒绝打开且保留文件。确认历史按服务端会话序号排列，未确认内容按本地入队顺序置后，每页40条；已显示的未确认消息单独刷新回执。离线首发和刚收到的消息立即具有本地会话入口，不依赖目录网络请求成功；草稿恢复、身份核对重试和迟到响应围栏已接入。

P1开发契约暂定4000 grapheme/16384 UTF-8字节；发送账号跨面具和单会话待投上限均4096，满额拒绝新受理，不删除旧消息。双方同时首发视为双方有效发言。以上为工程执行语义，不声称全部产品限额已最终批准。

## 验证

基线及最终文件SHA-256见[机器记录](../design/direct-message-text-verification-20261022.json)。原始本地输出位于 `E:/Hnuhole-env/tmp-dm/`，日志、私密fixture和APK不提交仓库。

| 检查 | 实际结果 |
| --- | --- |
| `flutter test --no-pub test/dm_reliability_test.dart test/dm_route_test.dart test/dm_visible_read_test.dart` | 13 PASS：实盘重开/加密、丢响应核对、原消息重试、窗口并发、离线会话、乱序、可见阅读、实际页面草稿恢复/失权清屏 |
| `flutter test --no-pub test/comment_views_test.dart test/feed_ui_test.dart` | 42 PASS：新增联系入口影响范围 |
| `direct_message_screen_test.dart direct_message_navigation_test.dart login_home_navigation_test.dart` | 本轮早期41 PASS；后续未变的既有路径复用，新增路由另测 |
| `flutter analyze --no-pub` | PASS，0问题 |
| 真实PG16/SQL+race+HTTPS | 4顶层/2迁移子项PASS、0 skip：`TestDMFirstContactConcurrencyAndRuntimePostgres`、`TestDMGooseFreshAndUpgradePostgres`、`TestDMReliableTextPostgres`、`TestCommentTextTransactionsPostgres` |
| Goose3.22.1 | 新库与0021→0022升级、保留既有账号/偏好/频道、拒绝破坏性Down；受限角色写权限检查通过 |
| Go build/vet | `./cmd/authdev`及authprivacy/authprivacyhttp/authprivacyruntime PASS |
| API | `python tools/check-direct-message-contract.py`完整OpenAPI PASS，6路径；不是仅YAML检查 |
| 真实Dart客户端联调 | `DM_HOST_FIXTURE=<私密fixture路径> flutter test --no-pub test/dm_http_fixture_test.dart` 1 PASS；实际HttpPostApi对隔离TLS/SQL完成丢响应后查SENT、拉取、ACK与未读分离、阅读归零；不使用网络替身 |
| Android构建 | 独立`.dmtext`主入口、`DM_TEXT_INTEGRATION=true`、versionCode2026102202 PASS |
| Android真实原生存储/文字链路 | **BLOCKED**：RMX3366 Android14锁屏；integration_test已准备，未获得设备测试执行结果 |
| 独立review、远端CI | NOT_RUN；本地自查不代证独立批准 |

只使用本任务私有socket数据库及合成账号。`TestDMDevicePostgres`的Go PASS仅表示设备fixture服务成功启动并退出，**不代表Android验收**。未改动的字体/图标/布局/IME复用[原证据](../design/telegram-direct-messages-verification-20261021.json)，不重复全量测试。CI已增加本次SQL、契约、Flutter和独立Android构建检查。

## 设备阻塞和下一入口

第一次`flutter test`自动构建回到pubspec版本号1，降级失败后Flutter自动卸载了旧`.dmpreview` 2026102156；流程已停止。原包是内存界面演示，日常`org.hnuhole.hnuhole_mobile`未被覆盖。已找到旧制品并尝试恢复安装，因安全锁屏未完成；已中止等待、停止fixture并释放lease，解锁后须恢复。P1现用独立`.dmtext`；以后先核对包名/版本，再显式安装，禁止依靠自动卸载处理版本冲突。

解锁后只补：恢复旧预览；重开独占`TestDMDevicePostgres`合成TLS/SQL服务；私密配置写本地临时文件，`adb reverse`映射58443到该次端口；`HNUHOLE_DM_TEXT=1`构建`integration_test/dm_text_device_test.dart`并明确版本号，核验`.dmtext`后`adb install -r`。运行测试须使用同一制品/版本。只验原生落盘、受理后丢响应不重复、离线补收、ACK/阅读分离、回复及数据库关闭重开后的草稿；不把它表述为整机断电或完整生产登录验收。

设备补验后更新证据，核对最新main和#44依赖，完成独立review后提交PR；无合并或生产发布授权。P1测试服务/手机操作停止时释放本任务lease；测试能力不写源码或日志。

开发启用：服务端显式`directMessages: true`且要求`allowDevelopmentNetwork`；前端debug使用`DM_TEXT_INTEGRATION=true`，沿用现有可信C/V配置，生产默认关闭。0022只允许repair-forward；禁用功能不删除消息/回执。ACK后的历史正文不在服务端恢复，完整换机交互留P2；生产开放留P3。
