# 认证隐私反馈整改交付报告

日期：2026-09-28。核对对象：用户提出的“独立思考并 debate”反馈，以及随后授权的实施前规格化工作。核对基线：远程 `codex/auth-privacy-handoff` 的 `2c47745631105b34f9776a0bb659fd9ca671d4e2`。

## 1. 完成结论

**反馈引出的文档与协议整改、恢复策略、数据库／API 设计，以及内部 AI 威胁模型评审已经完成。** 这些成果已推送到对应远程分支。认证实现、真实运行验证和生产安全验收尚未完成；本报告不授予实施或上线许可。

若“任务完成”指收干净反馈中的规格缺口，答案是已完成；若指完成其列出的所有生产前门槛，答案是尚未完成。V/C 实际运营分权不能通过写文档或 AI 评审来完成。

## 2. 逐项反馈与独立判断

| 用户反馈 | 判断与最终处理 | 证据及完成范围 |
| --- | --- | --- |
| 清理旧的邮箱唯一登录、稳定匿名凭证恢复旧号规则 | 采纳。当前交接、账号模块和进度采用新主链；历史 ADR 和讨论保留追溯，但明确失效，不能作为实施依据。 | [HANDOFF](HANDOFF.md)、[账号模块](modules/accounts.md)、[进度](progress.md)、[历史 ADR 0005](../adr/0005-privacy-preserving-email-authentication.md)。规格清理完成。 |
| 用 bootstrap key 阻止恶意 V 抢注册 | 采纳持钥证明，但原建议不足：恶意签名者仍可给同一 slot 换公钥重签。现方案由客户端公钥散列导出 slot，C 重算该等式，并验客户端对真实 C 挑战的签名；证明还绑定开户意图与完整资格票据。 | [注册／退役／释放协议](auth-privacy-registration-protocol.md)。协议完成，真实服务未实现。 |
| 注册必须建立独立恢复方式 | 采纳并收敛为：开户前必须保存并完整重输确认 128 位恢复码，开户后推荐可选 Passkey。没有采用“Passkey 或恢复码任选其一”，避免仅依赖平台同步；Passkey 只用于恢复及凭据管理，保留用户名密码日常登录。 | [恢复策略](auth-privacy-recovery-decision.md)。规格完成，保存效果和换机体验未做用户测试。 |
| Argon2id 之外还要控制密码攻击面 | 采纳。规定密码阻止名单、分维度限流与异常检测、普通登录统一错误及等价计算路径、恢复码限流、凭据版本与旧会话撤销、KDF 并发上限。成本和限流阈值待真实机器测量。 | [恢复策略第 5 节](auth-privacy-recovery-decision.md)、[数据/API 契约](auth-privacy-data-api-contract.md)、[威胁模型](auth-privacy-threat-model.md)。设计完成，防御效果未实测。 |
| V1 先用 Argon2id，OPAQUE 后续评估 | 采纳。OPAQUE 保留为后续方向；本次没有引入新的自创密码学原语。 | [架构决策](auth-privacy-architecture-decision.md)。取舍完成。 |
| V/C 必须实际独立 | 采纳为隐私承诺的部署前提，不能仅靠两个数据库或不同服务名证明。已记录运营、权限、客户端发布、备份和日志的核查要求。 | [独立评审输入包第 5 节](auth-privacy-security-review-package.md)。要求和模板完成，实际运营证据未完成。 |

### 保留的安全边界

校邮 OTP 只证明新注册资格，不查询或恢复旧号。公钥散列绑定防的是恶意 V 替换用户同一槽位的密钥；它不能阻止 V 自签另一套密钥和槽位、伪造新资格或拒绝服务。“同一精确邮箱同时至多一个有效账号”依赖 V 诚实执行配额。

V 保存邮箱到槽位，C 保存槽位到账号。双方串通或两库、备份同时泄漏，仍可按槽位关联邮箱和账号。C 诚实及客户端可信也是前提，不能宣传绝对匿名。

密码、恢复码及全部 Passkey 都失去后仍无法按邮箱找回；旧号未关闭时，同邮箱配额也继续占用。强制确认恢复码是在降低遗失概率，没有消除永久丢号风险。真实用户走查尚未完成。

## 3. Phase A–E 状态

| 阶段 | 当前状态 | 交付物 |
| --- | --- | --- |
| A：清理旧认证规则 | 完成当前规则清理；历史材料标记失效 | 交接、账号模块、进度、ADR 状态和设计入口 |
| B：slot、bootstrap、release 精确协议 | 规格完成 | 固定编码、限时资格、持钥证明、退役／释放、幂等、重放和故障规则；独立恢复策略 |
| C：数据库与 API 设计 | 设计及静态契约检查完成 | [逻辑契约](auth-privacy-data-api-contract.md)、[迁移设计](auth-privacy-database-migration-design.md)、[V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)、[C OpenAPI](../../packages/openapi/community-auth-api.yaml) |
| D：Threat-model review | 内部威胁建模及新上下文 subagent 规格评审完成；人类独立审计未完成 | [威胁模型](auth-privacy-threat-model.md)、[AI 交叉评审记录](auth-privacy-ai-cross-review.md)、[送审输入包](auth-privacy-security-review-package.md) |
| E：Go 实现 | 未开始，符合暂不编码要求 | 无本任务新增认证实现 |

内部 AI 初审发现一项中等规格缺口：C 的退役收据 outbox 没有获取 V 持久处理 ACK 的通道。已补齐退役收据入口、双方持久确认、单调终态、清理和灾备规则。修正后复核结论为 **`APPROVE WITH NOTES`，限于规格范围**。这是已经执行的 AI 交叉评审；不是人类第三方审计。

用户已决定本轮不使用 Claude Code。Claude 未产生模型评审结果，也不作为本轮交付前提。

## 4. 验证证据及其限制

- 三份 OpenAPI 已通过结构校验、重复键检查和本地引用检查；V 为 6 个操作、C 为 22 个操作、通道为 1 个操作。[本轮静态记录](../../packages/auth-protocol-vectors/retirement-ack-static-verification.json)还记录新增请求和 ACK 的正负形状检查，合成编码通过不代表签名验证通过。
- 先前签名和编码静态向量的实际运行范围见[原静态复验记录](../../packages/auth-protocol-vectors/static-verification-report.json)。本轮补 ACK 没有更改固定向量，也没有重跑签名库测试。
- 修正规格已固定到提交 `05dc4a4b88797f5532829c1f2953484f7ac86c90`，21 份源材料、字节数、摘要及 Git blob ID 见[快照清单](auth-privacy-review-snapshot.json)。报告不会改动该已锁定评审输入。
- 本报告核对时，远程分支为上述 `2c47745`；工作区清洁、`git diff --check` 成功，OpenAPI 和固定向量的当前摘要与静态记录一致。
- 未运行真实认证服务、实际 SQL、并发故障注入、移动端 WebAuthn、限流负载、灾备或用户走查。不能将规格通过表述为实现或生产通过。

## 5. 未完成的现实工作与下一步

现阶段不再需要继续增加规格模板来证明安全。剩余工作需要真实运行与运营证据：

1. **先进入隔离实现验证阶段（需获得实施授权）。** 最小范围是实际 PostgreSQL 约束、注册／退役竞争及提交后签名与持久 ACK outbox；运行送审表中的丢包、崩溃、重试和回滚交错，通过后再展开登录、恢复、会话和注销实现。
2. **同步确定部署控制关系。** 当前只确认校邮可用，不能据此认定验证服务 V 已建立；C 正式后台未建，V/C 运营主体和共享管理员权限未确认。生产前必须核实分权、客户端发布、日志和备份访问。
3. **以实现证据完成验收。** 测量密码成本和在线攻击防护，走查恢复体验，核验移动端 Passkey，补充实际安全评审及生产放行。AI 可以继续审查，但不能替代运营事实或未执行的测试。

详细未验收项以[送审包 G1–G6](auth-privacy-security-review-package.md)为准。这些是下一阶段工作，不是已经完成的规格整改结论。
