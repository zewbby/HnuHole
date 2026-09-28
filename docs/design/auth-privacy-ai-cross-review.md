# Hnuhole 认证隐私 AI 交叉评审记录

日期：2026-09-28。范围：**实施前规格；没有认证代码、实际 SQL 或生产部署验收。**

## 1. 输入、评审者与事实

- 初审固定源：`41fba7761035ee5aafb0e3beb55bf7b8d21f539a`。19 份原材料及摘要已导出成锁定快照；修正版须另建快照，不能把旧输入称为修正后版本。
- 首轮由 `/root/fresh_auth_privacy_review` 完成，启动时不继承前文讨论，直接读取固定提交的七份认证设计文档与 V/C OpenAPI。根 agent 另行核对发现及原有信任边界；修正规格后由同一评审 agent 回归复核。
- 这是内部 AI 交叉评审，不是人类第三方审计，不证明运营方独立、生产库准入、真实事务正确性或上线安全。
- 用户已提供的事实：学校邮箱可用；计划中的 C 正式后台尚未建；暂无人类独立评审者。邮箱可用不代表 OTP／配额服务已搭建，V/C 的运营主体和实际权限仍未确认。仓库已有的目录演示切片不算完整认证后台。
- 本机 Claude Code 2.1.267 已确认存在。首次调用因九份材料的外部披露未获明确授权被自动审批拒绝；用户随后明确授权同一固定提交的九份材料。重试已获准，输入为297239字节，SHA-256 `22bc43eb5863cf502d5367dc9c6778b4f8a3ff83a46538a5f5f3d14017062c1e`，请求xhigh，关闭工具／MCP／本地自定义／持久会话。CLI立即返回 `Not logged in`（进程1、`is_error=true`、费用0），另查 `claude auth status` 得到 `loggedIn=false`。未产生Claude模型评审结果。用户随后明确本轮暂不使用Claude Code，采用新上下文subagent评审；外部评审与本机登录不再作为本轮交付前提。

## 2. 初审发现与处置

初审结论：`REQUEST CHANGES`，一项中等规格完整性缺口。没有据此发现新的旧号接管或诚实 V 下同邮箱双号路径。

### AI-01：RETIRED 收据缺少持久确认通道

初审固定源的[数据契约第44行](https://github.com/zewbby/HnuHole/blob/41fba7761035ee5aafb0e3beb55bf7b8d21f539a/docs/design/auth-privacy-data-api-contract.md#L44)与[迁移设计第59行](https://github.com/zewbby/HnuHole/blob/41fba7761035ee5aafb0e3beb55bf7b8d21f539a/docs/design/auth-privacy-database-migration-design.md#L59)要求 C 的 `RETIRED/RELEASED` outbox 保留至 V 持久 ACK。但该源的[C 退役接口](https://github.com/zewbby/HnuHole/blob/41fba7761035ee5aafb0e3beb55bf7b8d21f539a/packages/openapi/community-auth-api.yaml#L893)只有返回收据的拉取流程，[V 内部入口](https://github.com/zewbby/HnuHole/blob/41fba7761035ee5aafb0e3beb55bf7b8d21f539a/packages/openapi/verifier-auth-api.yaml#L327)只接 `RELEASED`。这些链接锁定初审旧版本，修正版见当前仓库文件。

双方诚实也可遇到：C 提交退役并返回收据 → V 持久释放旧配额、终结退役待办并停止拉取 → C 无通道得知 V 已提交。HTTP 响应送达不能证明 V 数据库提交。结果是成功退役仍永久保留未确认 outbox，无法按约结案或清理；保留槽位终态仍能拒绝旧票，此发现不构成夺号证明。

**采纳，修正规格：**

1. 新增 V `POST /internal/v1/slot-retirement-receipts`，只接受已有固定 `RETIRED` 收据；环境绑定 C mTLS 与 C 严格签名均必需。现有 `RELEASED` 入口保留单一用途。
2. V 拉取／C 推送共用同一持久处理命令，按 `(slot, purpose)` 幂等。首次匹配原待办、旧配额版本与当前槽位才清占用；同用途重试只 ACK，未知映射或异用途冲突不 ACK、不清新槽位。
3. 保留原确认键及旧／新槽位、公钥的绑定；迟到拉取结果不回退已处理终态。收据 ACK 本身不签新资格；原确认续办另核对有效 OTP 与当前配额，避免第二槽位。
4. C 将受信 ACK 与永久槽位终态的单调 `receipt_acknowledged` 同事务记录。清理从 C 本地提交起算，重复 ACK 不延期；迟到签名／投递不得复活任务。状态页只读重签、灾备恢复和用途冲突规则一并补齐。

固定签名帧、槽位散列和原向量 JSON 不变。V 从 5 增至 6 个操作，C 仍为 22 个操作。新持久确认链路须在未来实际 SQL／服务中运行故障与并发验收，静态文档不能证明其运行正确。

### 非阻断说明：OTP 结果过期后的下一次收码

`410` 不是原邮件未发送的证明。现有新发送规则可覆盖用户明确开始下一次收码，没有据此认定永久锁死；只补客户端退出过期旧核对流程的说明。新操作仍读同邮箱预算、等待和未决发送，未知 `PENDING` 时只能推进原键，不能自动换键补发。

## 3. 修正后复核与证据

状态：**规格阶段 `APPROVE WITH NOTES`；AI-01 已在文档闭合，未发现剩余实质规格缺口。** 评审 agent 对实际 MD/YAML 补丁复读，核对单调 ACK、原确认续办与准入桶、状态页重签及灾备，不据此宣布实现通过。

根 agent 使用 PyYAML 6.0.3、openapi-spec-validator 0.9.0、jsonschema 4.26.0 重新检查三份 OpenAPI：结构有效、无重复 YAML 键、本地引用均可解析、操作 ID 不重复，操作数 V 6／C 22／通道 1。新请求 Schema 接受一份合成编码、拒绝十一种错误形状；ACK 接受一种、拒绝三种。跨方退役收据 Schema 一致，固定向量摘要未变化；**合成编码的接受不是签名验签成功**。逐文件摘要及范围见[本轮静态记录](../../packages/auth-protocol-vectors/retirement-ack-static-verification.json)。`git diff --check` 为 0，新增文档链接可解析，改动范围只有 MD／YAML／JSON。

实际服务／SQL 的待验收交错已加入[迁移验收包](auth-privacy-database-migration-design.md)与[送审验收表](auth-privacy-security-review-package.md)：拉取先完成／推送先完成、ACK 丢失、原确认续办竞争、迟到观察、重签与信任撤销、ACK 本地提交、清理和旧备份恢复。

初审逐份读取固定文档和接口，向量 JSON 仅复核无重复键解析、分组与固定摘要；未重新执行签名库向量，未运行实际 SQL、并发故障注入、移动端 WebAuthn、灾备、限流或运营权限核查。先前静态签名结果继续以[原记录](../../packages/auth-protocol-vectors/static-verification-report.json)的输入版本和实际范围为准。

## 4. 仍未完成的门槛

G1 的生产库与实际 SQL、G2 的服务／客户端交错、G3 在线攻击参数、G4 运营分权与留存、G5 用户走查、G6 具名独立结论仍未验收。AI 可以继续挑战规格和实现，但不能凭开一个新上下文宣布这些证据存在。

下一项实证工作应是获得实施授权后，在隔离环境验证最小 SQL 约束、注册／退役竞争及提交后签名与 ACK outbox；不以继续增加模板替代运行证据。当前仍遵守用户先完成架构、暂不编码的要求。
