# POST-LATEST-SORT-01 — 浏览帖子页“最新”排序入口

- 模式：常规
- 负责人：当前开发 Session
- 分支／Worktree／PR：`codex/fix/post-latest-sort`；独立 Worktree `E:/Hnuhole-env/source/SpeechFUL-post-latest-sort`；PR 未创建
- 授权依据与边界：用户要求修复“最新发布”组件并保留本地提交，不推送或合并；基线为 2026-10-30 拉取的 `origin/main` `76501d1a13c13ab0fa4a0919110c3bd00a2eba1c`
- 更新日期：2026-10-30
- 状态：实现已完成；验证宿主 PASS、真实 SQL 与 Android 构建 BLOCKED；合并未合并；发布未发布

## 目标与范围

浏览帖子页显示“最新”可点击入口。点击后请求当前范围的服务端第一页并回到列表顶部；下拉刷新重新获取第一页，加载更多沿用服务端游标。包含主页与旧通道列表入口、对应 Flutter 回归测试。没有修改服务端查询或接口契约。

## 接口与依赖

已实现的 `GET /api/v1/feed` 使用可选 `channelId`、`cursor`、`limit`；`GET /api/v1/channels/{channelId}/posts` 使用 `cursor`、`limit`。两者复用 `listPublicPosts`，SQL 按 `p.published_at DESC, p.publication_ordinal DESC` 查询，游标使用同一时间与序号元组，并在首次请求取得发布序号上界。`published_at` 在帖子首次公开发布时写入；后续帖子内容处理不写该列。无需新增排序参数。

## 验收标准

- 文案“最新”可点击，主页与通道列表均重新请求第一页。
- 新帖在刷新后出现在上方；后续页维持服务端整体降序与同时间顺序。
- 编辑不改变帖子的发布时间排序依据。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 原因与实现 | 基线 `76501d1` 加本分支差异 | 旧组件为纯 `Text`，没有点击回调；现改为按钮并接到现有 `loadTimeline`／`loadFeed`，回到顶部、重新获取第一页。分页仍使用服务端 `nextCursor`。 |
| 宿主静态检查 | Flutter 3.47.5 / Windows，`flutter analyze --no-pub` | PASS；No issues found。 |
| 宿主功能测试 | Flutter 3.47.5 / Windows，`flutter test --no-pub test/feed_ui_test.dart test/post_screens_test.dart test/post_api_test.dart test/feed_scroll_refresh_test.dart`；测试时临时使用已有 SQLite Windows 系统库，原 `pubspec.yaml` 已恢复 | PASS；98 项。覆盖按钮、范围参数、刷新新增帖、分页顺序、HTTP 参数与刷新手势。 |
| 服务端 SQL | 当前源码；现有 `TestFeedFilteringSnapshotAndPreferenceBindingPostgres`、`TestPostCeilingPaginationAndCursorIsolationPostgres` | NOT_RUN；本机 WSL 环境没有 Go 可执行文件，未把历史测试当作本轮结果。源码与既有测试确认时间与同时间序号的查询逻辑。 |
| Android bundle | `flutter build bundle --debug --no-pub` | BLOCKED；设置本机 Android SDK 后，SQLite native asset 需下载 Android `.so`，当前离线环境无法连接 GitHub。无构建成功或设备验收结论。 |

## 阻碍与下一步

本地代码与宿主回归已完成；后续若进入 PR／合并验收，须在具备 Go、PostgreSQL 与 Android native asset 的环境执行仓库 `feed-ui` 产品 CI。未推送、未合并、未部署。
