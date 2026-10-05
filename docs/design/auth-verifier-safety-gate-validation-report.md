# AC01：V 独立 Safety Gate 交付与验证

日期：2026-10-04（Asia/Shanghai）。分支：`codex/auth-privacy-handoff`，基线：`faf557db4d74ecb2c202fd1349f1bf8fa64e6133`，实现保留在未提交工作区。任务依据与逐路径授权清单见[实施方案](auth-verifier-safety-gate-plan.md)。机器记录见[本轮验证记录](../../services/api/authlab/verifier-safety-gate-verification.json)。

AC01 代码已实现，开发范围验收 PASS。最终全量 SQL／race／vet 和实际 C/V 进程、正式迁移与权限验收均退出 0；生产证据和平台缺口继续单列。

## 实现范围

- 复用 Gate 状态机，为 V 单独选择白名单 `v_auth` schema；C 默认行为保持。V 有独立状态、审计、5 秒回退容忍、最多 5 分钟证据、库外签名锚点、授权代次及显式受限恢复。
- 正式 V 迁移 3→4 初始化 FROZEN，为 OTP flow、confirmation、sign job、mail outbox 和 retire pending 增加不可变代次。升级前代次 0 和恢复前 pending 不可重绑定新代次。
- V 的 OTP、预算／设备锁、确认、资格签名、原确认退役、收据释放、邮件派发／回调及有界清理统一使用可信时间和最终授权事务。签名／SMTP／mTLS 调用留在事务外，回调复核原代次及原任务；结果读取也复核 Gate 与结果期限。
- V 使用独立有界 Gate 连接池，避免业务事务占满连接后无法刷新可信时间；业务事务仅在最终提交点取得 Gate 行锁，前置 Snapshot 在独立短事务中取锁并释放，避免业务锁与 Gate 锁顺序反转。
- runtime、readiness、`authdev`、独立 V 操作配置、用途密钥分离和最小数据库权限均接通。V API 无恢复角色成员资格、代次推进和开放时间写权限；恢复工具拒绝权限漂移。
- 共享核心修复了恢复等锁／证据提供者等待时复用旧时间的缺口；取得锁和证据后重新采样，过期证据不能解禁。

## 执行证据

| 检查 | 当前结果 | 精确范围 |
| --- | --- | --- |
| R01/R02 `sh authlab/run-isolated.sh` | PASS，退出 0 | 本次专属私有 socket、两个非超级用户库、全部服务端 `go test -race -count=1 -p 1 ./...` 与 `go vet ./...`。 |
| 初轮失败后的聚焦 SQL／race／vet | PASS，退出 0 | 同一受保护一次性集群流程的临时筛选封装；V Gate／业务、旧退役清理、公开协议向量和双侧 Gate HTTP 场景。不是给原 runner 传不存在的筛选参数。 |
| R03 `sh authlab/run-runtime-isolated.sh` | PASS，退出 0 | 实际 C/V cmd、HTTPS/mTLS、Mailpit、正式迁移、受限角色、V3→4 非空配额保持、权限负向、独立冻结／重启／恢复、旧代 OTP、旧 V schema 恢复与证据过期；保留原 C、身份及关闭释放流程。 |
| 最终待测源码逐文件比对 | PASS | Windows 工作区与 WSL 副本的 128 个源码文件字节相同；摘要 `5174c37ea08db8d4944ef1e0b9058de3f6461b4b9061ebcd26c5612922eb0aad`。 |

核心与业务新增 20 个顶层测试函数，另有两个 HTTP＋SQL 独立 Gate 测试。覆盖回退阈值、高水位、证据故障、多副本、重启、完整旧 Gate／audit 行镜像、恢复权限／重放／break-glass、等锁与证据读取跨过期、连接池饱和、签名／邮件／退役迟到和业务最终期限。用例名及最终状态由机器记录列明。

初轮编译发现新测试局部变量未声明，已修。初轮 SQL 暴露两处测试 fixture 问题：旧退役构造未绑定当前代次，以及行锁等待用了 advisory 锁观察屏障；均保留原安全断言后修正。公开向量原始字节在 Windows checkout 被换成 CRLF，已对 `v1.json` 固定 LF，恢复原公布 SHA-256；没有变更协议向量或校验期望。初轮旧代 OTP HTTP 预期误写 503，已按已有明确失效契约修为 `422 OTP_EXPIRED`；FROZEN 仍返回 503。

## 明确语义与证明边界

V 恢复会废止旧 pending 授权作业。它不会撤销此前已经提交并被用户取得、仍符合原协议有效窗口的签名票据，也不会抹去 C 已提交收据事实；协议票据本身没有 V generation 字段。旧确认不能通过恢复重新签发，旧 OTP 在恢复后失效。

邮件在获得授权并开始外部 I/O 后可能已经被 SMTP 接受，冻结无法撤回已发生的外部效果。迟到结果不会复活旧代作业，已 claim 的不确定派发保持不自动重发，后续按可信期限清理为 UNKNOWN。测试不宣称跨 SMTP／C／V 的原子提交。

R03 恢复的是包含资格业务与 Gate／audit 的完整 `v_auth` schema 逻辑快照，并保留库外锚点；这不是物理整库／WAL／跨机生产灾备演练。若数据库与独立锚点一起回退，同机文件机制不能证明新鲜性。真实独立授时、生产库外存储、双主体运营、灾备与人类安全审计继续列 P02/P03/P06。

本次没有重新执行 Flutter、Android/iOS、系统 Passkey、物理设备矩阵或完整真机 App→实际 C/V 全流程。历史平台证据保留原版本与范围。AC02、AC03 尚未实施，B02 整模块保持 BLOCKED。

## 复验与交接

使用[本机环境](local-test-environment.md)中的既有 WSL Go、PostgreSQL、固定 Goose 与缓存镜像，在 Linux 文件系统的源码 checkout 中运行：

```sh
cd services/api
sh authlab/run-isolated.sh
sh authlab/run-runtime-isolated.sh
```

第一个 runner 自建私有集群，并设置受保护 fixture 所需 DSN；不能用无 DSN 的普通 `go test` 替代 SQL 证据。第二个 runner 自建唯一 Docker 项目并清理自身卷，不下载镜像，也不接受未知用户数据库。

源码、测试源码和脱敏小型记录保留。本轮专属测试副本、Go 模块／编译缓存、私钥、临时集群、运行日志和本地辅助目录已清理；两次 R03 的精确项目均确认没有遗留容器或卷。本轮临时启动的 Docker Desktop 已正常停止，已有 D 盘工具与原镜像保留，没有全局 prune。本次未提交／推送／部署。
