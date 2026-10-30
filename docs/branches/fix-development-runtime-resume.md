# DEV-RUNTIME-RESUME-01：旧启动入口统一绑定已核验部署

2026-10-30，分支 `fix/development-runtime-resume`，基线main6233c8f；用户要求修旧入口、验证后PR直接合并。本轮从此前隔夜验收继续，修改恢复工具及现有机器入口，不变更产品API/App或迁移。

新增[版本绑定恢复器](../../tools/development_runtime/README.md)，以私有清单核对receipt/source、静态依赖闭包、真实schema与进程归属；保留原PG/AOF，双同步resume先于API。三个旧入口已有私有备份并替换薄转发，当前批准C28/V7/a2e98，包含第三个独立快照Redis；未来部署须显式更新批准清单。未创建新的开机任务，旧命令继续可用。

10项单元/编排边界及-O各PASS；最终安装恢复器完整依赖冷启动PASS（2PG/3Redis/4API-watch），三入口反复执行PID不变；错误source副本拒绝、C/V严格TLS ready、原会话/代次/RECOVER审计不变。首次实现把动态Gate证据误列静态pin，首次noop被拒绝；已剔除动态证据/锚并保留静态key，补依赖覆盖回归后重跑通过。一个PID复用测试最初误调用被mock的函数，修正为真实校验函数后10项全通过。旧失败不计PASS。

本次附加手机冒烟未执行成功：已连接vivo但主体无可启动activity，不重装或重新登录去代证；原PR89的2702隔夜手机PASS按原窗口保留。本任务恢复脚本验收以真实库/Redis/服务和原会话不变为准。后续真实整机再次关机启动未追加，不冒充新隔夜测试；生产/iOS/完整设备矩阵未验。

[脱敏证据](../design/validation/development-runtime-resume-20261030.json)、[恢复说明](../design/session-runtime-recovery.md)、[历史隔夜证据](../design/validation/session-overnight-20261030.json)。独立只读审查和最终精确HEAD CI通过后按用户授权合并；当前状态以本任务PR为准。合并后核对主线并保存回执，不递归提交自我登记。原私有清单、配置、代码副本、进程日志和备份不进入Git。
