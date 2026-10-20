# 新版帖子列表后端接线

> **2026-10-19 合并事实：**PR #27 已以 `f1752e1` 合入 main；下文“本分支／未合并”为原后端交接快照。FEED-UI-01 从该最新主线单独完成接线，见[前端任务](../branches/feat-feed-ui.md)。未部署。

工作项 `FEED-BACKEND-01`，分支 `codex/feat/feed-backend`，基线 main `fc2348f`。本页描述本分支新增能力，未合并、未部署。精确 JSON、错误与 header 以 [feed-api.yaml](../../packages/openapi/feed-api.yaml) 为准；实际验证见[分支交接](../branches/feat-feed-backend.md)。

## 接口

全部沿用原 C HTTPS origin、当前账号 Bearer、会话恢复和最终 C Safety Gate。请求不接受账号、身份、客户端时间或访客选择器。成功响应继续先处理并持久保存 `Session-Expires-At`，再发布业务状态；`Server-Time` 是最终事务可信时间。`Cache-Control: no-store`、`X-Request-ID` 和原错误包装不变。

| 请求 | 用途 | 成功响应 |
| --- | --- | --- |
| `GET /api/v1/feed?limit=20` | 跨通道时间倒序列表 | `{items:[FeedPost],nextCursor:string|null}` |
| `GET /api/v1/feed?channelId=<目录UUID>&limit=20` | 单通道新列表，仍执行屏蔽 | 同上 |
| `GET /api/v1/feed?...&cursor=<原nextCursor>` | 同账号、筛选和 limit 的下一页 | 同上 |
| `GET /api/v1/me/feed-preferences` | 当前账号屏蔽集合，默认空数组 | `{blockedChannelIds:[UUID]}` |
| `PUT /api/v1/me/feed-preferences` | 原子替换完整屏蔽集合 | 返回规范排序的完整集合 |
| `POST /api/v1/posts/<postId>/views` | 正文实际打开后登记浏览 | `{postId,viewCount}` |

新接口均不接受 `Idempotency-Key`。偏好 PUT body 为 `{"blockedChannelIds":["目录UUID"]}`，`[]` 表示重置；必须是完整、唯一的零至七个目录 UUID，禁止 null。重复同一集合为幂等操作，不使游标失效；不同写入按账号串行，最后提交的完整集合为准。未知通道返回 `404/POST_CHANNEL_UNAVAILABLE`。登记浏览 POST 无 body／query，不产生发帖任务或命令回执。

FeedPost 示例：

```json
{
  "postId": "22222222-2222-4222-8222-222222222222",
  "channelId": "5f6f4f88-8f64-4bb2-9d34-000000000001",
  "title": "帖子标题",
  "body": "帖子正文",
  "author": {"state": "ACTIVE", "nickname": "展示昵称", "avatar": "default-v1"},
  "publishedAt": "2026-10-19T08:00:00Z",
  "viewCount": 12
}
```

有图增加 `imageCount:1..9`，无图省略；manifest／受保护字节继续走原图片 API，不返回公开媒体 URL。删除身份或关闭账号继续使用原独立 shortCode／inactive 投影。公开数据不包含账号／身份 ID、访客名单、是否已浏览、内部序号、偏好版本或本人管理权限；本人权能仍走原私有接口。原 FEED-BACKEND-01 未扩展点赞／收藏；后续接口见下方 FEED-INTERACTIONS-01，私信不在范围。

旧详情、通道列表、我的帖子及目录接口的响应字段和行为保持原样，旧 Flutter 严格 DTO 可继续解析。真实浏览量仅通过新 FeedPost 和浏览登记响应提供。

## 前端接入

1. 合并后从新 main 单独接线，不把旧 UI 工作区整包覆盖到本分支。目录继续来自 `GET /api/v1/channels`，筛选和屏蔽使用服务端 UUID。
2. 新列表进入时先读取当前账号偏好，再请求 `/feed`。UI 的“推荐”此阶段仅为跨通道时间倒序，不表示已有推荐／热度算法。选中通道使用相同接口的 `channelId`，不能改走旧接口绕过屏蔽。
3. 独立解析 FeedPost，将 `viewCount` 映射为只读数值，K/M 格式放在展示层；未知值可显示“—”，不沿用 fixture 计数。正文及图片数量可直接驱动列表，图片读取复用原保护链。
4. 原样回传 `nextCursor`，分页中不改 `channelId` 或 `limit`；`null` 才是末页。切通道、换账号、刷新或修改屏蔽后清旧游标，从首屏重载。`400/CURSOR_INVALID` 需要刷新，不能当成末页或拼接其他筛选。
5. 开关开启即 UUID 加入 `blockedChannelIds`；每次 PUT 完整集合，前端串行写入并隔离迟到结果。未知结果先 GET 核对，失败按原错误流程恢复交互，不把本地开关当作已保存。左侧仍允许选已屏蔽通道，此时返回空列表，不暗中解除屏蔽。
6. 只有进入并显示真实正文后调用 `/posts/<id>/views`；列表曝光、build、预加载、点赞、切身份及图片查看不登记。成功后以返回总量更新当前账号上下文中该帖的数字；同日重开／网络重试由服务端去重。旧详情 GET 不登记。
7. 延续原 401、`session_replaced` 和 503 处理。切账号／退出清理本列表的内存偏好、游标和请求归属，丢弃迟到结果；503 保留原会话。不得把其他账号的偏好或结果发布到当前界面。

屏蔽只影响新 `/feed`，包括其单通道筛选；不扩展目录、正文深链、我的帖子、搜索、标签、通知或私信。全部屏蔽是合法 `items:[]/nextCursor:null`，前端给出空态和调整入口；服务失败仍是错误态。

## 计数与分页

- HEAT-07 按最终 Gate 可信时间的上海自然日（UTC+08:00，00:00）去重，唯一键是账号＋帖子＋日期。跨身份、会话、设备、并发及重试不重复；作者账号始终排除。
- 去重记录和总量 UPSERT 同属原最终授权事务。未发布、已删除、审核隐藏或原授权不可访问的帖子返回 `404/POST_NOT_FOUND`，不登记。
- 旧帖从零开始，不推测历史浏览；总量不加入热度公式，删除或注销不倒扣已累计贡献。
- 去重键只存在 C 私有表；该账号下次登记时清早于当日的键，正式注销同事务清全部键和偏好。总量不含访客关联；无浏览历史／访客查询 API。
- 排序是 `publishedAt DESC`、私有唯一 publication ordinal DESC。游标加密绑定账号、新列表 scope、通道、limit、屏蔽 revision、首屏 publication ceiling 和最后位置，有效期三十分钟。
- 首屏发布序号上界阻止后续新发布挤入；删除／下架按当前可见性排除。屏蔽在 SQL `LIMIT limit+1` 之前过滤，不占页容量。集合改变使旧游标失效，改回原集合也需刷新；同集合重放不增加 revision。
- 游标并非静态可见性快照；下架／删除仍即时排除，恢复的旧帖若位于游标之前，需要刷新首屏才能看到。

## 点赞、收藏与评论数接线

2026-10-20，`FEED-INTERACTIONS-01`／`feat/feed-interactions` 新增，合并状态见[任务](../branches/feat-feed-interactions.md)。不向严格的 FeedPost、旧详情／通道／本人帖子 DTO 增加字段；现有客户端可继续读取，新增互动另行接线，本次不修改 Flutter UI。

| 请求 | body | 成功响应 |
| --- | --- | --- |
| `POST /api/v1/feed/interactions` | `{"postIds":["帖子UUID"]}`，1至50个唯一UUID | `{"items":[PostInteractions]}`，保持请求顺序 |
| `GET /api/v1/posts/<id>/interactions` | 无 | `PostInteractions` |
| `PUT /api/v1/posts/<id>/like` | `{"liked":true}` 或 false | 当前已提交 `PostInteractions` |
| `PUT /api/v1/posts/<id>/favorite` | `{"favorited":true}` 或 false | 当前已提交 `PostInteractions` |

```json
{"postId":"22222222-2222-4222-8222-222222222222","likeCount":12,"favoriteCount":3,"commentCount":8,"likedByMe":true,"favoritedByMe":false}
```

- 全部要求当前账号 Bearer／最终 C Gate，无 query、Idempotency-Key、身份或账号选择器。读取不登记浏览；计数、本人标志与会话续期同一事务提交，成功 header／401／503沿原规则。
- 点赞及收藏均是账号级，不同身份／设备共用同一状态；不要求创建身份、不选择发言身份、不写 `post_identity_bindings`。允许自赞／自收藏，显示数量包含作者账号，不能直接作为排作者贡献的热度得分。仅本人获得 `likedByMe/favoritedByMe`，不公开点赞者／收藏者、账号ID、身份ID、是否本人作者或访客数据。
- 三个计数都是当前状态：赞／藏由账号事实行计算，取消或正式注销会减少；不是累计操作次数。删除身份不取消互动，账号正式关闭原事务清理两类私有记录。禁言不阻止互动；待注销 `PENDING_CLOSE`、已关闭或其他不符合原会话校验的账号都沿既有 `401` 拒绝读写，不新增只读例外。封禁、替换会话、冻结沿现有鉴权边界，不绕过 Gate。
- `commentCount` 直接共用评论 context／分页总数的查询，包含当前可见的已发布主评论及楼中楼。待发送、失败、删除、审核隐藏均不计；主评论删除／隐藏时其楼中楼也不计。不是独立讨论人数，不建立新聚合表或缓存。
- 批量查询只对当前可见帖子返回结果，任一项未发布／删除／下架即整个请求 `404/POST_NOT_FOUND`，不返回部分结果或失效ID列表。先刷新 `/feed` 并用新一页ID重试；网络／服务失败保持计数未知态，不伪造零。屏蔽继续只影响 `/feed` 的行选择，摘要与单帖详情同可见性，不因屏蔽禁止合法深链访问。
- 前端每页加载成功后批量取摘要，以 `postId` 合入当前账号页面模型，不修改严格 FeedPost 解析器。空页不发空数组。多个页面共享同帖的已提交结果；清账号、退出或刷新时丢弃旧请求结果，不能把 A 的旗标发布到 B。
- 点赞／收藏发送的是**期望状态**，不是 toggle。前端按账号＋帖子＋操作串行写入；未知结果暂停后续相反操作，先 GET 核对或重试相同 PUT，不能先取消再自动重放迟到的点赞。服务按最终提交顺序应用，不保证跨设备的客户端时间顺序。
- 可乐观更新按钮；明确失败回退，未知保持处理中。成功采用返回的完整计数／状态，不在响应基础上再次加一。后台刷新与写入也需本地请求版本围栏，防止先发的摘要晚到覆盖已提交的新状态。评论发布／删除成功后重新查询摘要，不本地猜楼中楼删除数量。
- 本轮只提供可见帖子互动，不实现“我的收藏”列表、已删除帖收藏占位的管理接口、点赞通知、热榜或私信。现有评论发布、点赞、删除、图片和举报接口不替换。

## 迁移与运行

新增 `0019_feed_backend.sql`，按正式顺序接在 `0001..0018` 后。仅新增三张私有表、时间索引和账号关闭清理触发器，不改原内容、绑定或回执。受控 owner 执行 Goose `up` 后重跑新版 `infra/postgres/grant-community.sql`；原来已启用图片、评论或治理时，按既有顺序重跑相应 `grant-post-images.sql`、`grant-comments.sql`、`grant-moderation.sql`，基线 grant 会重置 c_posts 权限。

原 feed 后端要求0019；本次互动二进制进一步要求完整 `0020_post_interactions.sql`。仅新增两张私有事实表、按帖计数索引和账号关闭清理 hook；无历史点赞／收藏推测回填。不迁移、改写已有帖子、评论、真实浏览或偏好。

升级按0001..0020后重跑新版 `grant-community.sql`，再恢复原已启用的图片／评论／治理 grant。互动表仅允许runtime SELECT／INSERT／DELETE，无UPDATE或DDL，recovery／business／V无新增读取权限。即使关闭帖子 HTTP，已安装0020的普通 C 启动仍核验互动主键、清理 hook 和所需权限；缺失即拒绝，全部表被擦除但版本已记0020也拒绝。旧pre0020普通C兼容，不将其当作新帖子服务可用。浏览及点赞／收藏登记均显式指定冲突键，约束丢失不能静默重复计数。保持原配置、密钥、Gate 锚点、会话和 C/V 边界；Down拒绝，故障前向修复。未授权真实环境迁移／部署；PR合并不等于发布。

## 验证入口

Linux 文件系统内使用现有 Go1.22.2、PG16、Goose v3.22.1：在 `services/api` 执行 `FEED_GOOSE=/absolute/path/to/goose PGPORT=55439 sh authlab/run-feed-isolated.sh`。脚本只建本次私有 socket／一次性库，结束自动停机清理，不接受外部 DSN。另执行 `go test -mod=readonly ./...`、`go build -mod=readonly ./...`、`go vet -mod=readonly ./...`。

仓库根执行 `python -X utf8 packages/openapi/check-specs.py` 和 `python -X utf8 tools/check-community-text-contract.py`。专属 [CI](../../.github/workflows/feed-backend.yml)执行同类产品检查。实际结果见[机器记录](feed-backend-verification-20261019.json)；正式前端接线、Android/iOS 设备与生产不在本次验收范围。
