# POST-LATEST-SORT-01 — 浏览帖子页“最新”排序入口

- 模式：常规
- 负责人：当前开发 Session
- 分支／Worktree／PR：`codex/fix/post-latest-sort`；独立 Worktree `E:/Hnuhole-env/source/SpeechFUL-post-latest-sort`；PR 未创建
- 授权依据与边界：用户要求修复“最新发布”组件并保留本地提交，后续要求优先复用本机工具缓存补齐真实 PostgreSQL 回归和 Android 构建；不推送或合并。基线为 2026-10-30 拉取的 `origin/main` `76501d1a13c13ab0fa4a0919110c3bd00a2eba1c`
- 更新日期：2026-10-30
- 状态：实现已完成；验证宿主、真实 PostgreSQL 定点回归、Android ARM64 debug APK／bundle 均 PASS；合并未合并；发布未发布

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
| 服务端 SQL／HTTPS | 运行时代码 `cb4b935`；追加 `community_feed_test.go` 时间推进与刷新顺序断言，内容 SHA-256 见[验证摘要](evidence/post-latest-sort-20261030.json)；WSL Go 1.22.2、PostgreSQL 16.15、Goose v3.22.1 | PASS；仓库 `run-feed-isolated.sh` 创建独立一次性集群，`go test -race -count=1 -p 1` 执行三个选定用例，零跳过。覆盖新发布时间刷新、同时间稳定顺序、分页快照／游标隔离、真实 HTTPS 与通道兼容。测试结束后集群已停止并清理。 |
| Android APK／bundle | `cb4b935` 运行时代码；Flutter 3.47.5、JDK 17、SDK 36／NDK 28.2；`flutter build apk --debug --target-platform android-arm64 --no-pub` 与同参数 `build bundle` | PASS；完整默认 `lib/main.dart` APK 和 bundle 均构建成功，APK v2 签名验证通过，minSdk 29／targetSdk 36。APK SHA-256 `455edc217b3b0a5bae95bd9b9d305dda6d60365fb8eddfa6970b18bb78ec693e`，详情见验证摘要。未安装设备。 |

本轮确认上轮工具调查有遗漏：Go 已安装在 `/usr/lib/go-1.22/bin`，只是默认 PATH 未包含；此前“没有 Go 可执行文件”的描述不准确，已更正。Android 使用现有 Gradle／Pub／SDK 缓存，并复用经 sqlite3 3.7.0 官方 SHA-256 校验的 ARM64 `.so`；未更改 `pubspec.yaml`、锁文件或 Android 工程配置。构建时 Kotlin daemon 因宿主临时目录权限回退编译，最终 Gradle 返回 0，APK 校验通过。

SQL 复现入口：在 Linux 文件系统上的源码副本设置 Go／PostgreSQL PATH、`FEED_GOOSE`、已有 Go 缓存，并以非 root 用户运行 `services/api/authlab/run-feed-isolated.sh`；`FEED_TEST_PATTERN` 的三个精确用例及产物摘要保留在[验证摘要](evidence/post-latest-sort-20261030.json)。原始日志与 APK 保留在本机，未提交构建产物。

## 阻碍与下一步

本次要求的本地验证已完成；本轮只追加后端回归断言与验证记录，运行时代码保持 `cb4b935`。远端产品 CI、实体设备运行、其他 ABI／release 构建未执行，未推送、未合并、未部署。
