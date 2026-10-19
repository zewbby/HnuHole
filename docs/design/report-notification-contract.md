# B11 / B08 举报、审核与最小系统通知契约

2026-10-19。帖子治理基础 [PR #18](https://github.com/zewbby/HnuHole/pull/18) 和真实评论 [PR #19](https://github.com/zewbby/HnuHole/pull/19) 已合入 main；阶段1的[报告](report-moderation-validation-report.md)与[机器证据](report-moderation-verification.json)保留原版本范围。
当前 `codex/feat/comment-report-moderation` 在实际完整评论主线接通评论举报闭环，验证与合并状态见[任务详情](../branches/feat-comment-report-moderation.md)、[新增报告](comment-report-validation-20261019.md)。未部署／发布，完整 B08／B11 仍为 PARTIAL。
评论发布、图片、失败任务及原任务重试／放弃仍由评论模块拥有；当前直接复用 #19 成果，不开发第二份 provider 或发送状态机。

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
真实服务端失败已由 #19 的 `0017_comment_business.sql` 在权威 FAILED 事务写入统一通知：
`source=SERVER`、`scope=IDENTITY`、`identityId=ownerIdentityId`、`kind=COMMENT_FAILURE`、
`eventId=comment-failure:{taskId}`、`route={name:COMMENT_FAILURE,resourceId:taskId}`。
任务重试进入 ACCEPTED、成功／放弃／原身份删除时沿已有触发器移除失效入口；后续失败产生当前权威入口，读取通知不能解锁任务。
App 详情复用 `CommentFailureView` 和 `CommentRuntime`，由评论拥有者接口读取原 `taskId`、版本、正文、图片及允许动作；
重试／放弃只调用评论核心，保留原身份／目标并核对原命令，通知模块不发 CREATE、不改投、不清 journal、不推断 UNKNOWN 为失败。
已有 `CommentFailureProvider`／`LOCAL_TASK` 类型仅是扩展边界，不能把它当成还需另造真实服务端任务的缺项。

## 公开接口

- `PUT /api/v1/reports/{requestId}`：`postId, commentId?, identityId?, reason, description, images, retryToken?`。
  原随机 UUID 绑定完整意图；同键同材料幂等，不同材料 409。`GET` 同路径核对，
  返回 `{state: SUBMITTED, report}` 或 `{state: NOT_SUBMITTED, retryToken}`；未知先核对，不能新键重发。
  `NOT_SUBMITTED` 在权威事务封住此前迟到尝试；显式重试保留原 requestId、材料及最新 retryToken，旧令牌不能重新受理。
  省略 `commentId` 为原帖子举报；传入时必须是该 `postId` 下真实已发布主评论或回复，不能用 taskId 代替。
  `identityId` 是举报者本人选用的通知身份，独立于评论作者身份；不得接收客户端声称的作者账号／身份。
  本人举报回执、案件与本人处罚摘要增加可选 `commentId`，旧帖子省略，不改变其原意图指纹。
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
评论摘要在同一命名空间加入 `COMMENT + commentId`，同文不同对象不会合案；评论文字及单图原字节从最终授权事务读取，父帖归属与公开状态一并核验。
下架回复只影响自己，下架主评论阻断整楼；处置取评论实际作者，父帖仍独立。作者删除、父帖删除及其他有效下架原因不能被申诉撤销覆盖。
举报通知仍以原 `requestId` 路由核对本人举报，再以权威回执 `postId/commentId` 调用现有评论定位；不在通知上复制内容或携带任意 URL。
无身份的浏览账号可举报，通知用账号范围，不为举报创建发言身份。
复用既有私有六位平台号，随机无重复、保留前导零、容量100万；不新增第二份账号映射，不将其作为公开身份或登录凭据。
审核员可下架、重置本案身份违规资料及禁言1／3／7／30天；封禁1／3／7／30天或永久、解除封禁及角色管理仅管理员，角色变更不能撤掉最后管理员。
账号级处罚独立计时，有效截止取最大值；撤销其中一项保留其他有效处罚。所有处理留审计且不下发邮箱、内部账号／资格映射、其他面具及举报人身份。
同一处罚累计最多三轮申诉、同时一轮待复核；首次500字／6图，每次追加500字／3图且不占新一轮。
原处理人不能独自复核；处罚到期仍继续申诉。通过时修正对应违规记录并按条件恢复仅因本次误判下架的内容，作者已删除或另有有效下架原因则不恢复。
材料分页保证单组解码图片总量最多8MiB；原帖证据快照独立沿用已限定的最多9张、每张10MiB，不在列表或每份举报材料重复携带。
证据和审计期限尚无确认政策：本轮无自动销毁任务，不将此视为永久留存批准；生产启用前另定保留/清理政策。

## 阶段状态

基础迁移0015保持只依赖原账号、身份和帖子表；真实评论0016／0017已经合入。
本任务新增0018，在实际评论表上增加案件目标及下架投影、删除终结和发布保护；前向升级，不覆盖既有迁移，不允许跳号，Down拒绝。
评论举报已完成本任务范围接通，真实失败通知直接沿用 #19；完整互动收件箱、私信证据及系统推送仍不在范围。
当前实现／验证及最终合并状态见[本任务详情](../branches/feat-comment-report-moderation.md)、[新增证据](comment-report-verification-20261019.json)与[模块交接](module-acceptance-handoff.md)，B08／B11不计全平台／生产完整 PASS。
