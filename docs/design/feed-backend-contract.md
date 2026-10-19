# 新版帖子列表后端接线

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

有图增加 `imageCount:1..9`，无图省略；manifest／受保护字节继续走原图片 API，不返回公开媒体 URL。删除身份或关闭账号继续使用原独立 shortCode／inactive 投影。公开数据不包含账号／身份 ID、访客名单、是否已浏览、内部序号、偏好版本或本人管理权限；本人权能仍走原私有接口。点赞、收藏、评论和私信能力不在本任务扩展。

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

## 迁移与运行

新增 `0019_feed_backend.sql`，按正式顺序接在 `0001..0018` 后。仅新增三张私有表、时间索引和账号关闭清理触发器，不改原内容、绑定或回执。受控 owner 执行 Goose `up` 后重跑新版 `infra/postgres/grant-community.sql`；原来已启用图片、评论或治理时，按既有顺序重跑相应 `grant-post-images.sql`、`grant-comments.sql`、`grant-moderation.sql`，基线 grant 会重置 c_posts 权限。

新 posts 二进制要求完整0019；即使关闭帖子 HTTP，已安装0019的普通 C 启动仍核验注销 hook 和最小权限，缺失就拒绝启动。保持原 posts 配置、密钥、Gate 锚点、会话和 C/V 边界；V 无新表或授权。Down 明确拒绝，故障走原冻结／前向修复。本任务不操作真实环境迁移、合并或部署。

## 验证入口

Linux 文件系统内使用现有 Go1.22.2、PG16、Goose v3.22.1：在 `services/api` 执行 `FEED_GOOSE=/absolute/path/to/goose PGPORT=55439 sh authlab/run-feed-isolated.sh`。脚本只建本次私有 socket／一次性库，结束自动停机清理，不接受外部 DSN。另执行 `go test -mod=readonly ./...`、`go build -mod=readonly ./...`、`go vet -mod=readonly ./...`。

仓库根执行 `python -X utf8 packages/openapi/check-specs.py` 和 `python -X utf8 tools/check-community-text-contract.py`。专属 [CI](../../.github/workflows/feed-backend.yml)执行同类产品检查。实际结果见[机器记录](feed-backend-verification-20261019.json)；正式前端接线、Android/iOS 设备与生产不在本次验收范围。
