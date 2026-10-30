# POST-LATEST-SORT-01 — 浏览帖子页“最新”排序入口

- 模式：常规
- 负责人：当前开发 Session
- 分支／Worktree／PR：`codex/fix/post-latest-sort`；独立 Worktree `E:/Hnuhole-env/source/SpeechFUL-post-latest-sort`；PR 未创建
- 授权依据与边界：用户要求修复“最新发布”组件并保留本地提交，后续要求优先复用本机工具缓存补齐真实 PostgreSQL 回归和 Android 构建；不推送或合并。基线为 2026-10-30 拉取的 `origin/main` `76501d1a13c13ab0fa4a0919110c3bd00a2eba1c`
- 更新日期：2026-10-30
- 状态：实现已完成；本地验证及 vivo 用户试用通过，已获用户推送／合并授权；远端 CI 待运行，合并未合并，发布未发布

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

本次要求的本地验证已完成；本轮只追加后端回归断言与验证记录，运行时代码保持 `cb4b935`。远端产品 CI、实体设备功能验收、其他 ABI／release 构建未执行，未推送、未合并、未正式发布。

## vivo 用户试用安装

2026-10-30 用户要求安装到 vivo。基于 `29c3471`（运行时代码仍为 `cb4b935`）构建 ARM64 profile 试用包 `0.1.0-latest-sort`／`2026103005`，沿用既有 USB 联调配置与转发，APK SHA-256 为 `786aec6cf791067ee87fe7636f8116bcd3a3ac71531817ace85fa931a869b3c4`。签名与 vivo 原安装包一致，经验证后 `adb install -r` 返回 Success；未卸载或清除应用数据。

vivo V2323A（`10CEAG17RY003M7`）安装后读回版本 `2026103005`，启动成功并取得应用 PID。保留原首次安装时间 `2026-10-30 09:57:04`；安装完成时间 `11:02:47`（Asia/Shanghai）。当前等待用户实际测试“最新”、刷新及分页；安装／启动不代替功能验收。APK 位于本 Worktree 的 `apps/mobile/build/app/outputs/flutter-apk/app-profile.apk`，原始构建日志位于本机 `E:/Hnuhole-env/post-latest-sort-validation-20261030/vivo-build.log`。未推送、未合并、未更改后端。

### 用户试用后的选中态修复

用户确认点击已发出刷新请求，但选中标识仍停在“推荐”。原因是左侧下划线固定绘制，前次只接入请求，没有维护选中态。本次在 FeedScreen 保存“最新”选中状态，点击后将下划线移到“最新”，补充加粗与 selected 无障碍语义；下拉刷新、分页及通道切换保留该状态。

被测源码为 `29c3471` 加本次 `feed_screen.dart`、`x_feed.dart` 与对应测试差异。`flutter analyze --no-pub` PASS；`feed_ui_test.dart`、`feed_scroll_refresh_test.dart` 共35项 PASS，覆盖点击前后选中状态、实际下划线以及刷新／分页后保留状态。测试使用临时 Windows SQLite 配置，执行后恢复，依赖配置未提交变更。

ARM64 profile 试用包 `2026103006` 构建、验签、vivo `adb install -r` 与版本读回 PASS；APK SHA-256 `d2b450efd232ef3042f5fa7646f9fa88b197341042c1ac947675ace0f25a89d6`。沿用现有签名及联调配置，未清数据。实机后续停在筛选面板，停止继续操作，选中态视觉功能验收留给用户；不把安装或界面层级读取算作该功能实机PASS。日志保留在同一本机验证目录的 `selection-tests.log`、`vivo-selection-build.log`。未推送或合并。

### 推荐文字与下拉箭头交互分离

用户明确澄清：推荐系统设计与实现由「HnuHole｜总指挥｜性能优化与推荐算法」及相关 session 负责，本任务只处理点击交互，不设计推荐规则、不修改后端。此前提出的算法与范围问题不作为本任务需求。

基于 `3055d61`，将原先覆盖整个左侧区域的选择框按钮拆为两个独立按钮。文字按钮使用独立 `onRecommended` 回调切回左侧选中态，蓝条随之移动；仅下拉箭头的 `feed-channel-picker` 回调打开既有选择框。保留原有选项、所选通道及请求接口。未引入新排序算法或协议。

`flutter analyze --no-pub` PASS；`feed_ui_test.dart` 与 `feed_scroll_refresh_test.dart` 共36项 PASS。新增测试从“最新”点击“推荐”文字，验证选中态切回且无弹框，再单独点击箭头验证弹框与原选项选择正常。本机日志为 `split-controls-tests.log`。

ARM64 profile `2026103007` 构建、同签名验证、vivo 覆盖安装与启动 PASS，设备读回版本为 `2026103007`。APK SHA-256 `048d48af862768c781c1de4a166be1ef4b949b07afeda5071aa6de119445691f`，日志为同一本机目录下 `vivo-split-controls-build.log`。保留现有应用数据及联调配置，交由用户试用；未推送或合并。

## 送审授权

用户试用后明确回复“可以，推送合并吧”，授权本任务分支推送、PR 与合并。2026-10-30 重新 fetch 后 `origin/main` 仍为 `76501d1`，无新增主线差异。产品代码为 `29a332a`；本次仅补授权与交付状态，原产品验证仍适用。等待当前 PR head 产品 CI 后按授权合并；不包含推荐算法或后端部署。README 无项目能力或主要入口变更，不作单任务状态追加。
