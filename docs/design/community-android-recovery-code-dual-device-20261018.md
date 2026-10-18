# 恢复码双实体 Android 验收记录

2026-10-18，Asia/Shanghai。结果：**PASS_APPROVED_RECOVERY_CODE_TWO_DEVICE_SCOPE，8项限定检查通过**。用户将当前可执行范围改为恢复码双设备，Passkey 单独待补；本轮没有扫码、调用提供方、修改产品代码或其他分支。

## 固定版本与设备

- 本任务独立 clone：`E:\HnuHole-community-f4-20261012\repo`；分支 `codex/community-flutter-pages`；起始与最终 HEAD 均 `dd5745a10bb0c732b5cf8b5ffc25a471e26f1b13`，本轮仅追加脱敏文档，未提交/推送。
- 固定认证来源 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。两机使用原 HnuHole Stage4，包名 `org.hnuhole.hnuhole_mobile.communityf5.passkey.control`；APK SHA256 `6cce56a7879bd76b2db9c1ed1b63c6326b1abb029a6f6f853d9c7a250470229c`，证书 SHA256 `3309ce001a5dfd93148c14e35159147a6711e4b61d881b7a223b3e8429665e34`。沿用既有构建证明，不重建/换签名/升级依赖。
- vivo S18 / V2323A / Android15 为源机，真我 GT 大师探索版 / RMX3366 / Android14 为目标实体机。只使用既有获准 USB 身份与隔离端口34881；全局5037、认证会话环境均未动。
- 用户删掉真我当前用户的测试 App 后，全局原 APK 仍由另一手机用户保留。实测 SHA 与批准包一致，故只执行 `cmd package install-existing --user 0`；其他手机用户状态逐行核对不变。没有冒称恢复卸载前的用户数据，也没有把直接安装算成 OEM 搬家。

## 本轮实际验证

| ID | 结果与证据范围 |
|---|---|
| RC-X01 | PASS — Restore the user-deleted realme user-0 task App from exact existing signed package; guest, no automatic authority；外部回执 `target-reinstall.json`。 |
| RC-X02 | PASS — Source active session and source-only native draft witnessed before target recovery；外部回执 `source-draft-before-reset.ui.json`。 |
| RC-X03 | PASS — Actual second Android recovers the expected synthetic account using only the existing recovery code; no username/password hint；外部回执 `code-reset-begin.submitted.json`。 |
| RC-X04 | PASS — New code hidden and fully retyped before actual reset commit; no automatic login; old active source session and old C Passkeys revoked；外部回执 `code-reset-confirmed.json`。 |
| RC-X05 | PASS — Actual HTTPS C rejects both old password and old recovery code with 401; no successful host login or extra SQL side effects；外部回执 `old-credential-negatives.json`。 |
| RC-X06 | PASS — Explicit new-password login succeeds on realme and vivo; no Google or Bitwarden authentication needed；外部回执 `target-new-password-login-01.submitted.json`。 |
| RC-X07 | PASS — Both physical Apps restore native sessions across force-stop/reopen; source draft marker retained and absent on target；外部回执 `source-draft-and-session-after-reopen.ui.json`。 |
| RC-X08 | PASS — Two-way single-mobile-session replacement enforced by actual App protected reads and exact SQL session witnesses; target active at finish；外部回执 `source-final-session-replaced-by-target.ui.json`。 |

同一旧有效移动会话在恢复意图受理后仍有效；实际确认提交后被撤销。凭据版本5→6、已消费重设意图1→2、旧服务端Passkey2→0；未改Gate或协议。旧密码与旧恢复码的本轮真实 HTTPS 请求均401。没有读取或删除手机密码库里的密钥条目。

新密码通过实际 App 显式登录：目标会话代次10，随后源机11接替目标，最后目标12接替源机；各阶段始终仅一个有效移动会话，SQL精确摘要与受保护页面拒绝相互印证。源机 PID13099→22547，目标19635→22270，均强停重开保留数据；原 `Stage4Local` 草稿标记在源机重新登录后可见，目标始终没有该标记。该项证明本地标记隔离，不宣称本轮重新逐字校验完整草稿正文。

重新认证后，旧页面的权限快照仍闭合；返回首页后重新进入“我的”才能看到当前账号数据，已按现有权限快照设计验证，没有修改该行为。没有发帖、删帖、注销；两个合成账号和公开帖数量保持2/0。

一次只读UI采集并发碰撞使目标登录driver在提交前停止，原输入完整核对后仅提交一次；不是App认证失败，没有重试未知POST。首次包路径CRLF解析也在安装前停止，修正只影响外部driver。中途名为 `recovery-code-after-commit-20261018.sql.json` 的观察实际发生于提交前；最终提交证明使用 `recovery-code-commit-final-20261018.sql.json`，不按文件名误算结果。

## 证据、命令与最终状态

外部执行根：`E:\HnuHole-community-f4-20261012\stage4-execution-20261016\recovery-code-execution-20261018`。实际设备命令和各次 SQL 摘要收录于[机器记录](community-android-recovery-code-dual-device-20261018.json)；`window.py` 为本轮独立设备driver，`check-old-credentials.py` 是两次已知旧凭据负向 HTTPS 检查。`owned-sql.py` 位于其父目录，仅对明确归属的 `hnuhole-community-s3-e974f2621f` 一次性库读观察。

没有改运行源码，故未重跑主机七阶段或构建；2026-10-16主机334等记录保留其原版本/范围，不计为本轮新增检查。当前8项指实际双实体恢复码检查，不是历史F4八项或主机项。

有效会话最后留在真我；vivo依单移动会话规则被接替，原本地草稿保留。两机provider/autofill值与本窗口开始逐字一致，其他测试App保留；只移除本窗口新加的反向映射并关闭精确自有ADB进程，临时后端与私有材料保留。后续连接测试后端需重新建立本任务USB反向映射。

当前合成账号的最新密码/恢复码只在 WSL 所属实验目录私有文件 `lab/fixture/recovery-code-two-phone-20261018.private.json`，权限600；不进入Git/聊天。旧 `reset-from-phone.private.json` 仅为历史/负向材料，后续driver不得继续当成当前凭据。

## 单独待补项与复验条件

- **NI-X02 Passkey双Android**：按用户要求延期，不能用恢复码替代它的Passkey证明。当前真我报告 `android.software.credentials=false`、`credential`服务不存在；官方更新页显示 realme UI5.0、`RMX3366_14.0.0.2100(CN01)` 已是最新。需有第三方凭据系统能力的第二实体机或厂家提供支持的正式更新，再先只读核对后验；不扫码，不强行写配置。
- **NI-X01 OEM搬家**：仍NOT_RUN；此前没有实际开始传输，本轮只做同包恢复安装，不算OEM迁移。没有再次执行用户已拒绝反复尝试的搬家流程。
- iOS、生产部署与完整App验收仍未通过。本轮不发布Release、不部署、不合并main。

新一轮恢复码复验应先读最新私有凭据与原待办状态，以新窗口/新日志执行普通恢复入口、隐藏原码完整确认、旧凭据拒绝、显式登录和会话接替；本轮一次性恢复码及提交命令不可盲目重放。完整四阶段任务没有被本轮限定PASS替代。
