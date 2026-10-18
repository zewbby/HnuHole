# B11 / B08 分阶段接口契约

2026-10-18；分支 `codex/feat/report-moderation`。[PR #18](https://github.com/zewbby/HnuHole/pull/18) 的阶段1产品候选
`aab9a647d9c8310e344bbc767abb5cbdc1045f73` 已提交、推送，agent 安全复核无阻断，状态 PHASE1_SCOPED_PASS。
基于 main `986477b`，当前无未提交产品源码；宿主、真实 SQL／HTTPS／浏览器链和产品候选CI均通过，交付head回执见PR。
最终证据由[验收报告](report-moderation-validation-report.md)及[机器记录](report-moderation-verification.json)固定；未合并、未部署、未发布，B08／B11仍为 PARTIAL，评论举报及真实失败 provider 等未实现范围不据此关闭。

阶段一独立 PR 交付帖子举报、审核、申诉和 App 内通知。评论发布/图片/失败任务仍由
`codex/feat/comments-replies` 拥有；阶段一不依赖评论表。评论合入 main 后另作类型适配与集成回归。

## 通知事件与任务

通知由权威业务事务创建，不提供客户端伪造服务端通知的写入 API。
事件有唯一 `eventId`；每位接收人的记录有独立 `id`，同事件重复投递不新建记录。
`source` 为 `SERVER` 或 `LOCAL_TASK`。本机明确失败仅可由评论任务 provider 提供
`LOCAL_TASK`，不声称服务端已受理。未知状态不产生失败通知。

`scope=ACCOUNT` 的通知归账号所有，跨本人身份共享已读；`scope=IDENTITY` 必须绑定原身份。
列表返回当前身份和账号级通知的单一倒序时间流，无分类页。省略 `identityId` 仅返回账号级。
打开列表不标已读；打开详情后显式提交该条 read。阅读不解决评论失败任务。
路由白名单为 `REPORT`、`SANCTION`、`APPEAL`、`COMMENT_FAILURE`，只传资源标识，不接收 URL。
服务端按当前账号复核资源所有权；客户端跳转前切至通知原身份，并保持账号/会话代次围栏。

评论 provider 最小职责：列出本账号本身份明确失败任务；按稳定任务标识读取详情、重试、放弃、标已读；
成功/放弃/原身份删除时撤去入口。通知层不存第二份发送正文、不重新绑定身份、不自行裁决未知。
评论目标适配须在同一最终 Gate 事务检查其类型、归属、帖子及评论生命周期，不能只凭资源 ID 存在放行。
当前已有 `CommentFailureProvider` 类型与 `COMMENT_FAILURE` 路由保留，尚未装配真实评论 provider；
阶段1服务端通知只创建举报进度／结果、处罚和申诉结果，不写入占位评论通知。

## 公开接口

- `PUT /api/v1/reports/{requestId}`：`postId, identityId?, reason, description, images, retryToken?`。
  原随机 UUID 绑定完整意图；同键同材料幂等，不同材料 409。`GET` 同路径核对，
  返回 `{state: SUBMITTED, report}` 或 `{state: NOT_SUBMITTED, retryToken}`；未知先核对，不能新键重发。
  `NOT_SUBMITTED` 在权威事务封住此前迟到尝试；显式重试保留原 requestId、材料及最新 retryToken，旧令牌不能重新受理。
- `GET /api/v1/system-notifications?identityId=&before=&limit=`：`{items,nextBefore}`。
  `GET /{id}` 读单条，`POST /{id}/read` 标单条已读；都需本人权限。
- `GET /api/v1/sanctions/{id}` 返回本人处罚摘要、起止/撤销时间、申诉次数及活动申诉 ID。
- `PUT /api/v1/sanctions/{id}/appeals/{requestId}` 新一轮申诉；
  `GET /api/v1/sanctions/{id}/appeal-requests/{requestId}` 核对原键。
- `GET /api/v1/appeals/{id}` 读本人申诉；
  `PUT /api/v1/appeals/{id}/materials/{requestId}` 独立追加；
  `GET /api/v1/appeals/{id}/material-requests/{requestId}` 核对原追加。
- `GET /api/v1/appeals/{id}/materials?cursor=` 逐批读取本人申诉材料。
  首次申诉和追加同样支持原键核对／retryToken 围栏；核对不是另起一轮，不消耗额外申诉次数。

管理接口统一位于 `/api/v1/moderation`：`me`，案件列表／详情／`claim`／`decision`，
待复核申诉列表／详情／`decision`，六位编号账号列表／查询、处罚 `revoke`、案件审计和管理员 `roles/{number}`。
案件／待复核申诉列表使用 `before,limit`（最多50）及 `(createdAt,id)` 游标；账号列表初始可省略 number，按六位编号游标分页，定点查询才展开该账号处罚。
所有管理动作绑定 `commandId`，案件／申诉处理还核对 `expectedVersion`；结果未知保留原命令与负载，服务端幂等回执和最终授权事务裁决竞争。

案件详情 `reports`、申诉详情 `materials` 只返回首份／首批，并分别附可选 `nextReportsCursor`／`nextMaterialsCursor`。
后续接口为 `GET /api/v1/moderation/cases/{id}/reports?cursor=` 与
`GET /api/v1/moderation/appeals/{id}/materials?cursor=`，以及上面的本人申诉材料接口。
返回 `{items:[material],nextCursor:null|string}`，一次至多一组，按 `(createdAt,reportId/requestId)` 升序追加并保留旧组。
每份举报材料独立返回 `reason`；申诉写入不接受此字段。cursor 原样传回，不能以其他案件的 cursor 获取其材料。
有后续 cursor 时界面必须提示材料未完整加载，切账号、会话变化和切详情后的迟到页不得串入新详情。

通知 DTO：`id,eventId,source,scope,identityId?,kind,state,title,body,createdAt,readAt?,route`；
`route={name,resourceId}`。举报路由 resourceId 为原 requestId。
成功响应沿用 `Session-Expires-At`、`X-Request-ID`、`Cache-Control: no-store`；
认证/冻结边界沿用 401/503。所有接口固定 HTTPS origin、拒绝重定向和重复 JSON 字段。
被封禁用户可用现有私有用户名密码取得仅本人处理通知／处罚／申诉可用的短期受限访问能力；
该能力不取消注销、不接替普通会话、不访问社区或管理接口。稳定匿名 `moderationSubject` 只用于本机待核对材料归属，不是内部账号 ID 或授权凭据。

## 本轮实现决定

六类原因编码为 `ADVERTISING,HARASSMENT,PRIVACY,FRAUD,ILLEGAL,OTHER`。
公开举报说明采用至多200字、最多6图；首次申诉500字/6图，追加每次500字/3图。
图片只接受验证通过的 PNG/JPEG/GIF/WebP 原字节，单图2MiB、每批8MiB；JSON请求最多12MiB。
本次以相同 `postId + snapshotDigest` 归并同事实，不按原因拆案；每份举报保留自己的类别，
不因多人／多原因／多人同时处理重复计违规或加罚，快照不因后续编辑替换。
无身份的浏览账号可举报，通知用账号范围，不为举报创建发言身份。
复用既有私有六位平台号，随机无重复、保留前导零、容量100万；不新增第二份账号映射，不将其作为公开身份或登录凭据。
审核员可下架、重置本案身份违规资料及禁言1／3／7／30天；封禁1／3／7／30天或永久、解除封禁及角色管理仅管理员，角色变更不能撤掉最后管理员。
账号级处罚独立计时，有效截止取最大值；撤销其中一项保留其他有效处罚。所有处理留审计且不下发邮箱、内部账号／资格映射、其他面具及举报人身份。
同一处罚累计最多三轮申诉、同时一轮待复核；首次500字／6图，每次追加500字／3图且不占新一轮。
原处理人不能独自复核；处罚到期仍继续申诉。通过时修正对应违规记录并按条件恢复仅因本次误判下架的内容，作者已删除或另有有效下架原因则不恢复。
材料分页保证单组解码图片总量最多8MiB；原帖证据快照独立沿用已限定的最多9张、每张10MiB，不在列表或每份举报材料重复携带。
证据和审计期限尚无确认政策：本轮无自动销毁任务，不将此视为永久留存批准；生产启用前另定保留/清理政策。

## 阶段状态

契约可供评论任务先行对接；评论举报、真实评论失败 provider、完整互动收件箱、私信证据及系统推送未集成。
基础迁移0015基于实际 main `986477b`（既有迁移连续至0014），只引用已存在的账号、身份和帖子表。
评论暂定0016；阶段2所需新迁移在评论合入后按实时 main 递增，不覆盖已合入文件、不乱序执行。
当前实现／验证状态见[任务详情](../branches/feat-report-moderation.md)与[模块交接](module-acceptance-handoff.md)；最终 SHA、真实 SQL／HTTPS／浏览器和平台结果须由对应执行证据补齐，B08／B11不计完整 PASS。
