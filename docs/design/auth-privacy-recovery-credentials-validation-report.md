# 恢复凭据管理：隔离实现与验证

日期：2026-09-30。分支：`codex/auth-privacy-handoff`。基线：`dc9f7a95816da6713947d8ed66c8c06f7da5af0b`。本轮按已收口的[恢复策略](auth-privacy-recovery-decision.md)、[数据/API 契约](auth-privacy-data-api-contract.md)、[迁移设计](auth-privacy-database-migration-design.md)和[C OpenAPI](../../packages/openapi/community-auth-api.yaml)继续实现恢复凭据管理。实验代码、迁移和测试仍与生产入口隔离。

## 交付范围

| 能力 | 最终行为 |
| --- | --- |
| 受限凭据清单 | 当前有效会话读取本人恢复码是否存在及最多十条 Passkey 的 ID、创建时间、必要备份标志；稳定排序，不返回原码、用户名、邮箱、槽位或设备详情。 |
| 恢复码轮换 | 当前会话加新鲜密码复验建立唯一十分钟意图，新建废弃旧意图，首次只显示新码一次。完整确认后原子替换旧码、消费意图、递增统一凭据版本，保留密码、其他 Passkey 和当前会话。 |
| Passkey 绑定 | 当前会话加新鲜密码复验，建立绑定原版本／会话／授权代次／固定策略的五分钟挑战及管理意图。固定 ES256、UV／residentKey required、attestation none；随机32字节 user.id/user.name，固定 displayName。最终验回包、复核原权限并原子登记、消费及推进版本。 |
| Passkey 移除 | 先凭新鲜密码建立固定本人目标的五分钟意图，再以 Bearer、Credential-Change-ID、幂等键做无体 DELETE；他人／已删目标统一404，原提交同键204；不能移除最后一个有效恢复途径。 |
| Passkey 恢复 | 匿名取得固定 RP 可发现挑战；有效 UV assertion 通过账号锁内原版本、公钥、句柄、BE和凭据存在复核后才显示私有用户名、新码和十分钟重设意图。挑战一次消费，保留旧恢复途径直到最终重设，不创建普通会话、不取消注销、不解除处罚。 |
| 统一失效 | 普通控制凭据变更立即废弃旧重设／管理权限并清其待展示摘要或 nonce，但不误撤保留的其他凭据。密码重设／正式关闭清全部 Passkey 和管理权限；密码重设继续撤所有旧会话。 |
| 留存与结果 | 不持久保存原 assertion、attestation、原恢复码、AAGUID或transports；提交结果不包含秘密，原键绑定本次操作／会话／目标。有界 worker 清过期秘密、七天终态元数据和受限事件；八天结果窗口后只留永久 EXPIRED 域摘要锚点。 |

密码计算和 WebAuthn 验签在锁外进行，携带原始证明到锁内。账号、限制、申请／意图／挑战、恢复凭据、会话、结果和最终 Gate 按序处理。每个成功授权、凭据清单、重试与清理都经最终可信时间及 authorization generation 复核；冻结恢复后旧挑战和会话不能重获权限。

新增 `0006_recovery_credentials.sql` 覆盖单调轮换代次、唯一活动轮换、操作形状、原权限绑定、随机用户句柄、不可变 Passkey 公钥／归属／BE及签名计数高水位。CHECK 对必需字段显式拒绝 NULL；管理挑战通过复合 FK 约束同一账号归属。独立管理意图和挑战分表，CREATE_PASSKEY 用同一ID一一配对。

WebAuthn 校验按 [W3C Level 3](https://www.w3.org/TR/webauthn-3/) 验证固定 origin、type、challenge、RP hash、UP/UV、ID/rawID、COSE EC2 P-256 和严格 ASN.1 ECDSA 签名。CBOR 限大小／深度且拒重复键、tag、不定长、尾随材料和未请求扩展。clientDataJSON 对未知字段保持规范兼容，拒重复键、topOrigin与跨源身份；签名始终覆盖原始字节，含可能的 BOM。同步凭据的零／非递增签名计数只记录最小风险事件，保存高水位，不仅据此拒绝恢复；BE变化拒绝。

## 验证证据

最终命令及源文件摘要记录在 [`recovery-credentials-verification.json`](../../services/api/authlab/recovery-credentials-verification.json)。`sh authlab/run-isolated.sh`、独立 `go test -race -count=1 -p 1 ./...` 和 `go vet ./...` 均退出0；完整隔离运行 authprivacy 100.137s、HTTP 8.379s。新增19个真实数据库测试、9组纯WebAuthn测试、9个HTTP契约测试及1条真实HTTPS→PostgreSQL凭据流程。本轮实际 PostgreSQL 和 HTTPS 验证使用 `sh authlab/run-isolated.sh` 的私有临时集群、C/V独立非超级用户数据库；无DSN的单独Go命令不能代替数据库验证。首次完整运行因实验RP与origin为兄弟子域而被严格配置校验拒绝，已改成固定共同RP并更新两个签名fixture；最终完整运行通过，没有放宽验证器。

测试覆盖轮换创建与替代、完整确认、原码失效、同键／异请求、保留会话与其他凭据、密码工作跨重设／会话接替／冻结恢复、并发轮换与绑定、全局凭据ID及账号归属、旧挑战／删除权限失效、到期／注销截止、一次性 assertion、恢复不取消注销、签名计数风险、十条上限和最后恢复途径、最小事件写失败全事务回滚、账号锁等待跨冻结、过期清理及永久墓碑。真实HTTPS端到端测试执行注册→轮换→绑定→可发现恢复→删除与同键重试→旧重设拒绝。

## 后续边界

本轮完成隔离服务端恢复凭据闭环。下一切片可进入移动端认证状态机：安全存储、未知提交结果持久核对、单设备接替、登出撤销待办，以及注册／保存恢复码／密码登录／恢复／注销操作的真实客户端串联。生产路由、正式迁移、通道与业务授权接入、业务注销投影和设备通知仍待做。

Passkey RP／origin 必须从独立部署配置注入；未配置时此能力 fail closed，HTTP Host或Origin不能选择配置。测试只使用合成RP／密钥，尚无真实iOS／Android同步平台、域名关联或可发现恢复演练证据。固定 residentKey 选项和 fmt=none 回包不能单独证明平台可发现能力。多副本共享反滥用、密码容量校准、独立授时／库外锚点、真实灾备、备份留存、V/C运营分权及独立人类审计仍是生产放行条件，隔离通过不代表生产就绪。
