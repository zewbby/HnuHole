# PERSONAL-REPOST-INTEGRATION-01：个人页转帖接线交接

更新：2026-10-24。目标工作树 `E:/Hnuhole-env/source/HnuHole-personal-profile`，分支 `feat/personal-profile-mood`，基线 `cda337c43cf5d0e5793351577f7054ec552fb6d5`。状态：已提交推送至[PR #68](https://github.com/zewbby/HnuHole/pull/68)，独立agent审查与Android限定验收推进中；未合并／部署。下方初次限定宿主验收保留原版本范围，后续回执覆盖当前状态。

## 整合范围

已先阅读 POST-REPOST-01 的接线契约、分支记录、验证清单、OpenAPI 和完整交付报告，再将来源工作树作为只读输入逐文件／逐块整合。来源：`E:/codexDoucuments/2026-10-23/post-repost-01-hnuhole-origin-main/work/HnuHole-post-reposts`；原交付报告位于其工作目录上级的 `outputs/POST-REPOST-01-handoff.md`。46 个来源交付文件的 SHA-256 与整合开始时清单全部一致；未修改或清理来源工作树。

- 独立转帖 API、HTTP、controller、组件、测试、Go 服务、严格路由、权限、0026 迁移、最低 schema 26、OpenAPI 与相关 CI 均已纳入目标分支。目标此前最大迁移号为 0025，无编号冲突；没有运行迁移、升级任何共享开发库或启动部署。
- 共享文件逐块保留双方功能。`HttpPostApi` 同时实现 `PersonalCollectionsApi` 与 `PostRepostsApi`；`PostController` 保留个人身份／心情／帖子逻辑并在授权代次变化时清空转帖状态；服务端路由与游标同时保留喜欢／收藏／本人身份过滤和新增转帖 scope。
- 个人页转帖直接读取同一 `PostController.repostItems` 等状态，使用现有 `CustomScrollView` 的 sliver，不嵌套 `PersonalRepostsList` 主滚动容器，也不维护第二份转帖数据数组。页签缩放、吸顶、返回锚点、心情气泡、喜欢和收藏实现保留。
- 转帖汇总本人仍保留身份，按转帖时间倒序，行键为 `identityId/postId`。切换页头身份不会筛掉转帖或重置该栏阅读位置；帖子／回复／心情继续按页头身份切换，喜欢／收藏继续账号共享。
- 身份昵称从本人身份目录读取，在移除确认中标明所属身份；列表去掉状态文字、仅显示蓝色双箭头；原作者、正文和受保护图片组件仍属于原帖。刷新同一行会展示新的原帖投影。打开详情使用原始 `postId`；取消使用该行 `identityId`。
- 所有页面转帖读写与重试使用页面创建时捕获的授权代次。列表支持下拉刷新、分页、错误重试、未知结果核对；写入由来源控制器的条件版本协议处理，不乐观宣告成功。
- `post == null` 显示“原帖已不可用”，不显示历史正文／图片，不允许打开，保留精确身份取消入口。复制链接、分享和收藏不会调用转帖接口。

主要接线文件：`apps/mobile/lib/src/posts/personal_profile.dart`；共享路由与导入：`post_screens.dart`；新增链路测试：`apps/mobile/test/personal_reposts_integration_test.dart`。CI 已加入个人页与转帖链路测试；远端执行情况按下方后续回执记录。

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

## 2026-10-24 UI增量与验收续记

- “我的”左上角改为 `:)`，名字14px／头像28px／圆角身份按钮、箭头旋转、白色锚定菜单按私信页实现。保留白色心情气泡尖角、五栏目动画与单一吸顶滚动容器。身份弹窗销毁／切换后校验原账号与身份代次。
- 首页／详情／个人列表不再显示“已转帖”“取消转载”“以某身份转帖”等状态文字。统一圆角细线双箭头，选中为蓝色；三点菜单只有查看帖子、举报帖子、移除；蓝色图标及移除菜单均先显示“确认移除？”和取消／确认，所属身份在确认框中说明。
- 每张帖子评论、转帖、喜欢、浏览量、收藏、分享使用等宽操作区，图标中心等距；文字放在图标右侧。窄屏／放大字号仍沿用无溢出的折行布局。
- 本地UI增量最初31PASS／1FAIL，失败是独立归档组件新增确认后测试尚未点确认；修正测试后定点PASS。新增蓝色标记移除确认的取消及旧账号回调守卫测试PASS；身份／心情受影响定点回归PASS。分析0。未重复转帖分支全量／SQL矩阵。
- 独立只读补审：无阻断；已清理失效iconOnly参数。agent审查不代表GitHub成员批准。
- 真实设备：Realme RMX3366 Android14，独立applicationId个人页测试包，真实Bearer／TLS／C Safety Gate／SQL运行于本任务专属WSL C/V和PostgreSQL，无共享库升级。已验证双身份归档、原作者/原图、详情、精确移除乙保留甲、切身份汇总、心情、刷新、栏目吸顶、20+1分页、三点举报路由（未提交举报）、蓝色确认取消、操作栏等距。旧2e包图片自然60s到期返回已修复并真机复验PASS。
- 远端2e27252：10工作流PASS，Feed UI和Post images共同发现FA-O02两项媒体撤权首帧延迟FAIL；委派GPT-6.1 Sol XHigh定点修复，最终CI及新UI真机版本另记，不能引用历史36de788全绿代替。
- 新版不可用原帖、账号切换真机收尾、最终CI回执待完成；iOS、生产和GitHub成员批准NOT_RUN。

媒体CI失败后仅修复事件期撤权首帧重建，构建／布局期继续帧后调度；原失败两项原样PASS，直接相关11项PASS，最终分析0。后续最终提交与CI回执另记。

### 用户纠正：全局深浅主题一致

原2323个人页强制白底，造成主页/私信深色时个人页主体与身份/底栏混搭，记为FAIL。e722166已移除局部浅色覆盖并安装2324，真机深色全页确认已统一；Astra High只读代码/图片审查又发现草稿卡次要文字及删除确认框漏项，继续修复。当前个人页面、栏目、列表、身份菜单、心情编辑、转帖菜单/确认和草稿删除确认均使用全局主题；保留几何布局、账户/身份/条件写入语义。浅色和深色均必须真实截图通过才交付，旧截图不作最终颜色验收。

### 最新定稿：移除心情气泡

2026-10-24 用户取消心情气泡。已移除气泡、编辑框、定时到期和个人页心情读写入口，保留 `:)`、私信同款身份切换、搜索/设置及五栏目。旧心情验证与2325截图只作历史证明；最终新包应无气泡，深浅主题继续跟随全局。
