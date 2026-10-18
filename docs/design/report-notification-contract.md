# B11 / B08 分阶段接口契约

2026-10-18；分支 `codex/feat/report-moderation`。本页先交付对接契约，不表示功能已验收。

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

## 公开接口

- `PUT /api/v1/reports/{requestId}`：`postId, identityId?, reason, description, images`。
  原随机 UUID 绑定完整意图；同键同材料幂等，不同材料 409。`GET` 同路径核对，
  返回 `{state: SUBMITTED, report}` 或 `{state: NOT_SUBMITTED}`；未知先核对，不能新键重发。
- `GET /api/v1/system-notifications?identityId=&before=&limit=`：`{items,nextBefore}`。
  `GET /{id}` 读单条，`POST /{id}/read` 标单条已读；都需本人权限。
- `GET /api/v1/sanctions/{id}` 返回本人处罚摘要、起止/撤销时间、申诉次数及活动申诉 ID。
- `PUT /api/v1/sanctions/{id}/appeals/{requestId}` 新一轮申诉；
  `GET /api/v1/sanctions/{id}/appeal-requests/{requestId}` 核对原键。
- `GET /api/v1/appeals/{id}` 读本人申诉；
  `PUT /api/v1/appeals/{id}/materials/{requestId}` 独立追加；
  `GET /api/v1/appeals/{id}/material-requests/{requestId}` 核对原追加。

通知 DTO：`id,eventId,source,scope,identityId?,kind,state,title,body,createdAt,readAt?,route`；
`route={name,resourceId}`。举报路由 resourceId 为原 requestId。
成功响应沿用 `Session-Expires-At`、`X-Request-ID`、`Cache-Control: no-store`；
认证/冻结边界沿用 401/503。所有接口固定 HTTPS origin、拒绝重定向和重复 JSON 字段。

## 本轮实现决定

六类原因编码为 `ADVERTISING,HARASSMENT,PRIVACY,FRAUD,ILLEGAL,OTHER`。
公开举报说明采用至多200字、最多6图；首次申诉500字/6图，追加每次500字/3图。
图片只接受验证通过的 PNG/JPEG/GIF/WebP 原字节，单图2MiB、每批8MiB；JSON请求最多12MiB。
本次以目标、原因及公开内容快照摘要归并同事实，材料不因后续编辑替换。
无身份的浏览账号可举报，通知用账号范围，不为举报创建发言身份。
六位平台号随机无重复分配，保留前导零、容量100万，避免新增注册顺序信号；不是公开身份或登录凭据。
证据和审计期限尚无确认政策：本轮无自动销毁任务，不将此视为永久留存批准；生产启用前另定保留/清理政策。

## 阶段状态

契约可供评论任务先行对接；评论举报、真实评论失败 provider、完整互动收件箱、私信证据及系统推送未集成。
0015只引用已存在的账号、身份和帖子表；编号以合入前实时 main 为准。
