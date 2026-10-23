# DM-IDENTITY-LOADING-01 私信身份状态与快捷切换

更新时间：2026-10-23。分支 `fix/direct-message-identity-loading`；基线 main `93d3ed6`。本页保留逐版实现与验收记录，最新结果见“最终2311候选与送审回执”；合并状态以[PR #60](https://github.com/zewbby/HnuHole/pull/60)为准，未生产发布。

## 问题与范围

用户反馈 vivo 主体包 2307 私信一直显示“正在核对私信身份”，随后确认该账号当时尚未设置帖内身份。原 `DmInboxRoute` 将 `own == null`（合法空目录）误判为加载中；目录请求异常又被 `DmRuntime` 捕获后仅定时重试，页面无法订阅失败状态。旧定点测试直接装配 DmController 或 runtime 替身，没有覆盖真实 runtime/auth/identity 装配。

随后用户确认增加紧凑右上身份切换、向下菜单、按现有名额补蓝色加号、快捷添加、删除“最近聊天”、搜索框简化为“搜索”。用户另报系统三键导航遮挡身份选择，要求沿用现有 Telegram 字体和风格，并查看实装组件 UI 图。

## 实现

- `dm_runtime.dart` 区分加载、空目录、失败、会话不可用、就绪，页面监听 runtime 与 controller。空目录为“您目前还没有身份”及相邻“添加身份”；失败提供重新核对。暂时传输失败保留登录，明确 unauthorized/unavailable 沿现有认证围栏收回访问，身份读取元数据先持久化再绑定。
- 身份管理 init/dispose 可同步通知：立即增加 runtime epoch 使旧窗口失效，再微任务合并刷新，避免在 widget build 中通知背后私信页。异步旧目录不绑定新会话。
- 右上紧凑入口按左箭头、中姓名、右头像排列，保持文字正常方向和至少 48dp 点击区。右下锚定菜单保留未读提示／当前选中，复用 Telegram palette、内置字体和轻动效；展开、首帧前后账号替换均关闭旧菜单，关闭搜索键盘后重算锚点。
- 身份总上限沿现有客户端 `canCreate` 与后端契约的 3 提取为 `IdentityDirectory.maximumIdentities`；当前最终菜单在未满额时仅提供一个紧接已有身份的蓝色加号入口，满额隐藏；冷却不伪装成满额。原补齐空槽方案按用户最新指令取消。加号进入现有 `_openIdentity(initialCreate:true)`，当前权限、目录就绪且 `canCreate` 才打开原编辑器；冷却／满额显示原说明。不会自动创建身份。
- 首次发送身份选择面板增加底部 SafeArea。发起联系选择原先已有 SafeArea，无需重复改动。

## 定点验证

源码与测试：`apps/mobile/test/dm_runtime_test.dart`、`direct_message_navigation_test.dart`、`identity_management_screen_test.dart`；更新 `direct-messages.yml` 产品 CI，保持现有路由／通知 fixture 兼容真实 runtime 可监听接口。

本机 Flutter 环境：先执行 `. E:/Hnuhole-env/env-windows.ps1`，依赖使用 `$env:PUB_HOSTED_URL='https://pub.dev'; flutter pub get --enforce-lockfile`。初次镜像离线解析不能满足锁，改用既有 pub.dev 缓存／锁成功，未改依赖或锁文件。

| 检查 | 结果与范围 |
| --- | --- |
| `flutter test --no-pub test/dm_runtime_test.dart test/direct_message_navigation_test.dart test/dm_route_test.dart test/dm_notification_navigation_test.dart test/identity_management_screen_test.dart --reporter expanded` | PASS，37 项。真实 runtime/auth/identity controllers + 宿主加密 SQLite，HTTP／系统 vault 为替身；含空身份、失败重试、元数据不循环、创建后绑定、401/503围栏、迟到跨账号、存储错误、root直达编辑器、冷却、菜单旧scope及首帧前撤销、触控/键盘/安全区。 |
| `flutter analyze --no-pub` | PASS，0 issues。 |
| 可选真实组件渲染 | PASS，1 项。见下方命令；两图仅渲染夹具身份，不读取真实用户聊天。 |
| Android／vivo | 该首轮实现agent未执行；主会话后续2309与最终2311限定结果见下方，设备空身份与首次发送面板仍NOT_RUN；不得把宿主 SQLite 当原生存储证明。 |
| 后端／旧DM大矩阵 | 未改后端；沿原结论，不重复既有文字／图片／设备恢复验证，不提升整个 B08/B09。 |

渲染命令（`apps/mobile`）：设置 `HNUHOLE_DM_IDENTITY_RENDER_DIR` 为本次输出目录，`HNUHOLE_UI_RENDER_ICON_FONT` 为现有 Flutter SDK 的 `bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf`，执行 `flutter test --no-pub test/direct_message_navigation_test.dart --plain-name 'render actual inbox identity selector collapsed and expanded' --reporter expanded`。使用仓库 Roboto/Noto Sans SC，390×844逻辑画布、48dp底部系统区、2倍PNG；图像不作为生产资产提交。

本地证据目录：`E:/Hnuhole-env/deliveries/dm-identity-ui-20261023/`，含 `focused-tests.log`、`analyze.log`、`render-test.log` 与 `dm-identity-collapsed.png`、`dm-identity-expanded.png`。

## 交付边界

主会话独立只读 review，首帧前替换菜单问题已补修并回归；最终精确提交 review、Android build／设备截图、PR／CI／合并回执由主会话和用户指定的提交代理继续登记。源码实现不等于已发布。README、HANDOFF、模块台账及最终进度由整合提交阶段统一汇总，避免多个代理写同一交接材料。

## 用户看图后的右对齐补充

原交付 `e6dd325` 的 2308 仅构建未安装。用户要求整个组件右对齐后，将入口放入 `Align.centerRight`，标题行右边距统一为搜索框的14dp，菜单锚点取入口右下角，使其向左展开。内部镜像排列不变。390dp定点断言验证入口右边缘等于搜索框、菜单右边缘等于入口（误差不超过1dp），该用例 PASS；新渲染1项 PASS。仅复测新增对齐，不重跑原37项／分析；原证据保留原源码范围。

新版两图及日志另存本地证据目录 `r2/` 子目录，未覆盖用户已看到的首版。后续由主会话构建2309并同签覆盖安装验收。

## 首次送审与整合状态（2026-10-23，历史快照）

应用源码固定 `5de60e3917b2ed74891a848d016e09426141063e`，含前置 `e6dd325b31b889b80b8570c941ba734c32dac768`。主会话独立只读审查两个提交的全部产品差异、日志和收起／展开组件图；首帧菜单旧scope撤销问题已修复并回归，无剩余可操作阻断。本记录属于 agent 审查，不是 GitHub 成员批准。

2308绑定e6dd325，仅构建PASS，用户追加对齐后未安装；2309绑定5de60e3，正常主入口同签构建及vivo保数据覆盖安装由主会话执行，本提交时待回执。合法空态与创建入口通过宿主装配验证；用户已自行创建身份，不删除其身份或切换账号来制造设备空态。组件图为宿主夹具、没有App底部导航，不能代替原生UI／安全区验收；含真实用户身份的旧设备截图不提交。

本次同步 README 分支入口与最近已合并#55、HANDOFF、progress和模块交接／台账。保持Draft等待2309新增UI／安全区设备结果、精确head远端产品CI及协作检查；仅这些通过后按既有授权合并main。未改后端、不重复未受影响旧DM矩阵，真实突然掉电NOT_RUN、P3人工SKIP、厂商推送未实现、iOS／生产未验保留。实现、合并、验收及发布分别登记，未正式发布。

## 新主线整合与单行入口（2026-10-23）

[Draft PR #60](https://github.com/zewbby/HnuHole/pull/60) 送审后 main 已更新到 `7a2a76a0a82d85b54f49a02c22ce924425cba4dc`，本分支合并保留 #56 启动恢复与 #57 底栏／刷新／图片功能。`main.dart` 相对该主线只保留 `_openIdentity(initialCreate)` 的参数及传递，将回调移到新的 `PrimaryTabs.builders.directMessages`；通知入口保留主线的身份／revision设置和选中底栏。文档冲突保留双方历史和边界，README最近变动采用新主线最新五项。

用户随后要求移除“当前身份”：入口变为箭头、姓名、头像单行垂直居中，右对齐、菜单和至少48dp点击区保留。只有 `direct_message_inbox.dart` 这一既有DM组件按此授权发生变化；其余已验DM运行时／身份管理／聊天组件源码保持原样。2309已由主会话同签保数据安装vivo，收起／展开／两个加号／直达创建并取消返回限定PASS，未创建身份；该旧包不代表此次主线整合与单行微调已原生验证。

仅新增受影响验证，未重复37项旧矩阵／图片后端／旧真机：

- `flutter test --no-pub test/dm_runtime_test.dart --plain-name 'production root opens real identity setup from empty DM inbox' --reporter expanded`：1 PASS，增加取消编辑、返回身份管理后跨底栏往返仍有添加入口且只有一条底栏。
- `flutter test --no-pub test/dm_notification_navigation_test.dart test/app_navigation_test.dart test/startup_entry_test.dart --reporter expanded`：5 PASS，包含统一底栏、通知精确身份及启动恢复。
- `flutter test --no-pub test/direct_message_navigation_test.dart --plain-name 'compact dropdown mirrors content, fills slots and opens add flow' --reporter expanded`：1 PASS，增加无副标题与箭头／姓名中心Y一致断言。
- `flutter analyze --no-pub`：0 issues；同既有渲染命令输出 `r3/` 收起与展开图：1 PASS，不覆盖r2。

本轮日志在原证据目录 `r3/` 下：`root-integration-test.log`、`navigation-integration-tests.log`、`single-line-alignment-test.log`、`analyze.log`、`render-test.log`。最终2310构建、独立review及新增布局／入口设备回执由主会话继续；PR精确head CI与合并回执由提交代理更新，当前未合并／发布。

## 最新菜单简化：只保留一个添加入口

用户看图后明确取消补齐三个名额空槽的旧要求。现仅在身份数小于现有上限时展示一条56dp“蓝色+”添加行，紧接最后一个身份项；满额不显示。名称、单行布局、右对齐和原创建权限／冷却约束不变。2310已经主会话构建并安装vivo，但该包仍为旧双加号，最新单加号候选由主会话构建2311。

只复测 `direct_message_navigation_test.dart` 中 `compact dropdown mirrors content and places one add row after identities` 与 `full identity menu has no add slot and stale scope dismisses it`：2 PASS；验证只存在一个+、紧邻最后身份、点击区48–56dp和满额不显示。实际组件渲染1 PASS，另存 `r4/` 两图与 `single-add-test.log`、`render-test.log`，不覆盖前版。未重复37项／整合7项／全量分析；旧结论保留原源码范围。

## 最终2311候选与送审回执（2026-10-23）

最终应用源码 `07193735513c69ad1a7ec4d6ecd0043e4f60a1fe`，`apps/mobile/lib` tree为 `bc77a63e9501f0bf7ccc6b1471f69ee0316693c6`，已整合 main `7a2a76a`。主会话独立只读review原需求全部产品差异、main三处必要入口整合与单加号最终微改，无剩余可操作阻断；该审查非GitHub成员批准。最终文档提交不修改源码，不重复原37项／整合7项／分析；各项证明范围绑定其原版本，r4补最终单加号2项及渲染1项。

2311正常主入口debug候选构建PASS，APK为188038636字节，SHA256 `58dce99b27ae5a7eb76172d06b9f814459eeb463dab67604803ea5e2ea708a2b`。与日常包相同签名 `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`，vivo V2323A执行 `adb install -r` 保数据覆盖成功，实际versionCode核对为2026102311。当前USB转发／私有CA开发环境，未部署或修改后端。

主会话实际设备限定PASS：最新main PrimaryTabs私信入口；没有“当前身份”副标题，箭头／姓名／头像单行居中且右对齐；搜索提示及旧标题移除；展开后一个蓝色加号紧接身份；添加行bottom804px小于系统导航top2274px；点加号直接打开既有创建编辑器；取消后返回DM，无持续核对。未输入或提交身份、未读取用户私信；设备lease已释放。

合法空态仍用真实runtime/auth/identity宿主装配覆盖，不修改用户当前已有身份来制造设备空态；首次发送身份面板SafeArea只具有宿主几何测试，native NOT_RUN。旧2309只保留其双加号／编辑取消／安全位置范围；2310仅构建覆盖及折叠单行通过，未成功捕获展开，后被最终单加号替代，不计完整通过或最终UI确认。

[脱敏版本证据](../design/direct-message-identity-verification-20261023.json)记录最终包和验证边界。本地原回执 `E:/Hnuhole-env/deliveries/HnuHole-dm-identity-2026102311-device.json`、APK及含用户昵称的截图留私有delivery，不提交Git。PR #60精确最新head的远端CI通过后按用户既有授权Ready并正常合并；最终合并SHA／CI回执写PR正文并核对main，不为记录自身递归创建PR，不删除分支或worktree。当前未正式发布；历史整模块、突然掉电、P3人工项、厂商推送、iOS及生产结论不扩大。

## 入口瞬时加载提示精简

用户在2311实际进入私信时仍看到瞬时“正在核对私信身份”，要求移除。本次仅调整 `DmInboxRoute` 展示：加载为22dp无可见文案的小进度指示（读屏“正在加载”），默认失败为“加载失败，请重试”，会话不可用为“暂时无法加载私信”，按钮统一“重试”；空身份及添加入口不变。不修改 runtime 状态机、权限判断、会话恢复、消息处理或后端。2311及其截图继续保留原范围，后继2312待主会话构建／覆盖安装回执，PR暂不合并。

仅运行 `dm_runtime_test.dart` 的空目录与加载失败重试2项，均PASS，覆盖小进度尺寸／读屏语义、失败／不可用无核对文案、失败重试成功且暂时失败不退出登录。`flutter analyze --no-pub lib/src/messaging/dm_runtime.dart test/dm_runtime_test.dart` 为0 issues。日志在原本地证据目录 `r5/entry-presentation-test.log` 与 `r5/analyze-entry.log`；未重复旧37项／整合7项／单加号／真实收发。
