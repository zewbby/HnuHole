# 私信 P3 后端交接

2026-10-23；分支 feat/direct-message-governance-backend，基线 d864d03062ddbbd4af72e1b83d63dac73dbcf15c。仅分支实现，未合并、未发布。整合方维护 B08/B09、HANDOFF、progress 和主任务验收台账。

## 实现与契约

- 正式迁移 0024：账号范围双向阻止新发送；每个用户主动选中的身份对单独投影，解除只移除对应选择。不会枚举对方其他身份；账号限制仍可能被行为推断。统一操作回执，已受理待投内容保留。
- 三条新路径及完整请求／响应在 packages/openapi/direct-message-governance.yaml。普通回执／待投新增 evidenceVersion，目录新增 ownBlockId。Report、Case、Sanction 的私信目标通过 conversationId 表示，postId 为空；Appeal 无新字段。
- 私信举报连续首尾区间最多 200 条。预览由客户端固定，显式 authorized；每个实际序号必须提供认证正文／图片或明确缺口。无法得知本地缺口的 ID／类型时允许空 messageId＋UNKNOWN，但服务端仍按本人会话和实际序号定位。原始聊天材料与附图合计 32 MiB，HTTP JSON 48 MiB；不把超预算的现存中间图片伪装成缺口。
- 新文字只保存 HMAC 认证摘要，ACK 清除普通正文；图片校验既有已认证清单和原始字节 SHA-256。迁移前没有认证摘要的文字返回 EVIDENCE_UNVERIFIABLE，必须在预览中明确作为缺口，不能信任客户端重写正文。HMAC 使用既有 requestKey，恢复／密钥轮换须保持对应验证密钥，不能丢失后声称旧材料已认证。
- GET NOT_SUBMITTED 使用既有 REPORT attempt fence；晚到旧 PUT 被封口，显式重试使用 retryToken。相同 request UUID／固定材料不重复建案。
- 治理证据独立保存；审核仅可按案件读已授权范围，记录 READ_DM_EVIDENCE 审计。后台按结构化 dmRecords 显示序号／方向，防止正文伪造归属；预览后撤回保留授权原文并加服务端撤回标记。普通聊天接口不能读治理证据。
- 复用既有系统通知、禁言／封禁和独立申诉链。私信案件仅允许 DISMISS/MUTE/BAN，不宣称远程下架用户本地历史，也不处置源帖。身份删除／正式注销同最终授权事务清理本人待收正文、媒体与备注，保留仍有效对方已受理待投和独立治理证据。
- 服务配置 directMessages 保持显式默认关闭。解除 development-only 限制后仍要求 migration 0024、moderation 和私有图片验证启用。未部署或改变共享开发环境。

## 已执行检查

最后产品代码的 SQL/race 自有私有 socket 环境：/tmp/hnuhole-dm-p2.Gu5e3p，运行结束已停止。

```
PATH=/usr/lib/go-1.22/bin:/usr/lib/postgresql/16/bin:/usr/local/bin:/usr/sbin:/usr/bin:/bin
POST_MEDIA_PYTHON=/home/hnuhole/community-pr13-main-20261018-tools/python/bin/python
COMMENT_TEXT_GOOSE=/mnt/e/Hnuhole-env/linux/bin/goose
DM_CHAT_TEST_PATTERN='^(TestDMGovernance|TestDMGoose|TestDMFirstContact|TestDMChatMediaLifecycle|TestModerationAppealIndependentReversal|TestModerationConcurrentDecision)'
sh services/api/authlab/run-dm-chat-isolated.sh
```

PASS：9 个 authprivacy 顶层测试＋1 个真实 HTTPS 测试；包含 0024 fresh／22→23→24 升级与拒绝破坏性 Down、受限运行角色、双向阻止竞态、跨身份选择投影、ACK 后真实性、图片和缺口、固定快照／撤回、举报 fence、处罚通知、身份删除、正式注销以及受影响首发／媒体／治理申诉检查。

PASS：5 份受影响完整 OpenAPI（direct-message-governance/chat/text、report-api、moderation-api）；后台 Node 13 项；go build -mod=readonly ./cmd/authdev 与 go vet -mod=readonly ./internal/authprivacy ./internal/authprivacyhttp ./internal/authprivacyruntime；git diff --check。

早期失败如实保留：一次 fixture PATH 缺 /usr/sbin 导致 runuser 不可用；身份测试仅有一个身份触发最后身份保护；grant fixture 未建 goose_db_version；治理 HTTP 错误误走普通 Post allowlist。均已修复，相关项实际重跑 PASS。未将无 DSN 编译检查计作 SQL 通过。

## 未验及运营边界

2026-10-23 最终整合 Gate CI 增量（head 73892f3，job 120190551179）：唯一失败是 verifier 关系清单漏列既有 0005/0006 的 v_auth.email_login_confirmations。该表仅保存 V 的确认／proof／重放状态；不含 C 账号、面具或会话字段。privacyRelations 仅枚举 public/c_auth/v_auth，因此不是 0024 的 c_dm.blocks 导致。补丁只增列该准确表名，保留完整关系精确匹配、禁止列及特权函数／跨库桥接检查。使用前述自有隔离 runner、DM_CHAT_TEST_PATTERN='^TestPrivacySchemaPartyBoundaryPostgres$'，真实 SQL／race 的 community 和 verifier 两子测试 PASS（3.93s）；未重跑已通过主体及完整预发布。此项是最终整合暴露的历史测试清单遗漏，不扩展邮箱登录产品功能。

2026-10-23 预发布审计增量（PR #52 head fc4f986）：rehearsal 在 environment.py:398 的共享权限审计失败。0024 的 grant-community 增加了即使 DM API 关闭也必需的清理权限，旧审计没有 c_dm 矩阵。修正只为 C runtime 放行既定五表读取、四表明确清理列 UPDATE 与 blocks DELETE；未增加运行角色授权。新增 test_role_audit_postgres.py 使用两个新建自有 C/V PostgreSQL 集群、实际 Goose 最新迁移、正式 grants 和原 Lab.audit：修前复现 FAIL，修后 PASS；8 个发送/不可变列/整表更新/越权角色负例全部因 noncontract table privilege 被拒绝。CI 使用 PRERELEASE_AUDIT_SQL_TEST=1 启用该回归。仅验证受影响审计，完整远端 rehearsal 待新提交 CI，不将本地增量等同整套预发布通过。

2026-10-23 真实 TLS 联调增量：合成账号初次 PUT commands 返回 SENT、PUT block 返回 APPLIED；第三步 GET blocks 的 createdAt 实际返回 +08:00，触发 Flutter 严格 UTC 解码失败。DMBlocks 现将数据库时间显式转为 UTC；TestDMGovernanceHTTPSPostgres 强制 time.Local=UTC+08 并断言 JSON 时间以 Z 结束。使用同一自有隔离 runner、DM_CHAT_TEST_PATTERN='^TestDMGovernanceHTTPSPostgres$' 实际 SQL／HTTPS／race PASS（4.33s）。未重跑未改变的全套检查。完整 Flutter 联调仍由整合方执行。

- Flutter 真实 TLS 合同联调交整合方；TestDMChatDevicePostgres 已加 WithModeration，可用 DM_CHAT_DEVICE_FIXTURE 生成自有合成账号 fixture。此后端任务不连接手机。
- 远端 CI、完整最终整合、生产渠道推送、Android／iOS 真机与正式发布未执行。
- 证据／审计保留期限、备份及密钥轮换需运营定案；没有擅自设置自动过期删除。举报材料真实性不能证明用户未谎报本地缺口，审核始终可见缺口声明。
