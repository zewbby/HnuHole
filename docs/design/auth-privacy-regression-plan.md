# AC04 匿名基础链路覆盖与回归任务单

日期：2026-10-05。分支：`codex/auth-privacy-handoff`。基线：`cbc99b010ba23bba42f76e2523269e3952b14392`，开始时工作区干净。

## 三步实施

1. 将 AC01–AC03 的关键不变量映射到真实测试函数、R03 实际进程阶段和 R05 客户端操作；保留原版本证据，区分已覆盖、缺场景、平台及未来业务未集成。
2. 补 R05 真实 Dart→HTTPS handler→一次性 SQL 的 V 独立冻结／恢复旧 OTP 失效，以及身份缓冲／取消／正式关闭、永久历史与同邮箱新账号隔离。只扩展测试与私有 fixture，不实现帖子、评论或聊天。
3. 在既有 WSL2 Linux 工具环境执行 SQL／race／vet、R03 与 R05 相关回归和 Flutter 静态检查；记录固定源码摘要、真实结果与失败修复，同步模块交接／台账、HANDOFF、progress。清理本次明确创建的缓存、一次性数据库与进程。

## 结束条件与边界

每个关键不变量有测试入口、执行记录与精确证明范围；新增真实客户端场景运行通过，失败先修复再复验。R05 使用内存 vault 和实际 HTTP handler，不能宣称完整 App→实际 cmd／原生存储通过。AC05 平台、系统 Passkey、物理设备及 P02–P06 生产证据继续单列；B02 整模块仍 BLOCKED，未来业务消费者未实现。结果见[回归报告](auth-privacy-regression-validation-report.md)和[机器记录](../../services/api/authlab/privacy-regression-verification.json)。
