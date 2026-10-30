# 隔夜关机恢复验收归档

2026-10-30；分支 `docs/session-overnight-acceptance`，基线 main `31a05d9`；用户授权同步记录、恢复说明、PR及检查通过后合并。仅文档和脱敏证据，无产品改动或新部署；合并状态以本任务PR为准，不将待合并文档记为已合并功能。

AUTH-SESSION-RESUME-01 原代码由PR #48合并、PR #50交接。本次补齐此前未验的隔夜场景：10月29日用户重新登录，已核对vivo2702登录与冷启动保留；10月30日恢复原部署，冷启动直接回已登录页面。关机前后会话集合不可逆指纹相同，C/V代次和RECOVER审计次数相同，严格TLS ready200，无重登/重装/清数据/recover。约9.6小时是后端最后可信活动到恢复的间隔；关机由用户报告，没有独立硬件断电计时。

10月23日缺登录基线、10月29日真我当前用户缺主体App的结果不计手机通过；建立新vivo基线前用户自行卸载签名不兼容旧包并重新登录，这不是关机保登证据。正式验证窗口自基线确认后开始，基线后未重装、重登或清数据。

- [脱敏机器证据](../design/validation/session-overnight-20261030.json)：只归档时间/版本/通过判定及本地制品摘要，不提交账号、会话指纹原值、设备序列或秘密。
- [当前恢复说明](../design/session-runtime-recovery.md)：C28/V7、两个限流Redis及第三个快照Redis，先同步resume再API；旧私有启动脚本未在本PR修补，不能当作当前launcher。
- [原修复交接](fix-session-restore.md)、[进度](../design/progress.md)、[HANDOFF](../design/HANDOFF.md)、[模块表](../design/module-acceptance-handoff.md)、[台账](../design/module-acceptance-ledger.json)。

本次验收PASS限同机开发环境/单台vivo2702隔夜恢复，历史模块整体、生产、iOS和其他设备矩阵不变。检查范围：证据基线字段一致、JSON解析、相对链接、脱敏、diff和协作检查、独立只读审查；远端适用CI以精确提交为准。纯文档不重复运行产品或设备验收。本次PR自身不递归写入最近变动；合并后核对主线记录并保存合并回执。
