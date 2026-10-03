# B02：身份管理基础实施任务单

日期：2026-10-02（Asia/Shanghai）。分支 `codex/auth-privacy-handoff`；保留现有未提交认证工作。

- 目标：已登录用户从“我的／设置”管理本人持续发言身份；零身份账号仍可浏览。
- 范围：本人列表、创建、改名、删除、默认头像、持久原结果核对、会话失效处理。帖内绑定、内容和聊天删除投影随对应业务模块实现；自定义头像上传随媒体功能实现。
- 依据：[身份规则](modules/identity.md)、[个人规则](modules/personal.md)、[Safety Gate](auth-authorization-safety-gate.md)。首个身份按需创建，注册不自动创建；删除后至少保留一个，同时最多三个。
- 方法：同一账号行锁串行化身份操作，最终 Gate 事务复核会话、资源归属、可信时间和业务规则。成功操作及确定业务拒绝与账号归属幂等回执原子写入；未知结果先核对，同一意图始终使用原键。

## I1：存储与规则

在正式 `services/api/migrations/0011_identity_management.sql` 和 `internal/authprivacy` 增加身份记录、累计创建计数及永久成功／拒绝终态回执。第三次累计成功创建起按上海日历加六个月、目标月末夹紧，此后每次成功创建重新计时；删除不减累计次数。昵称二至十二可见字符，同账号大小写敏感判重，首次成功改名后等待满三十天。软删除保留稳定资源ID但清除旧昵称；未来投影使用删除状态。

验证：纯规则测试与真实 PostgreSQL 测试涵盖日期边界、非法字符、数量、累计次数、同名、归属、并发、幂等、冻结、会话接替和过期。不运行无DSN测试冒充SQL通过。

## I2：HTTP契约与运行时

增加 `packages/openapi/identity-api.yaml` 和 `internal/authprivacyhttp/identity_endpoints.go`：本人列表，POST创建、PATCH改名、DELETE删除；变更及结果查询使用16字节规范无填充base64url的 `Idempotency-Key`。结果查询为 `GET /api/v1/identity-change-result`。成功均返回同Bearer的 `Session-Expires-At`；不暴露账号、其他身份共同归属或已删除资料。所有错误沿用公共包装。更新非owner运行权限、迁移就绪门槛与一次性fixture。

验证：真实TLS替身契约测试、真实HTTPS/SQL端到端测试源码、OpenAPI引用／结构与完整规范验证（后者依赖锁定工具）。

## I3：移动端闭环

在 `apps/mobile/lib/src/identity` 增加严格HTTP解析、控制器和身份管理页面；主路由增加“我的→设置→身份管理”。复用现有origin隔离vault、账号归属与会话代次；提交前持久保存不可变意图，未知结果和重启核对保留原键。同Bearer截止先持久再展示，旧会话迟到结果不发布。列表有空状态、名额／日期提示、默认头像与删除影响确认；不添加虚构内容页。

验证：控制器、HTTP、输入法与组件测试源码；Flutter分析、小屏大字／无障碍、重启与会话接替验收按工具／设备可用情况登记。

## I4：复核与交接

检查授权事务、跨账号与未知结果边界，执行可用的轻量检查并记录源码指纹。同步 `module-acceptance-handoff.md`、`module-acceptance-ledger.json`、`HANDOFF.md` 和 `progress.md`。B02登记为“基础管理已实现，业务联动待实现”；代码状态与验收状态分开。2026-10-03 用户纠正分支范围：后续改按[匿名收口清单](auth-privacy-closure-checklist.md)推进；原完整业务顺序留待匿名分支交付后另行开发。
