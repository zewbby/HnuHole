# DM-P2-DEVICE-RECOVERY：真实换机与异常恢复补验

2026-10-23 最终整合：P2 #51 已 merge 为 `988bb42045f4140c46cf9e890d985a774d033e16`，P3 #52 已 merge 为 `665291cdf312dec94fb11a75527524a821c5f008`；各精确 head 全部适用 CI 和独立整合审查通过。#55 改以 main 为 base 并整合 P3 merge，只解决五份文档并发插入，保留认证反馈、P2、P3 及补验记录。README／台账及任务记录已同步真实上游合并状态；用户已授权本 PR 检查通过后正常合并并构建。正式运行实现未变化，原生 SKIP、真实掉电／iOS／规模／生产未验不变；本 PR 自身最终回执在 PR 正文记录，不递归提交。

2026-10-23，分支 `test/direct-message-device-recovery`，基线 P3 整合提交 `07923b047dcc1bf8b431e7b6d94da31d28ec223e`。仅补二阶段原先未覆盖的真实双设备接替与异常中断恢复，不重复九图、UI/IME、管理功能及已通过服务端测试。未合并、未部署。

[Draft PR #55](https://github.com/zewbby/HnuHole/pull/55) 已提交，验收入口提交 `85429383dec780b92990dc48736d0fc02f168019`；base 为 `feat/direct-message-governance`，依赖 P2 #51 → P3 #52 → 本补验 PR。产品与协作 CI 已触发，最终结果以 PR Checks 对应最新 head 为准，不为补写最后回执递归提交。用户已授权主整合会话按顺序核对后合并 main 并构建，提交 agent 未执行合并或部署。

用户明确允许使用真我 RMX3366 与 vivo V2323A，均为物理设备。使用独立 `.dmrecovery` 包和全新合成账号、专用 PostgreSQL/TLS fixture，不读取日常账号或清除日常包。此次证明绑定当前整合代码，不冒充对旧 P2 APK 的再验收。

## 已执行结果

- **PASS：真实双设备接替。** 真我首次密码登录并保存文字、图片、未发送草稿与私人备注；vivo 使用独立安装 ID 对同一合成账号正式密码登录。新机恢复会话及备注，未下载旧机已 ACK 的正文，保留 unavailableUnread。旧凭据请求触发 unauthorized 并隐藏会话。真我再次正式密码登录，仍能读取本机原文字、原图字节 SHA256 和草稿；vivo 的旧凭据随后失效。
- **PASS：发送受理后、回执落地前强杀。** 在真实 PUT 已返回受理结果、DmController 尚未得到结果时冻结测试传输接缝，用 `am force-stop` 实际结束进程并核对 PID 已不存在。新进程查询原 commandId，SENT/attempt=1，只有一条对应本地记录。
- **PASS：接收落地后、ACK 前强杀。** 在原生 SQLite 已提交、ACK 尚未发送的位置冻结测试接缝，再强杀。新进程补收后本地只一条原 messageId，服务端 pending 已无该条，完成 ACK。
- **PASS：整机重启恢复。** `adb reboot` 前后 boot ID 不同，用户开机后解锁。新进程读取原机文字、原图 SHA256 及未发送草稿均通过，未清数据或重装。
- **NOT_RUN：真实突然掉电。** 用户确认“没有，真实掉电暂列未验”。内置电池设备的软件重启不代表突然掉电，不能将上项结论扩大。

源码：`apps/mobile/integration_test/dm_recovery_device.dart`，调用真实 HttpAuthApi、DmController 和 DmStore.openNative。操作入口：`tools/dm-recovery-device.py`；阶段 marker 只表明断言完成，不替代测试代码和实际 SQL/TLS/原生过程。机器证据、阶段 PID、包摘要和命令见[本轮记录](../design/direct-message-device-recovery-verification-20261023.json)。

## 复现入口与范围

先构建专用包：`HNUHOLE_DM_RECOVERY=1 flutter build apk --debug --no-pub -t integration_test/dm_recovery_device.dart --build-number=2026102304`。合成账号的固定测试用户名／密码会进入专用APK；会话令牌和临时fixture能力仅运行时注入app-private files，不写入APK或仓库，不含真实用户凭据。该包只用于独立验收，不作为日常包交付。

使用已有自有隔离 runner，明确 `DM_CHAT_TEST_PATTERN=^TestDMChatDevicePostgres$`、`DM_DEVICE_RECOVERY=1` 和私有 `DM_CHAT_DEVICE_FIXTURE`。该模式仅刷新测试签名授权证据，不改变会话 generation、不修改认证替换规则。设置 `DM_RECOVERY_ADB`、`DM_RECOVERY_APK`、`DM_RECOVERY_FIXTURE`、`DM_RECOVERY_EVIDENCE` 后运行 Python driver 的 `install/inject/phase`。两个 package 安装都实际成功；需人工配合时仅请求解锁及安装确认。

阶段顺序：真我 old-prime → vivo new-takeover → 真我 old-replaced/old-retake → vivo new-replaced → 真我 send-stop/强杀/send-recover → receive-stop/强杀/receive-recover → reboot-prime/系统重启/用户解锁/reboot-recover。

开发早期 old-prime 失败：验收程序图片请求多传 sourcePostId/sourceCommentId，被严格接口拒绝。Astra High 只读定位后仅修验收 body，业务代码未改；最终 2304 阶段通过。2302/2303 不作为成功包。

本地 `flutter analyze --no-pub integration_test/dm_recovery_device.dart` 0 issues，专用 APK2304 构建通过。独立 Astra High（`device_recovery_diagnosis`）只读增量审查 PASS；已关闭合成密码描述 finding，无剩余限定范围阻断，此审查不代表 GitHub 成员批准。

fixture 已由 owned done marker 停止，PostgreSQL 正常退出，私有凭据自动移除。两台专用测试包已卸载，自己的 58444 转发已清理或确认不存在，设备租约释放；日常包保留。无需重复已通过场景。iOS、规模性能、真实掉电及生产仍不在通过范围。
