# AC02：整账号正式关闭与身份联动验证报告

日期：2026-10-04（Asia/Shanghai）。分支 `codex/auth-privacy-handoff`；基线 `faf557db4d74ecb2c202fd1349f1bf8fa64e6133`，保留未提交 AC01。任务依据与执行步骤见[实施任务单](auth-identity-account-closure-plan.md)，精确结果见[本轮机器记录](../../services/api/authlab/identity-account-closure-verification.json)。

AC02 已实现，当前服务端范围验收 PASS。完整 SQL／race／vet 与 R03 实际进程验收均退出 0；没有将 AC01 的旧源码摘要当作 AC02 通过证据。当前 133 文件摘要 `300d31ce7526c836473fc372bb6309d85944289d28ab86361300f5bd0c7af07d`，工作区与 WSL 被测文件字节一致。

## 实现与事务边界

- 七天缓冲、登录取消和封禁取消不改变身份资料。正式关闭在账号锁及 C 最终 Gate 授权下，原子提交账号 CLOSED、凭据／会话撤销、活动身份资料擦除、槽位关闭与 RELEASED outbox。无需等待 V ACK 才注销身份。
- 擦除活动身份的昵称、头像和改名时间，删除时间使用最终可信时间。原身份 ID／归属／原始身份标记／创建时间、累计创建计数、成功／拒绝永久回执和已有单删墓碑继续保留；不合成用户 DELETE 收据。
- 正式迁移 11→12 允许 CLOSED 的活动身份归零，未关闭且已有身份的账号仍至少保留一个，零身份账号不自动创建计数或身份。账号状态变化也触发延迟一致性校验，阻止只关账号却留下活动资料；运行时拒绝旧版本及缺失／禁用该触发器。
- 身份生命周期事务显式 READ COMMITTED；延迟约束串行锁账号后读取聚合，其他隔离级别被拒绝，防止旧快照下的直接 SQL 聚合写偏差。
- 独立注销投影只返回身份级全长 opaque token、统一头像 token 和 DELETED／ACCOUNT_CLOSED 状态。token 仅由随机身份 UUID 域隔离派生，不含共同账号或时间；正式关闭优先于此前单删状态，原占位 token 保持稳定。没有新增任意身份查询接口。

## 升级修复边界

此前 CLOSED 账号遗留的活动资料在迁移中前向擦除。修复 marker 来自 Gate 已持久可信高水位，要求不早于原资料的创建／改名时间；不足则整个迁移拒绝并回滚。该 marker 仅记录升级时资料修复，不代表能找回原关闭时间，也不用来签发新资格、判断七天期限或改写旧回执。

升级 fixture 使用明示合成 checkpoint 验证这一规则，保留 ACTIVE／PENDING 账号资料、已有墓碑、累计状态及回执的原始字节。实际关闭仍只用最终 Gate 时间。

## 当前执行状态

| 检查 | 当前结果 | 范围 |
| --- | --- | --- |
| R01/R02 `sh authlab/run-isolated.sh` | PASS，退出 0 | 全部服务端 `go test -race -count=1 -p 1 ./...` 与 `go vet ./...`，专属私有 socket、两个非超级用户库。authprivacy 275.028 秒，HTTP 21.810 秒，其余包及协议均通过。 |
| R03 `sh authlab/run-runtime-isolated.sh` | PASS，退出 0 | 实际 C/V、正式 11→12、缺／禁用约束拒绝启动、权限、缓冲／取消／正式关闭、旧资料修复及同邮箱新账号；保留 AC01 实际流程。 |
| 最终编译 | PASS，退出 0 | `go test -run '^$' ./...`，仅证明可编译；SQL 证据由完整 R01 提供。 |
| 最终被测源码比对 | PASS | 133 文件字节一致，摘要如上；Go 自动重整了 `go.work.sum`，已保留实际被测 checksum 元数据，`go.mod`／`go.sum`及应用源码没有因此改变。 |
| 当前／历史交接核对 | PASS，退出 0 | Windows Python 执行 `tools/check-identity-handoff.py`，核对模块ID、文档路径、历史B02与当前AC02证据及源码摘要；仅证明台账一致性。 |

新增 12 个顶层测试函数，源码为 `community_identity_closure_test.go`（9个）与 `identity_closure_migration_test.go`（3个）。实际覆盖零／一／三身份、缓冲与取消逐字段相等、4 worker一次提交、CREATE／RENAME两种真实账号锁顺序、SQL故障整体回滚、身份锁等待期间冻结及恢复旧代拒绝、释放后新号独立历史、RC直接SQL双删只能提交一方、其他隔离拒绝、legacy修复及不足水位回滚、有限投影字段与独立占位。函数名由机器记录列明。

静态交接初轮发现检查器混用了历史／当前结果入口，以及 PowerShell 文化排序与 Python 路径排序造成汇总摘要不同。检查器已分别核对历史和当前证据，当前 AC02 摘要统一为 Unicode 码点顺序；133 个被测文件的实际字节未改变。历史 AC01 摘要保留原计算与版本，不重写成当前通过。

## 未执行与后续依赖

本片提供现有身份关闭与纯投影边界。帖子、评论、聊天、本人本地聊天／私人备注／搜索清理尚无完整业务调用者，不能登记已接入或 X06/X07 全场景 PASS。独立 token 的 UI 编号格式、注销头像图稿和单删提示文案仍待对应设计；本片未擅定六位平台号或公开共同归属。

本轮未改移动端源码或公开 HTTP wire contract；R05／Flutter／Android／iOS／系统 Passkey／物理设备未重跑，历史证据保留其原版本和范围。AC03 尚未实施，B02 整模块继续 BLOCKED，生产分权、真实灾备与人类独立审计仍单列。

R03 使用专属到期请求 fixture 跳过实际七天等待；同邮箱再注册前，仅调整本轮生成邮箱的发送等待 fixture，保留全部触发器与 OTP 寿命。这些证明服务端边界和流程，不宣称七天／六十秒实时间验收。

## 复验入口与产物

使用[既有本机环境](local-test-environment.md)，在 Linux 文件系统的源码副本中运行：

```sh
cd services/api
sh authlab/run-isolated.sh
sh authlab/run-runtime-isolated.sh
```

两入口仅自建明确归属的专属库／项目，不传未知 DSN，不发明模块筛选参数。源码、测试源码与小型脱敏证据保留；本轮专属副本、Go缓存、密钥、日志、临时集群及容器／卷已清理，精确R03项目无遗留容器／卷，临时启动的Docker Desktop已正常停止。已有工具／镜像保留，没有全局prune。未提交／推送／部署。
