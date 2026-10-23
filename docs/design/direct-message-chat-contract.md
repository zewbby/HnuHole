# P2 图片与完整聊天契约（隔离实现）

适用：集成分支 `feat/direct-message-chat-completion`，基线 main `154a761`，迁移 0023；后端子任务原分支 `feat/direct-message-chat-backend` 已整合。正式开放、治理、推送仍属于 P3；本文件不提升 B08/B09 整模块或生产验收结论。P1 路径与 DTO 保持兼容，完整机器契约见 `packages/openapi/direct-message-chat.yaml`。

## 请求与结果

所有请求复用当前 C 会话、会话代次、账号状态、本人身份和最终 Safety Gate。没有第二套聊天身份或公共图片权限。所有响应采用显式 DM DTO，禁止包含账号 ID、邮箱或会话能力。

| 路径 | 用途 |
| --- | --- |
| `PUT /api/v1/dm/chat/images/{commandId}` | 每张图片独立稳定命令、消息和受理结果 |
| `GET /api/v1/dm/commands/{commandId}` | 沿用 P1 的 ABSENT/FAILED/SENT 回执核对 |
| `GET /api/v1/dm/chat/pending` | 文字或图片待投信封，不含图片字节 |
| `GET /api/v1/dm/chat/media/{messageId}` | 仅有效收件身份读取该项待投字节 |
| `POST /api/v1/dm/ack` | 沿用逐消息 ID 的可靠落地 ACK，原子清正文及该图字节 |
| `POST /api/v1/dm/read` | 沿用已 ACK 且实际查看的明确 ID，不以游标批量清未读 |
| `GET /api/v1/dm/chat/conversations?identityId=&after=` | 含隐藏、删除墓碑的本人身份目录，UUID 分页每页 100 |
| `PUT/GET /api/v1/dm/chat/operations/{operationId}` | 稳定设置、隐藏、恢复、删除、撤回操作及结果核对 |
| `GET /api/v1/dm/chat/controls?after=0` | 本账号有效身份的最小撤回控制事件，每批 100 |

图片 PUT 字段：`identityId, peerId, conversationId, groupId, position, groupSize, mediaId, sha256, byteLength, mimeType, width, height, data, attempt`。`position` 从零开始，小于 `groupSize`（1–9）。`data` 为标准带 padding 的 canonical base64。同组固定发送身份、会话、大小；同组位置和该发送身份的 mediaId 唯一。服务端 sequence 按每图实际受理顺序递增；客户端按 groupId/position 保留选择顺序，补失败项不重建七张成功图。

每图最多 10 MiB，整组自然上限 90 MiB；发送账号全部待收字节最多 128 MiB，全服务最多 1 GiB；消息待投额度沿用 4096。超限返回持久 `FAILED/PENDING_LIMIT`，已有待投不设过期丢弃。完整解码复用固定 hash 的 Linux Pillow/libwebp 子进程验证器（2 个并发槽、8 秒、384 MiB、5 CPU 秒），检查原始 SHA256、尺寸、帧数和动画工作量；仅接受 JPEG/PNG/GIF/WebP，不接受 APNG。仅复用字节验证，未复用帖子上传能力或公开图片地址。运行装配须启用既有 `postImages` 固定验证器配置，否则图片受理失败关闭。

首次双方文字受理完成前禁止图片；文字撤回、本人删除聊天不会重置 `low_sent/high_sent`。每图失败重试沿 P1：仅已记录 FAILED 可增加 attempt 一次，原 ID、身份、组、位置、manifest 不变。超时先 GET 原 command，ABSENT 只是一时观测；同 ID 重放不会创建另一消息。新增失败码 `INVALID_IMAGE`；其余为 P1 的权限、联系、额度和冲突码。

## 本人目录与操作

目录扩展字段：`sourceTitle, version, settingsVersion, pinned, muted, hidden, deleted, deletedThrough, note, unavailableUnread`。sourceTitle 仅来自仍公开且非治理隐藏的原帖已发布内容；不可用返回空字符串，不恢复删除前标题。

`version` 为该会话目录投影的单调 revision，消息插入、ACK/read/retract、本人设置更新均推进。客户端拒绝较小版本，任何响应都不能降低本机 `deletedThrough`。`settingsVersion` 专供本人设置 CAS，不能把全会话 revision 当设置预期版本。目录保留隐藏、删除墓碑；新消息越过隐藏/删除边界时恢复入口，原未读除明确阅读、删除或撤回外不消失。`unavailableUnread` 是已 ACK 仍未读的最小元数据计数，换机不能下载这些正文，也不会擅自标已读；本机已保存内容仍由本机判断可用。

操作必传 `identityId, conversationId, operation, expectedVersion`。SETTINGS 另传完整 `pinned, muted, note`，备注最多 100 grapheme/400 UTF-8 bytes；HIDE/RESTORE 不传额外内容。三种操作比较 settingsVersion，冲突记录稳定 `REJECTED/VERSION_CONFLICT`。DELETE 必传用户所见 `throughSequence`，仅在该值以内单调删除本人记录、清其待收字节/未读，保留备注与对方独立副本，不能用“执行时最新序列”吞掉并发新消息。RETRACT 必传本人 messageId；预期设置版本不参与 DELETE/RETRACT 判定。

操作 GET/PUT 返回 `state, errorCode, conversationId, version, settingsVersion, deletedThrough, messageId`，state 为 ABSENT/APPLIED/REJECTED。同操作 ID、同规范化意图返回永久相同结果，变更意图冲突；已记录失败也不会因时间或后续状态而变成功。未知结果只能核对原 ID。越权/失效身份或非会话成员直接 HTTP409；没有操作回执，客户端应保留“明确拒绝”和“网络未知”的区别。

## 撤回、控制和竞态

撤回依据最终 Gate 的 trusted time 与平台 acceptedAt，严格小于 120 秒；恰好两分钟拒绝。本人已撤回的目标重复撤回幂等成功。正文、图片字节即时从待投列移除，最小消息、原受理回执、会话额度保留；不服务端保存重新编辑原文。重编辑原文和 24 小时可用期限由本机单独实施。

撤回在同事务分别为双方创建事件：`eventId, sequence, identityId, conversationId, messageId, messageSequence, type=RETRACTED, createdAt`。返回 `items,next`。客户端原子应用墓碑并保存 next；没有 controls ACK，最小墓碑持续保留，使旧手机重新登录或换机从 0 重放后仍能清理其本机旧正文。全局事务锁串行分配控制 sequence，避免小序号未提交、大序号先提交导致游标跳过。事件不携带正文、私人备注或其他身份关系。

ACK、删除、撤回均先按序锁 conversation，再写 message/settings/media，避免消息行与目录 revision trigger 的锁序反转。图片受理先全局容量锁再 conversation；清理仅减少容量不需要反向获取预算锁。设置版本/删除边界及消息 ACK/read/retracted 由 SQL trigger 防止回退；媒体 UPDATE 只允许置 NULL，不能重新注入已清理字节。运行角色不得修改 manifest、sender、命令 fingerprint，不能更新/删除操作回执或控制事件。

已经发出的 HTTP 字节可晚于撤回响应到达。客户端必须持久撤回墓碑和删除边界，并在迟到信封/下载/本机写盘结果应用前检查；仅服务端取消补投不足以防止本机复活。逻辑清除不等同 PostgreSQL WAL/备份介质的即时物理擦除，生产保留与备份治理在 P3/部署边界评审。

## 增量检查与使用

- PASS：真实独占 PostgreSQL16 + 受限 hnuhole_c_runtime，九图七成功两失败、只补失败项、稳定回执、字节完整性、越权、逐图 ACK、私有备注/设置 CAS、隐藏保留未读、新消息恢复、删除截断与备注保留、ACK/撤回并发、双方离线控制重放、窗口外拒绝、禁言阻断、数据库授权。
- PASS：真实 HTTPS/SQL 新增六路径、媒体受理/读取/清除、来源标题、严格请求、操作结果隐私、控制取数、最终 Gate freeze。
- PASS：完整 P1/P2 OpenAPI；Go build `./cmd/...` 与相关 authprivacy/authprivacyhttp vet；受影响 P1 并发首发/受限运行及可靠文字 HTTPS。
- PASS：迁移新建、22→23 及已有 P1 待收文字/回执/额度保留、失败 Down 前向恢复。主功能日志 /tmp/hnuhole-dm-p2.lRuZ61/tests.log；携带 P1 正文升级补验 /tmp/hnuhole-dm-p2.zrjiL1/tests.log。前者 runner 输出末尾曾因编辑期间 CRLF 失败，Go 测试两包均 PASS；runner 已修 LF 并由后者正常退出确认。
- 集成补验：真实 Dart TLS/SQL 与 RMX3366 Android14 原生加密存储／九图收发／备注隐藏删除／离线撤回／图片查看器通过；源码8892172，限定证明范围见 [机器证据](direct-message-chat-verification-20261022.json)。新建本地存储模拟恢复，不代证物理换机；搜索规模性能未执行。生产默认开关保持关闭。
- 独立额度补验：发送账号和当前会话分别计算 4096 待投上限；并集达到4096而两者均未满仍可发，任一满额拒绝。真实 SQL/race 旧代码 RED／修复 GREEN，独立审查已关闭该问题。
- 客户端删除未知任务只保留核对原 ID 所需最小意图字段，不把 ABSENT 当作取消；不再 PUT 已被用户删除的内容。核对工作轮转，普通待发优先，避免持续 ABSENT 阻塞新消息。图片键按 senderId/mediaId 隔离。

独占 runner：`services/api/authlab/run-dm-chat-isolated.sh`。环境须显式给已有 `POST_MEDIA_PYTHON` 和 `COMMENT_TEXT_GOOSE`；runner 自建 /tmp 私有 socket 数据库和合成 PNG，不读写已有服务。`DM_CHAT_TEST_PATTERN` 只选择新增/受影响检查。保留本次临时目录与日志，退出自动停库。

`TestDMChatDevicePostgres` 仅当 `DM_CHAT_DEVICE_FIXTURE` 非空启用。私密 JSON 包含 P1 能力字段、第三账号 `DM_TOKEN_C`、已文字互回的 `DM_CONVERSATION`、同一已验证 `DM_IMAGE` base64/7×5 尺寸与 `HOST_PORT`。仅此 fixture 对第八、九张 attempt1 翻转原图首字节，保留 manifest/digest/长度，让真实服务器记录 INVALID_IMAGE；attempt2 不改。不得将故障注入带入运行装配。fixture 等待 `<file>.done` 或 25 分钟截止后清理能力文件；HTTP/Android驱动自行负责自有转发映射和done文件。
