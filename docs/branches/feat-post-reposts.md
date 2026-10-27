# POST-REPOST-01：身份转帖

> 本文保留 POST-REPOST-01 来源工作树的交付事实与测试范围。转帖已在个人页分支整合，并由[PR #68](https://github.com/zewbby/HnuHole/pull/68)合入 main。来源分支旧“未提交/未合并”状态为历史快照；下方来源全量结果不代表整合版本验收。独立结果见 [个人转帖整合交接](personal-reposts-integration.md)。

原始交付快照：2026-10-23，分支 `feat/post-reposts`，建立时已 fetch 最新 `origin/main cda337c43cf5d0e5793351577f7054ec552fb6d5`。当时功能实现及限定验证已完成，尚未提交／推送、无独立 PR；后续转帖能力经个人页整合并由 PR #68 合入 main（状态回核见本文开头）。用户指定分支名优先于默认 codex 前缀。

工作树：`E:/codexDoucuments/2026-10-23/post-repost-01-hnuhole-origin-main/work/HnuHole-post-reposts`。

用户确认：转帖仅进入本人归档，不额外进入别人的信息流；归属于操作时选定的发言身份。复用原帖投影，不复制新帖，不附引用评论。私人列表汇总本人仍保留身份的转帖；每个身份对同一原帖最多一条，取消精确作用于该身份。身份选择不改变原帖作者，也不建立评论发言绑定。不提供公共转帖参与者或跨帖历史。

个人页工作树 `E:/Hnuhole-env/source/HnuHole-personal-profile` 仅只读参考；不修改 `personal_profile.dart`。独立 API/controller 及可嵌入列表交由页面会话整合。

## 已检查

- AGENTS.md、CONTRIBUTING.md、HANDOFF、personal/post-detail/identity 模块。
- 服务端 `community_post_interactions.go` 的最终 Gate 事务、账号锁、持久版本条件；HTTP 的严格 DTO、Bearer 和会话续期元数据。
- Flutter `post_interactions_controller.dart` 和 `PostController` 的账号／会话代次、未知结果核对与迟到响应隔离。
- `run-feed-isolated.sh` 自建一次性 PostgreSQL；产品 CI 覆盖 Go、SQL、Flutter 和契约检查。

## 完成标准

持久化创建／取消／分页，原帖访问边界，身份与账号隔离，重复及迟到写不复活取消，跨页共享真实状态，失败和未知结果可核对，个人页明确接入方式。静态检查、宿主测试、一次性 SQL、构建分别记录，未执行不得记 PASS。

## 当前验证

| 检查 | 结果与范围 |
| --- | --- |
| 仓库与源码隔离 | PASS；个人页工作树只读，本分支未改 personal_profile.dart；605个产品源码／依赖文件哈希与被测Linux镜像一致，依赖锁无变更 |
| Go | PASS：`go test -mod=readonly ./...`、`go build -mod=readonly ./...`、`go vet -mod=readonly ./...`；无DSN的宿主结果不替代下行SQL |
| 一次性PostgreSQL16 | PASS：`authlab/run-feed-isolated.sh` 自建且销毁私有Unix socket集群，`go test -race -count=1 -p 1`；含迁移25→26、空库、排序分页、快照、重复、迟到创建、并发取消、回滚重试、身份／账号隔离、隐藏／删帖、会话接替、Gate冻结、身份删除、账号关闭、最小权限及启动schema约束 |
| 真实传输 | PASS：编译后的生产Dart HttpPostApi→真实C HTTPS→一次性SQL；创建、读取、取消、外账号空列表、旧版本412，无内存接口冒充 |
| Flutter | PASS：`flutter --no-version-check analyze --no-pub` 0 issues；`flutter --no-version-check test --no-pub` 863通过、3跳过；11个新增专项测试包含跨页、旧响应、账号切换、未知结果重试、身份选择、不可用原帖取消 |
| Bundle与探针 | PASS：`flutter --no-version-check build bundle --debug --no-pub`；`dart compile exe integration/feed_live_probe.dart` |
| Android | PASS：arm64 debug APK构建成功；哈希见[机器证据](../design/post-reposts-verification.json)，未安装设备 |
| 契约 | PASS：全部OpenAPI规范完整校验（含repost-api.yaml）及社区文字契约检查 |
| 协作策略 | 未暂存工作副本调用原策略的路径／内容／分支检查及`git diff --check` PASS；未创建提交，不把空提交区检查冒充代码验收 |

全量Flutter首次因WSL缺少系统`libsqlite3.so`名称而失败；只在本任务Linux目录建立指向现存`libsqlite3.so.0`的链接并设置LD_LIBRARY_PATH后复验通过，未改产品依赖。3个跳过是现有私信外部HTTP fixture未提供。Android首轮在Windows挂载盘共享SDK的Gradle资源chmod失败；使用任务私有Linux SDK副本重试，未调整共享SDK源码／权限，未安装／部署产品；第二轮缺API35，改为任务私有SDK目录引用现有Windows API35及Linux工具后构建通过。

精确命令、日志摘要及SHA-256见[机器证据](../design/post-reposts-verification.json)。宿主与SQL结论不提升历史整个模块、原生设备或生产结论。

## 实现位置与接线

- 服务端：独立`community_post_reposts*.go`、`post_reposts*.go`、`posts/reposts.go`；复用最终Gate和账号锁、独立持久条件版本、严格DTO；`0026_post_reposts.sql`及runtime权限／最低schema26。
- 客户端：独立`post_reposts_api.dart`、`post_reposts_http.dart`、`post_reposts_controller.dart`、`post_reposts_widgets.dart`；共享PostController，首页与详情已有按钮，提供PersonalRepostsList及getter供个人页使用。
- 测试：`community_post_reposts_test.go`、`community_post_reposts_lifecycle_test.go`、HTTP／runtime同名前缀测试、`post_reposts_test.dart`；真实Dart探针扩展了原feed_live_probe，产品CI明确包含新专项与真实链路。
- 公开契约：[Markdown接线说明](../design/post-reposts-contract.md)及`packages/openapi/repost-api.yaml`。每页返回`items + nextCursor`，不可用原帖`post:null`，原帖投影复用PostDetail。

页面会话先整合本分支代码、迁移与权限，再把“转帖”栏目绑定同一PostController；可直接嵌入PersonalRepostsList，或使用repostItems构建既有sliver。详情打开item.postId，取消传item.identityId及页面创建时捕获的authorityVersion；不要把自己的转帖身份当作原作者。合并共享文件时逐块保留页面会话的喜欢／收藏和布局改动，勿整文件覆盖。

## 剩余与验收入口

1. 页面会话实际接入已确定的“帖子、回复、转帖、喜欢、收藏”布局；本分支按用户边界只交付可接入组件，未改整个“我的”页面。
2. 独立代码审查及提交后的远端产品CI尚未执行；本次仅主会话自审，不声明GitHub成员批准。
3. Android／iOS真机、系统分享不会触发转帖的设备验证、真实网络丢响应／强杀与长时间会话验收NOT_RUN。现有宿主模拟与SQL并发通过各自范围，不替代设备故障注入。
4. 迁移仅在任务自建库执行；共享开发库、生产、客户端安装均未变更。后续授权发布时成套升级C26迁移／grant／服务端与客户端，保留原账号与会话，按既有Gate发布流程操作。
