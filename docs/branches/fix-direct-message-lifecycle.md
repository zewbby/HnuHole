# DM-P3-LIFECYCLE 私信生命周期清理

更新：2026-10-22。分支 `fix/direct-message-lifecycle`，基线 `d864d03062ddbbd4af72e1b83d63dac73dbcf15c`。这是 P3 的 Flutter 子任务，供 `feat/direct-message-governance` 集成；未合并 main、未发布。父任务统一更新 README、HANDOFF、progress 和 B08/B09 台账，不把此子任务宿主检查视为整体验收。

## 范围与接口

- `DmStore.reconcileIdentities` 只接收认证后完整身份目录，在一个 SQLite FULL 事务内移除不再属于本人的身份的会话、正文、草稿、私人备注、隐藏记录、控制记录、操作队列和无其他引用的私有图片；只保留加密的最小删除身份防复活标记。新文本草稿显式记录本人 identityId，覆盖首次联系尚无会话的情况。
- `DmController.bind` 在暴露数据库和启动重试前完成清理；本地写入也核验持久身份目录。原 unknown 任务始终保留原身份语义，不转为其他身份发送。身份变更令旧同步、图片下载、请求和读取返回失效。
- `DmController.purgeClosedAccount(String accountId)` 与 `DmRuntime.purgeClosedAccount` 只由认证流程持久确认 CLOSED 后调用。立即阻止该账号再次 bind，等待该账号 pending open/bind 和 retired store 排空，再调用注入的 `purgeStore`。失败仍保持封锁且可重试；普通 detach/logout/session replacement 仅关闭数据库，保留历史和密钥。
- 正式装配注入 `purgeStore: (account) => DmStore.purgeNativeClosedAccount(environment: environment, accountId: account)`，通过现有 `DurableBusinessVault` 仅删除该 DM scope 的 noBackup 数据库与密钥，不需要成功解密原数据库。`main.dart` 和 `AuthFlows.onAccountClosed` 由父任务连接。没有 native purge 注入时，仅实盘测试接缝保留 CLOSED 墓碑并清空数据库。
- `accountId` getter 和 `onIncoming: Future<void> Function(List<Map<String,dynamic>>, String account)?` 提供通知装配接缝。仅新入站消息可靠落地且目录刷新后调用，重复投递、抑制记录及失效窗口不通知。回调若自行 await，展示前仍须核验其入口捕获的 `controller.scope`、accountId 和 available。
- 401/会话接替及 unavailable/Gate 请求失败立即隐藏当前会话数据并停止轮询，覆盖后台同步及 contact 前台请求。禁言等服务端明确业务拒绝继续沿用原任务拒绝结果，不转身份或绕过授权。

## 兼容边界

旧 P1 单独文本草稿只保存 HMAC pair，既没有 identityId 也没有任何会话/消息引用时无法反推本人归属。可从同 pair 记录证明归属的旧草稿迁移 owner；完全孤立、无法证明归属的旧草稿在权威目录清理时删除，不猜测或迁移给另一身份。新写入均带 owner。图片回收按剩余消息/草稿引用进行，其他本人身份仍引用同一入站图片时保留其字节。

## 验证与交接

本机 Windows 实盘 SQLite + 加密 vault 替身验证；这不是 Android/iOS 原生删除验收。测试位置 `apps/mobile/test/dm_lifecycle_test.dart`，生产改动限 `dm_controller.dart`、`dm_store.dart`、`dm_chat_store.dart`、新增 `dm_lifecycle_store.dart` 及 `dm_runtime.dart` 的生命周期部分，不改 UI。

每条命令前 `. E:/Hnuhole-env/env-windows.ps1`，随后设置 `$env:PUB_HOSTED_URL='https://pub.dev'`；工作目录 `apps/mobile`。

| 检查 | 状态 | 结果/范围 |
| --- | --- | --- |
| `flutter analyze --no-pub lib/src/messaging test/dm_lifecycle_test.dart` | PASS | 0 问题 |
| `flutter test --no-pub test/dm_lifecycle_test.dart test/dm_chat_races_test.dart test/dm_reliability_test.dart test/dm_chat_test.dart test/dm_chat_draft_ui_test.dart test/dm_route_test.dart` | PASS | 46 项，其中新增 13 项生命周期/通知接缝，既有受影响 33 项 |
| 原生 scope/密钥删除、正式 auth 装配、最终包短冒烟 | NOT_RUN | 由父任务整合后完成；本子任务不操作设备或共享服务 |
| 需要用户解锁/人工确认的验证 | SKIP | 用户不在，按当次授权直接跳过，不等待人工配合 |
| P1/P2 未受影响外观、IME、旧设备链路 | 复用旧证据 | 沿基线原版本/原范围，不重复、不提升 B08/B09 完整结论 |

13 项新增覆盖权威身份删除及独立草稿、持久 unknown 不换身份、共享图片引用、CLOSED 墓碑与旧连接、迟到 lookup/私有图、普通退出保留、仅清原账号、pending open 与已受理发送排空、purge 失败重试、可靠入站通知去重、会话接替和 Gate。开发中两次测试失败分别为测试 TEXT fixture 缺少协议必填键，以及重开 CLOSED 文件触发图片布局 marker 写入；后者已修复为 CLOSED 文件不再执行迁移，最终回归通过。

下一步：父任务 cherry-pick 后接正式注销回调、通知及举报装配；由独立审查检查 AT-15/AT-18 与后端最终事务的组合，完成受影响正式集成验证并统一记录结果。
