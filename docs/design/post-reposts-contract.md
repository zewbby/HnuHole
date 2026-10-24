# POST-REPOST-01 接线契约

适用：`feat/post-reposts`，未合并／未部署。产品决定由用户于 2026-10-23 确认：仅本人归档，不额外进入他人信息流；转帖归属于操作时选定的发言身份。普通转帖引用原帖，不附评论、不创建新帖、不改变原作者、不顺带绑定该帖评论身份。复制链接和系统分享不调用本接口。

## 身份、可见性与生命周期

- 每个仍有效的本人身份对同一原帖最多一条；同一账号不同身份可各保存一条。私人列表汇总这些记录，行键为 `identityId/postId`；取消只作用于该行身份。
- 服务端从当前 Bearer 得到账户；不接受客户端 accountId，不提供他人列表或公开参与者。identityId 仅为本人身份选择和私人归档用途，不加入公共 feed／详情 DTO。
- 新增必须验证身份属于当前账号且未删除，并在最终 C Safety Gate 事务内重新验证会话、账号代次及原帖权限。读取原帖复用 `readPublicPost`；不从历史拷贝恢复正文或图片。
- 原帖已删除、隐藏或不可访问：已有归档返回 `post:null`，显示“原帖已不可用”，可以取消；不可访问且本账号从未有此帖写入记录时，状态查询返回 404。
- 删除转帖身份时清除该身份归档并旋转相关账号／帖子写入版本；账号正式关闭清除本人全部转帖及版本。其他身份／账号不受影响。原帖作者身份删除／账号关闭，沿用原帖作者匿名投影。
- 迁移 `0026_post_reposts.sql` 新建引用表与独立版本表，无历史回填。版本表在取消后保留，防止旧请求复活。正式 C runtime 最低版本提高到 26，需同步执行 `infra/postgres/grant-community.sql`；不支持破坏性 Down。不得把迁移跑到未明确授权的数据库。

## HTTP

全部沿用 C HTTPS、`Authorization: Bearer …`、独立 `X-Request-ID`、`Cache-Control: no-store`。成功才返回 `Server-Time` 和 `Session-Expires-At`。完整机器规范为 `packages/openapi/repost-api.yaml`。

| 请求 | 输入 | 成功响应 |
| --- | --- | --- |
| GET `/api/v1/posts/{postId}/repost` | 无 body/query | `{postId,items:[{identityId,repostedAt}]}`，响应头 `Interaction-Version` |
| PUT `/api/v1/posts/{postId}/repost` | `{identityId,reposted:true\|false}`；必须有 `If-Interaction-Version` | 同上，返回提交后的实际状态与新版本 |
| GET `/api/v1/me/reposts?limit=20&cursor=…` | limit 为 1–50，默认20；cursor 可省略 | `{items:[{postId,identityId,repostedAt,post}],nextCursor:string\|null}` |

`post` 为原有 `PublicPost`／Dart `PostDetail` 投影：`postId,channelId,title,body,author,publishedAt,imageCount?`。图片清单和字节继续使用原帖受保护媒体 API，不能将媒体 URL 或鉴权信息写入归档。不可用时只有 `post:null`，不提供历史内容快照。

列表按 `repostedAt DESC, ordinal DESC` 排序；同时间用内部序号稳定打破平局。分页加密游标绑定账号、用途、limit 与快照上界，有效期30分钟。刷新获得新快照；分页期间新建／重新转帖不会插回旧分页。取消导致对应旧行消失。切换 limit、换账号、损坏或过期游标返回 `400 CURSOR_INVALID`，需要从首页刷新。

## 并发与失败

- 版本为带双引号的64字符小写十六进制不透明值；账号／帖子绑定，独立于点赞收藏版本，也不随别人操作变化。
- 创建和取消都是设置目标状态，不是 toggle。唯一键保证重复 true 不新增行、不重写转帖时间。
- 每个成功 PUT 都旋转版本，包括同值设置和空取消。旧版本得到 `412 INTERACTION_VERSION_CONFLICT`，不改变数据或续期。
- 传输失败／响应损坏后保留原条件重试或读取核对；只能在版本已经变化后认定旧请求不会再生效。遇412读取当前真实结果，不把旧 true 自动换成新版本重放。
- 缺少／非法版本、重复字段、额外账号字段、额外查询与不适用 `Idempotency-Key` 返回400；非本人或已删身份返回409 `POST_IDENTITY_UNAVAILABLE`；原帖不可用新增返回404 `POST_NOT_FOUND`；失效会话401；Gate／服务不可用503。其他限流与输入错误沿用帖子契约。
- 前端不乐观显示成功。保存中、结果待确认和真实已转帖分开；同帖未完成写入时暂停重复点击。共享 controller 负责状态、核对、列表作废和确认取消后的移除。

## Dart 公共入口

从 `package:hnuhole_mobile/hnuhole_mobile.dart` 导入：

- `HttpPostApi implements PostRepostsApi`：`postReposts`、`setPostRepost`、`ownReposts`。沿用原 `PostResponse<T>` 授权元数据；业务页面无需接触 Bearer。
- `PostRepostSnapshot`、`PostRepostMark`、`RepostedPost`；`RepostedPost.post` 可空，`key` 由身份与帖子组成。
- `PostRepostsController` 为 `PostController` 扩展；共享原 controller 实例即可，不额外构造独立账号缓存。
- `loadRepostState(postId,authorityVersion:epoch)`、`repostState(postId)`。
- `repostIdentities(authorityVersion:epoch)` 返回经过当前会话核验的本人身份目录；必须让用户选定身份。
- `setRepost(postId,identityId,enabled,authorityVersion:epoch)` 与 `retryRepost(postId,authorityVersion:epoch)`。
- `loadReposts(authorityVersion:epoch,more:false)` 刷新；`more:true` 加载下一页；读取 `repostItems/repostCursor/repostListLoading/repostListError/unresolvedRepostIds`。
- `PostRepostButton(controller:controller,postId:id)` 提供身份选择、创建／取消、未知结果核对，已接入首页及详情。
- 可选 `PersonalRepostsList` 提供独立栏目内容。它不是整张“我的”页面，不处理页头、心情、吸顶或其他栏目。

## 个人页会话接入

1. 先整合转帖分支服务端、迁移和客户端代码，保留个人页分支的喜欢／收藏与布局修改。共享锚点见下方，不整文件覆盖。
2. 页面和详情使用同一 `PostController`。页面创建时保存 `final epoch = controller.authorityVersion`；旧页面回调使用捕获的 epoch，不在点击时临时读取新账号代次。
3. 可以直接嵌入下例，或用上述公开 getter 自行构建现有 sliver 列表。controller 变化通过 `AnimatedBuilder` 或现有监听刷新。
4. 原帖详情始终用 `item.postId`；图片始终用现有 `loadImages`。不能把转帖身份当作原作者。
5. 自定义行取消传 `item.identityId`；identityId 仅用于映射本人目录昵称，不能输出账号或公开身份关联。不可用行不打开详情，保留取消入口。
6. 账号切换／退出／失效会清空归档并使旧响应、旧页面写入失效；不要另存会覆盖 controller 的本地数组。

```dart
PersonalRepostsList(
  controller: postController,
  loadImages: loadImages,
  onOpen: (item) {
    // 组件已经阻止 post == null；页面仍按原账号代次守卫导航。
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PostDetailScreen(
        controller: postController,
        postId: item.postId,
        loadImages: loadImages,
        onAuthenticationRequired: onAuthenticationRequired,
      ),
    ));
  },
)
```

如果个人页已拥有滚动容器，使用 `controller.repostItems` 接入原 sliver，避免嵌套第二个主滚动容器；保留原页签和滚动锚点逻辑。`PersonalRepostsList` 仅为可直接使用的完整栏目实现示例。

## 合并锚点

与个人页分支共享文件有：`http_post_api.dart`（新接口实现/import/part）、`post_controller.dart`（import/part、字段、账号变化清理）、`post_screens.dart`（详情互动区单个按钮）、`posts_endpoints.go`（独立路由分发）、`cursor.go`（新增scope）、README与交接文档。转帖主要实现都在独立 `post_reposts_*.dart`、`community_post_reposts*.go`、`post_reposts_*.go`。未修改 `personal_profile.dart`、`post_store.dart` 或个人页会话工作树。

验证结果与仍未验项目见 `docs/branches/feat-post-reposts.md` 和 `post-reposts-verification.json`；设备验收、页面会话实际整合和部署不得由宿主测试代替。
