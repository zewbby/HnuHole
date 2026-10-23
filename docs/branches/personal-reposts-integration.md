# PERSONAL-REPOST-INTEGRATION-01：个人页转帖接线交接

更新：2026-10-23。目标工作树 `E:/Hnuhole-env/source/HnuHole-personal-profile`，分支 `feat/personal-profile-mood`，基线 `cda337c43cf5d0e5793351577f7054ec552fb6d5`。状态：实现与限定宿主验收完成，未提交／推送／合并／安装／部署，无 PR。

## 整合范围

已先阅读 POST-REPOST-01 的接线契约、分支记录、验证清单、OpenAPI 和完整交付报告，再将来源工作树作为只读输入逐文件／逐块整合。来源：`E:/codexDoucuments/2026-10-23/post-repost-01-hnuhole-origin-main/work/HnuHole-post-reposts`；原交付报告位于其工作目录上级的 `outputs/POST-REPOST-01-handoff.md`。46 个来源交付文件的 SHA-256 与整合开始时清单全部一致；未修改或清理来源工作树。

- 独立转帖 API、HTTP、controller、组件、测试、Go 服务、严格路由、权限、0026 迁移、最低 schema 26、OpenAPI 与相关 CI 均已纳入目标分支。目标此前最大迁移号为 0025，无编号冲突；没有运行迁移、升级任何共享开发库或启动部署。
- 共享文件逐块保留双方功能。`HttpPostApi` 同时实现 `PersonalCollectionsApi` 与 `PostRepostsApi`；`PostController` 保留个人身份／心情／帖子逻辑并在授权代次变化时清空转帖状态；服务端路由与游标同时保留喜欢／收藏／本人身份过滤和新增转帖 scope。
- 个人页转帖直接读取同一 `PostController.repostItems` 等状态，使用现有 `CustomScrollView` 的 sliver，不嵌套 `PersonalRepostsList` 主滚动容器，也不维护第二份转帖数据数组。页签缩放、吸顶、返回锚点、心情气泡、喜欢和收藏实现保留。
- 转帖汇总本人仍保留身份，按转帖时间倒序，行键为 `identityId/postId`。切换页头身份不会筛掉转帖或重置该栏阅读位置；帖子／回复／心情继续按页头身份切换，喜欢／收藏继续账号共享。
- 身份昵称从本人身份目录读取，仅显示为“以某身份转帖”；原作者、正文和受保护图片组件仍属于原帖。刷新同一行会展示新的原帖投影。打开详情使用原始 `postId`；取消使用该行 `identityId`。
- 所有页面转帖读写与重试使用页面创建时捕获的授权代次。列表支持下拉刷新、分页、错误重试、未知结果核对；写入由来源控制器的条件版本协议处理，不乐观宣告成功。
- `post == null` 显示“原帖已不可用”，不显示历史正文／图片，不允许打开，保留精确身份取消入口。复制链接、分享和收藏不会调用转帖接口。

主要接线文件：`apps/mobile/lib/src/posts/personal_profile.dart`；共享路由与导入：`post_screens.dart`；新增链路测试：`apps/mobile/test/personal_reposts_integration_test.dart`。CI 已加入个人页与转帖链路测试；远端未运行。

## 本次限定验收

被测版本为上述基线上的未提交工作区；产品、测试和 CI 文件哈希见 [整合验证清单](../design/personal-reposts-integration-verification.json)。日志位于 `E:/Hnuhole-env/personal-profile-tools/repost-integration/`。

| 检查 | 结果与边界 |
| --- | --- |
| `flutter analyze --no-pub` | PASS，0 issues。初次发现测试缺少互动模型 import、测试 import 前缀与方法重名、页面未使用 import；修复后分析通过。最终仅修改测试返回按钮定位，不改产品代码。 |
| 转帖专项、个人页、账号路由、详情、首页六个测试文件 | 初次 70 PASS／1 FAIL；唯一失败是新增测试使用通用 `pageBack()`，而实际页面是中文“返回”按钮。 |
| 仅复验 `personal_reposts_integration_test.dart` | 改用实际按钮后 1 PASS；未重跑已通过的70项，合计71个不同测试通过。 |
| 宿主完整操作链路 | PASS：首页身份一转帖 → 原帖详情身份二转帖 → 我的聚合列表 → 分页显示同帖两身份 → 打开原帖 → 返回／切栏／切页头身份 → 刷新最新正文 → 只取消身份一。随后验证不可用原帖不可打开但可取消，以及退出／登录B后清空列表、旧取消回调不能写入B。 |
| 原个人页保持 | 既有测试覆盖窄屏五栏动画、心情限制和有效期、吸顶、身份隔离、喜欢／收藏共享及账号路由，通过。 |
| `git diff --check` | PASS。 |

初次集中命令：

```text
flutter test --no-pub --reporter expanded test/post_reposts_test.dart test/personal_profile_test.dart test/personal_reposts_integration_test.dart test/personal_route_account_test.dart test/post_screens_test.dart test/feed_ui_test.dart
```

唯一失败项的复验命令：

```text
flutter test --no-pub --reporter expanded test/personal_reposts_integration_test.dart
```

链路测试运行实际应用根路由、页面和同一真实 controller，HTTP 与存储为宿主替身，不冒充真实 HTTPS／SQL／设备验证；未执行真实图片网络加载。

## 来源证据与未验项

[来源验证清单](../design/post-reposts-verification.json)保留 POST-REPOST-01 原始记录：来源版本 Flutter 全量863 PASS／3既有fixture SKIP、分析0、Go test/build/vet、迁移25→26、一次性PostgreSQL并发权限、真实Dart→HTTPS→SQL、debug bundle及Android ARM64 APK均通过。它们只属于来源版本，本轮按用户要求没有重复执行这些矩阵，也没有借用为整合版本PASS。

本次整合版本的 Go test/build/vet、SQL／迁移执行、真实HTTP链路、Flutter全量、bundle／APK构建、Android／iOS真机、独立审查、远端CI均为 **NOT_RUN**。并发、丢响应和权限边界沿用来源测试证据；转帖专项宿主测试已在本次限定命令运行。原个人页初版155测试／3 SQL／9契约／ARM64构建记录也仅为历史证据。

配套后端需 schema 26 与新的数据库权限；共享开发库升级和部署仍需另行授权。本轮按限定验收范围结束，不扩大到安装、部署或重复全套验收；未启动子agent。
