# PERSONAL-PROFILE-MOOD-01

2026-10-23 · 分支 `feat/personal-profile-mood` · 基线 `cda337c43cf5d0e5793351577f7054ec552fb6d5`。
状态：页面、共享列表及 POST-REPOST-01 转帖接线已实现；未提交／推送／合并／发布。主线能力不据此提升。最新整合结果见 [个人转帖整合交接](personal-reposts-integration.md)。

## 当前实现与身份规则

- 左昵称右头像，字号24／头像直径60；移除账号、粉丝、标签、推荐和编辑整行；顶部搜索／设置保留，空状态入口改为加号。
- 头像旁切换身份按钮打开白色选择框，昵称／头像／帖子／回复／本机心情随身份变化。帖子、回复只显示当前身份；喜欢、收藏在同账号所有身份间共享。转帖按最新交接契约汇总本人仍保留身份的记录，每行显示转帖身份并精确取消，不随页头身份筛选。
- 五个栏目固定为帖子、回复、转帖、喜欢、收藏。全部显示小号图标和文字，选中项以240ms动画放大，底线同步移动；保持等宽点击区，避免切换挤动。上滑资料滚出、栏目吸顶，单列图文帖子复用现有组件。
- 纯白心情气泡尖角指向头像；加号展开编辑框，完成保存、取消不保存；12个可见字符（含组合emoji）、24小时有效。复用按环境／账号隔离的加密PostStore元数据，并按身份保存。兼容原始身份旧本机心情；没有公开或跨设备心情接口。
- 帖子支持最新／最热（点赞＋评论＋收藏，同分时间倒序），搜索遍历本人分页筛选标题。草稿、失败任务、回复图文、详情与图片继续复用现有逻辑。
- 本人帖子HTTP新增可选identityId，服务端核验当前账号拥有且未删除；游标绑定身份，分页不能跨身份重用。身份尚未确定时不展示混合内容；切换清理列表，迟到请求不会覆盖新身份。
- 喜欢与收藏新增读取接口 `/api/v1/me/liked-posts`、`/api/v1/me/favorite-posts`，支持分页／刷新，复用现有互动写入；按原帖发布时间排序。它们不接收identityId，保持账号共享，移除互动或原帖隐藏后不再返回。

## 个人页初版验证（整合转帖之前的历史证据）

- PASS：`flutter analyze --no-pub`，0 issues。
- PASS：`flutter test --no-pub test/personal_profile_test.dart test/personal_route_account_test.dart test/post_storage_test.dart test/post_screens_test.dart test/post_controller_test.dart`，121项。
- PASS：独立运行 `flutter test --no-pub test/post_api_test.dart`，34项。前一次与widget测试组合运行有未完成测试，独立复跑全部通过；不将中断算PASS。
- PASS：WSL Linux副本 `go test ./internal/posts ./internal/authprivacyhttp ./internal/authprivacy`。无DSN项明确跳过，不作为SQL证据。
- PASS：本次专属私有PostgreSQL16实例中运行 `TestPersonalIdentityAndSharedCollectionsPostgres`、`TestFeedInteractionsAccountIsolationAndConcurrencyPostgres`、`TestFeedInteractionsVisibilityRollbackAndSchemaPostgres`，3项真实SQL通过。实例已停止；未接触既有数据库。
- PASS：`python tools/check-community-text-contract.py`，16个受保护操作；`python -m unittest discover -s tools/tests -p test_community_text_contract.py`，9项契约检查。
- PASS：`git diff --check`。

宿主验证覆盖：320宽度五栏持续可见与中间动画帧、快速切换身份和迟到响应、帖子隔离、喜欢／收藏共享、心情按身份／账号隔离、12字emoji与24h过期、加密存储重开／注销、吸顶滚动、既有草稿／详情／删除／账号路由。真实SQL验证身份归属、分页游标隔离、共享列表、互动移除和隐藏原帖。

PASS：`flutter build apk --debug --no-pub --target-platform android-arm64`；产物 `apps/mobile/build/app/outputs/flutter-apk/app-debug.apk`。首次全ABI构建因网络受限不能下载ARM32 SQLite库失败，后使用既有ARM64缓存并通过依赖hook哈希校验完成限定架构构建；未改依赖锁文件。

设备安装与真机键盘／动画帧性能、真实HTTP端到端回复列表、iOS、独立评审、远端CI：NOT_RUN。测试替身与宿主截图不等于整机验收。新客户端的identityId和喜欢／收藏列表接口需要配套部署本分支服务端，不能直接声称已上线。

## 交接

页面：`apps/mobile/lib/src/posts/personal_profile.dart`；路由：`post_screens.dart`；身份选择与分页：`post_controller.dart`；加密心情：`storage/post_store.dart`。集合接口：`personal_collections_api.dart`、`http_post_api.dart`、`services/api/internal/authprivacy/community_posts_read.go`；契约：`packages/openapi/post-api.yaml`。

日志、宿主预览与临时工具：`E:/Hnuhole-env/personal-profile-tools/`（不入库）；Linux测试副本和已停用的一次性数据库：`/home/hnuhole/personal-profile-20261023-check`。

原转帖需求单保留为历史：[post-reposts-session-request.md](post-reposts-session-request.md)。最终产品规则以 [POST-REPOST-01 契约](../design/post-reposts-contract.md) 为准；本次接线和验收见 [个人转帖整合交接](personal-reposts-integration.md)。未启用子agent，未提交／推送／部署。
