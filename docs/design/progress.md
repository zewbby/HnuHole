# 设计进度与剩余工作

> **2026-10-08 F1-07最新候选v3：**保存失败已从底部面板改为居中两按钮弹框（左放弃／右重试），用户通过v2布局并要求厚重质感；[v3](ui-reviews/post-composer-save-failed-v3.md)已加强标题、说明文字、控件边界及暗灰蓝动作，视觉待评审。未将布局通过计为整页FINAL，其他身份三图不改。当前6正式＋4候选＋12未出图；代码未实现，业务／平台NOT_RUN。

> **2026-10-08 F1当前10／22页已出图：**F1-06[发布确认](ui-reviews/post-publish-confirm-v1.md)经用户“可以，下一批”正式定稿，正式文件[发帖-发布确认](../../UI产品图/发帖-发布确认.png)。通道三态＋编辑正常／键盘＋发布确认共6页FINAL；本批F1-07保存失败、F1-08身份选择、F1-09无身份、F1-10失效重选共4页DRAFT，见[本批记录](ui-reviews/post-identity-and-save-states-v1.md)。失效页以v2为当前候选，v1保留历史。其余12页未出图：我的3页、发布任务5页、详情4页。确认当前批次后继续“我的”类。本轮仅设计，Flutter社区代码未实现、业务及平台验收NOT_RUN，不改模块台账。下方此前计数按历史节点理解。

> **2026-10-08 F1共5／22张正式定稿：**用户对[键盘状态v1](ui-reviews/post-composer-keyboard-v1.md)明确“这个可以”，F1-05正式定稿，正式图为[发帖-键盘编辑](../../UI产品图/发帖-键盘编辑.png)。当前5张定稿为通道三状态、编辑正常态、键盘状态，配色不自动推广为全局主题。F1-06[发布确认v1](ui-reviews/post-publish-confirm-v1.md)已出图／DRAFT／待评审，产物`docs/design/ui-drafts/post-publish-confirm-v1.png`；从上到下标题／标签／身份、底部固定“确认发布”，无预览和额外确认。第二类正常与键盘已定稿、确认制作中、保存失败1张未画；加上其他四类15张，除制作中的确认外共16张未出图。本轮不写代码，Flutter社区文字切片未实现、业务验收NOT_RUN，不改模块台账或登记代码／平台验收PASS。以下此前记录按历史节点理解。

> **2026-10-08 F1共4／22张正式定稿：**用户看过[文字编辑页v1](ui-reviews/post-composer-edit-v1.md)后明确“可以，我同意这个”，F1-04编辑正常态正式定稿，正式图为[发帖-文字编辑](../../UI产品图/发帖-文字编辑.png)；加上F1-01／F1-02／F1-03通道三状态，共4张定稿，不扩大为全局配色。F1-05[键盘状态v1](ui-reviews/post-composer-keyboard-v1.md)按既有指令继续制作，图稿`docs/design/ui-drafts/post-composer-keyboard-v1.png`，已出图／DRAFT／待评审；其余17张未出图（第二类确认与保存失败2张、其他四类15张）。第二类4张中正常态已定稿，键盘待评审，确认／保存失败未画。本轮不写代码，Flutter社区文字切片未实现、业务验收NOT_RUN；不改模块台账或登记验收PASS。以下出图与确认记录保留历史状态。

> **2026-10-08 F1第一类3／3正式定稿（历史节点）：**用户明确“定稿这三个”，[v9通道三状态](ui-reviews/channel-feed-v9.md)登记F1-01／F1-02／F1-03正式定稿（布局＋本组三状态配色）。正式图为[通道最新列表](../../UI产品图/通道最新列表.png)、[通道暂无帖子](../../UI产品图/通道暂无帖子.png)、[通道首次加载失败](../../UI产品图/通道首次加载失败.png)；白色框架及偏暗偏灰的原蓝色UI仅作为本组定稿，不扩大为全局主题。v6先通过布局、v9生成期间曾待评审；v7林绿与v8整页暗蓝已废弃。图片／纯文字双列、点赞数、通道名、搜索、紧凑工具栏和底栏保持；“首页”回导航树，中央加号新建当前通道帖子，热榜仍由搜索进入。按既有指令继续第二类第一张[文字编辑页v1](ui-reviews/post-composer-edit-v1.md)，产物`docs/design/ui-drafts/post-composer-edit-v1.png`，已出图／DRAFT；其余18张尚未出图。本轮仅图稿与文档，Flutter社区文字切片代码未实现、业务验收NOT_RUN，无平台验收证据；不改模块台账或登记验收PASS。下方旧稿和隐藏策略按历史版本理解。

> **2026-10-08 F1视觉改稿：**原通道列表v1方向被否定；当前先评审[正常列表v3](ui-reviews/channel-feed-v3.md)的浅色双列与强对比卡片，未确认定稿。新版空／失败状态依正常图方向再同步，其余类别未出图；无Flutter或设备验收。

> **2026-10-08 F1页面设计启动：**第一类3／3张v1草图已生成并保存，分别为最新列表、空通道、首次加载失败；[评审记录](ui-reviews/channel-feed-v1.md)。待用户评审，不计定稿或功能PASS，其余19张尚未出图。

> **2026-10-08 UI能力补齐：**项目级frontend-design／ui-ux-pro-max／Impeccable及hnuhole-ui-craft已安装，四份技能结构验证通过；[UI工作流](ui-quality-workflow.md)已具体化中文排版、视觉克制、状态真实性和逐页PNG复审。来源及试跑边界见[技能记录](project-ui-skills.md)。没有新图或社区功能证据，不改变模块验收结论。

> **2026-10-08 Flutter社区第3项：**[实施计划](community-flutter-pages-plan.md)已完成规则／图稿阅读及Q1决策，状态PLAN_READY／IMPLEMENTATION_NOT_STARTED。当前分支 `codex/community-flutter-pages`；先逐页补设计，按后端固定契约推进业务状态及SQLite，再接认证候选进行真实链路与Android验收。没有业务代码或测试证据，不改变既有模块验收结果；完整评论／赞藏／搜索等另行开发。功能里程碑结束按AGENTS更新四份交接。

> **2026-10-05 AC06 当前交接：**匿名基础源码与本地交接材料已整理，详细结论见[最终交接报告](auth-privacy-final-handoff-report.md)、[AC06任务单](auth-privacy-final-handoff-plan.md)和[最终记录](../../services/api/authlab/final-handoff-verification.json)。后端／真实客户端回归保留AC04原证据，Android模拟器范围保留AC05；AC05整项、B02整模块及生产仍未通过。当前AC04–AC06修改尚未提交／推送，本地交接完成不代表远端已发布。历史规格／AI评审／旧台账按原日期、源码摘要与证明范围理解；下一步补外部平台配置与设备证据，或按当次授权发布当前材料，不自动开发完整业务片。

> **2026-10-05 AC05 当前交付：**当前完整 Android arm64 App、两个 instrumentation APK、模拟器 vault16项与3组跨进程、Passkey Dart9／Android codec5、Flutter真实原生双进程均PASS；新增身份草稿恢复／组合输入／账号隔离和原意图核对，write/read PID 7062／7189。Flutter分析及179项、四份OpenAPI本轮PASS。AC05整项和B02整模块仍BLOCKED：iOS／系统Passkey／物理设备／系统备份与完整App→实际C/V尚无完整证据。见[AC05报告](auth-privacy-platform-acceptance-validation-report.md)、[任务单](auth-privacy-platform-acceptance-plan.md)和[机器记录](../../services/api/authlab/platform-acceptance-verification.json)。保留AC04原指纹与证明范围；下一步AC06最终交接，不扩展完整业务片。本轮未提交／推送／部署。

下方记录按原日期与版本理解；当前平台范围和阻塞以台账 currentAC05 为准，后端回归保留 currentAC04。

> **2026-10-05 AC04 当前交付：**基于已推送 `cbc99b0`，补齐真实 Dart→HTTPS handler→SQL 的 V 独立冻结／恢复旧 OTP 围栏、身份关闭资料／永久历史和同邮箱新账号隔离场景；修正 R03 普通重启测试的授权事务停机时序，应用逻辑／公开 API／迁移未变。完整 Go／SQL／race／vet、R03 实际 C/V、Flutter 分析及179项测试、R05 均 PASS。覆盖、失败修复与精确范围见[AC04报告](auth-privacy-regression-validation-report.md)、[任务单](auth-privacy-regression-plan.md)和[机器记录](../../services/api/authlab/privacy-regression-verification.json)。B02整模块仍BLOCKED；下一步AC05平台验收，再AC06最终收口。本轮未提交／推送／部署。

下方 AC01–AC03 和平台记录保留原版本与证明范围；当前回归入口为台账 currentAC04，历史“未实现／未执行”不代表本轮状态。

> **2026-10-05 Git远端交付：**AC01／AC02／AC03源码、测试和小型证据已提交至 [8db630f](https://github.com/zewbby/HnuHole/commit/8db630f66bfc87cc05164aaae95b02b0d884d09a)，并普通推送到 `origin/codex/auth-privacy-handoff`；远端提交号已核验一致。本段是随后补充的交付记录。下方“未提交／未推送”及机器记录的uncommitted字段保留测试时快照，当前交付状态见台账publicationDelivery／Git提交历史。原测试摘要保留；额外Git文本摘要只允许CRLF→LF换行转换，协议向量仍逐字节核验。发布本次Git提交没有重新执行动态测试，也不代表部署、B02整模块验收或生产批准。

> **2026-10-05 AC03 当前交付：**当前数据／角色／HTTP／客户端持久状态及日志已完成有范围核对，修复应用错误／HTTP、PostgreSQL普通错误和移动端通道诊断三项差异；后续匿名业务契约已固定。完整Go／SQL／race／vet、R03实际C/V角色／日志与AC01／AC02回归、Flutter analyze与179项测试、R05真实Dart→HTTPS→SQL均PASS。见 [AC03报告](auth-privacy-boundary-validation-report.md)、[三步任务单](auth-privacy-boundary-plan.md)、[后续契约](auth-privacy-business-contract.md)及[机器记录](../../services/api/authlab/privacy-boundary-verification.json)。B02整模块继续BLOCKED，公共内容／聊天／管理消费者尚未实现，原生设备／生产证据单列。未提交／推送／部署。

以下 AC02／AC01及更早记录保留原日期、摘要和证明范围；“AC03未实施”等仅描述历史版本。currentFeature旧SQL／Flutter等字段明确保留为历史快照；本轮结果见currentAC03，历史平台不代证当前native验收。

> **2026-10-04 AC02 当前交付：**在保留 AC01 的工作区中，整账号正式关闭与身份联动已实现，完整服务端 SQL／race／vet 和 R03 实际 C/V 验收均 PASS。正式关闭原子擦除活动身份资料，保留累计状态、已有墓碑和永久回执；11→12 前向升级、受限角色、冻结／并发／回滚及同邮箱新账号独立历史取得本轮证据。详见 [AC02报告](auth-identity-account-closure-validation-report.md)、[实施任务单](auth-identity-account-closure-plan.md)及[机器记录](../../services/api/authlab/identity-account-closure-verification.json)。AC03 尚未实施；B02 整模块仍 BLOCKED，帖子／聊天业务调用、客户端／设备与生产缺口单列。未提交／推送／部署。

以下 AC01 及更早交付保留原日期、源码摘要与证明范围；“AC02 未实现”等表述仅描述历史版本。当前服务端版本以 AC02 记录为准，历史平台结果不能代证当前回归。

> **2026-10-04 AC01 交付（历史版本）：**基于 `faf557d` 的本次工作区已实现 V 独立 Gate，最终完整 Go／SQL／race／vet 和 R03 实际 C/V 进程验收均 PASS。V 正式迁移 3→4、独立状态／材料／连接池、受限恢复角色、最终资格事务、后台外部调用代次复核和旧 V schema 快照阻断均已接通。详见 [AC01报告](auth-verifier-safety-gate-validation-report.md)、[实施方案](auth-verifier-safety-gate-plan.md)及[机器证据](../../services/api/authlab/verifier-safety-gate-verification.json)。AC02／AC03 尚未实施；B02 整模块仍 BLOCKED，平台与生产门槛单列。本次改动尚未提交／推送。

以下原有 2026-10-04 平台交付及更早记录保留其原版本和范围；其中“AC01 未实现”和工具未执行等字段描述历史状态，当前 AC01 以上述证据为准。

> **2026-10-04 最新验证与环境交付：**基于远端 `codex/auth-privacy-handoff` 的 `d624ea30943a2b12096c20dbeefd844ba0e5e840`。Flutter分析与175项mobile测试、真实Dart→HTTPS→PostgreSQL R05、Android完整app构建、16项vault＋3组跨进程探针、9项Passkey Dart／5项Android codec和真实Flutter双进程共享AuthStore探针均PASS；Go/SQL/race/vet、R03实际C/V进程及完整OpenAPI已在本轮复验。环境与可复验命令见[本机环境](local-test-environment.md)，精确证明范围／失败修复见[最新记录](../../services/api/authlab/identity-runtime-test-verification.json)。**B02整模块仍BLOCKED：AC01 V Gate、AC02身份整账号关闭尚未实现，iOS、真实Passkey ceremony和物理设备／B02设备矩阵仍未验。**用户要求保留D盘工具环境、删除全部测试缓存和临时产物，完成后直接推送对应分支。

## 历史记录与验收目录

以下记录保留原日期、版本及证明范围；“缺Flutter／未验／未提交”只描述当时状态，现行结果见顶部入口和机器台账。

> **2026-10-03 本机接续验证（历史）：**从远端codex/auth-privacy-handoff的87e603c3f54b2fc08d1501dd3a0d7db5b70d17cc拉取。AC04的B02 R03/R05测试源码已补；**Go全量SQL/race/vet、四份OpenAPI完整校验及R03实际非owner C/V HTTPS/mTLS进程验收通过**。R03覆盖身份CRUD、成功和拒绝回执、实际服务重启、Gate冻结/恢复后新会话核对、迁移10→11及缺表/缺DML拒绝。实际启动发现权限检查format()参数未指定类型，已补$1::text并通过实际进程和匹配race/vet复验。Go位于WSL /usr/lib/go-1.22/bin；PG/Docker可用，固定Goose仅在本次临时目录构建。**Flutter/Dart入口未找到，R05真实Dart→SQL及设备/原生Passkey仍BLOCKED/NOT_RUN，B02整模块未PASS。**AC01 V Gate、AC02身份整账号关闭仍未实现。逐项结果、失败修复/复验和源码摘要见[接续测试记录](../../services/api/authlab/identity-runtime-test-verification.json)。下方旧机器/版本和缺Go/未补B02测试链描述是历史状态。

> **2026-10-03 远端接续交付：**用户已授权将当前匿名收口材料、运行时／设备／B02源码与测试提交并推送到 `origin/codex/auth-privacy-handoff`，由另一台机器继续。先读[机器接续入口](auth-privacy-machine-handoff.md)，再按[匿名清单 AC01–AC06](auth-privacy-closure-checklist.md)执行；提交／推送不代表缺口已修复或动态验收通过。下方“未提交／推送”是历史记录，最新交付状态以本次提交及远端结果为准。

> **2026-10-03 匿名分支范围纠正：**本分支以匿名方案及其基础实现收口，停在 B02，不进入 B05/B03 等完整业务片。当前有限缺口和结束条件见[匿名收口清单](auth-privacy-closure-checklist.md)：先补 V 独立 Gate、现有身份的整账号关闭联动，再核对隐私边界、补真实测试链与集中验收。B02继续登记为“基础管理已实现，业务联动待实现”，动态／设备未执行项保持待验；本段覆盖下方历史开发顺序，不改写历史测试证据。

> **2026-10-03 B02身份管理基础：**本人身份列表／创建／改名／删除、默认头像和我的→设置入口已写入；注册零身份仍能浏览，落实最多3个／不能删最后一个、累计创建及六个月／30天限制。全部访问最终Gate／会话／归属复核，账号串行及成功／拒绝终态回执保护未知提交与迟到重试。**基础管理已实现，业务联动待实现；编译、SQL、Flutter和真机验收待执行。**帖内绑定、旧帖／聊天投影随业务模块，自定义头像随媒体实现。见[任务单](identity-management-plan.md)、[报告](identity-management-validation-report.md)、[机器记录](../../services/api/authlab/identity-management-verification.json)和[模块交接](module-acceptance-handoff.md)／[台账](module-acceptance-ledger.json)。后续按[匿名收口清单](auth-privacy-closure-checklist.md)补齐基础缺口并交付，不进入完整发帖／列表业务片；未提交／推送。

> **2026-10-02 设备／恢复凭据／原生Passkey：**当前／最近接替设备及退出、恢复码轮换全量确认与持久结果核对、Android/iOS绑定／两步移除／可发现恢复已写入工作区；runtime固定RP／签名origin已接。真机vault／跨进程与冻结／接替／迟到响应测试源码已补。**编译、动态和设备验收待执行，RP／平台关联配置未提供。**见[任务单](auth-privacy-device-credentials-passkey-plan.md)、[报告](auth-privacy-device-credentials-passkey-validation-report.md)、[模块交接](module-acceptance-handoff.md)／[台账](module-acceptance-ledger.json)。缺工具不停止指定功能开发；源码完成不计验收通过；未提交／推送。

> **2026-10-02 用户决定可先开发后集中分模块验收：**无需等待另一电脑；[模块测试交接](module-acceptance-handoff.md)及[机器台账](module-acceptance-ledger.json)分别列出已有实现的待验／待复验、原生未验、尚未实现业务、安全与生产缺口。[AGENTS.md](../../AGENTS.md)要求每个功能任务结束同步未测项、原因、测试入口和影响模块。动态／设备验收可延期，代码实现不计为验收PASS；可用的必要检查仍按实际执行记录。后续任务照已收口规则开发并持续维护台账，生产放行前完成相关模块及跨模块验收。以下历史“先验收再进入下一片”的顺序已被本项更新，未通过记录不改写。

> **2026-10-02 T0–T6 实施已落盘，验收未完成：**只基于 `codex/auth-privacy-handoff`，按[C/V 开发服务与目录闭环计划](auth-privacy-runtime-business-integration-plan.md)加入正式迁移／受限角色、两个实际服务入口与开发引导工具、持久 worker、C Gate 同事务目录读取／续期、移动端权威截止持久更新和实际 cmd 一次性 runner。记录见[本轮报告](auth-privacy-runtime-business-integration-validation-report.md)及[机器记录](../../services/api/authlab/runtime-business-integration-verification.json)。本机缺 Go／gofmt、Docker／PostgreSQL 与 Flutter，动态命令因缺工具失败，尚未编译／验证 SQL／race／真实链路，也未提交或推送。下一步在现成工具环境完成格式化、生成漂移、全部回归和实际进程 runner，不把历史通过记录外推到本次改动。[第40轮](../discussions/2026-10-01-grilling-round40.md)确认的 V Gate 另片、全新开发库＋临时升级、Windows＋WSL2 及设备并行范围不变；大型运行时未重下，后续顺序以本段为准。

> **2026-10-01 原生存储与真实 C/V 联调：**真实 Flutter→隔离 C/V HTTPS／PostgreSQL 已跑通注册、会话接替／续期、未知结果核对、Gate 冻结／签名恢复和注销释放 ACK。Android 原生／测试编译与测试 APK 已完成，新增 16 项设备故障测试和跨进程探针；iOS 标记同步重试及跨 engine 串行修复，macOS 文件系统回归通过。本机未做设备执行、完整应用构建或 iOS Keychain 验证。用户要求删除大型临时验证运行时、缓存和 APK并推送远端给另一电脑复验，命令与实际证据见[本轮报告](auth-privacy-mobile-native-integration-validation-report.md)及[机器记录](../../services/api/authlab/mobile-native-integration-verification.json)。下一步先补平台验收，再做设备／恢复凭据管理页面和原生Passkey；生产路由授权接Gate、迁移、业务清理／通知及独立安全验收继续待做。

> **2026-09-30 移动端核心认证状态机（历史节点）：**指定分支 `codex/auth-privacy-handoff` 已接入校邮注册、恢复码隐藏后完整确认、密码登录、权威恢复／活跃续期、七天注销和持久结果核对。退出先确认登出标记持久化，再删除Bearer并以独立能力异步定向撤销，旧任务不影响新会话。系统安全存储适配器及Android/iOS工程已加入；完整Dart／TLS／组件回归和Go故障回归见[本轮报告](auth-privacy-mobile-auth-validation-report.md)及[机器记录](../../services/api/authlab/mobile-auth-verification.json)。下一步先做原生构建、真机安全存储故障与真实C/V整链联调，再补设备／凭据管理页面。原生Passkey、生产路由／迁移与业务授权接Gate、注销清理／通知、运营分权及独立安全验收继续待做。

> **2026-09-30 恢复凭据管理隔离实现（历史节点）：**当前分支 `codex/auth-privacy-handoff` 补齐新鲜密码复验恢复码轮换、可选 Passkey 的绑定／可发现恢复／两步移除，以及受限凭据清单。管理权限绑定原凭据版本、同一会话、固定RP策略及Gate代次，最终事务再次复核；普通变更保留其他凭据和当前会话，重设／关闭撤全部旧Passkey。交付与最终验证见[本轮报告](auth-privacy-recovery-credentials-validation-report.md)和[机器记录](../../services/api/authlab/recovery-credentials-verification.json)。下一步进入移动端安全存储、持久结果核对／登出待办及完整认证状态机；生产路由／迁移、真实平台Passkey演练、业务数据清理／通知及生产安全验收继续待做。

> **2026-09-30 恢复码与七天注销隔离实现（历史节点）：**在登录／会话切片之上加入恢复码证明、唯一重设意图、最终密码重设与无秘密结果核对，以及七天注销申请、截止前主动登录取消、到期关闭、受限状态与释放收据。密码重设不登录、不取消注销、不解除处罚；封禁受信命令即时撤会话，迟到封禁不能取消到期申请。新增授权与清理继续经过 Safety Gate。交付范围与证据见[本轮报告](auth-privacy-recovery-closure-validation-report.md)和[机器记录](../../services/api/authlab/recovery-closure-verification.json)。可选 Passkey、恢复码轮换、移动端、业务数据清理／通知和生产接入仍待做。

> **2026-09-30 登录与会话隔离实现（历史节点）：**在已落地的 Authorization Safety Gate 上，C 实验包增加用户名密码登录、单设备接替、权威会话恢复／同令牌续期、最近替代设备读取与独立撤销秘密定向退出；有界清理保留幂等墓碑与最终服务端到期后的摘要窗口。[本轮报告](auth-privacy-session-lifecycle-validation-report.md)和[机器记录](../../services/api/authlab/session-lifecycle-verification.json)说明真实 SQL／HTTPS／并发／冻结验证。下一步是独立恢复与七天注销的权威事务、处罚写入口，再接移动端和生产路由／迁移。`PENDING_CLOSE` 登录现先 fail closed，待注销截止模型接入后实现截止前主动取消；生产安全验收仍未完成。

> **2026-09-30 第 0 步隔离实现：**Authorization Safety Gate 已接入现有 C 注册意图、最终开户与初始会话、隔离认证读入口；含持久冻结、库外签名证据／锚点、可信时间高水位、授权代次及受限签名恢复。5 秒回退／5 分钟证据、旧快照、跨连接和提交途中冻结等故障测试见[本轮报告](auth-authorization-safety-gate-validation-report.md)。第 0 步隔离验收后可进入用户名密码登录＋完整会话管理；生产独立授时、恢复运营、真实灾备、人类审计仍未完成。

> **2026-09-29 第 0 步设计历史：**Authorization Safety Gate 设计在第 39 轮收口：FROZEN 时所有认证读写 fail closed；单个受限恢复角色执行显式恢复，不采用双人控制；允许 5 秒时钟回退抖动；可信证据 TTL 5 分钟。后续实现状态以上方 2026-09-30 记录为准。

> **2026-09-29 当前实现进展：**用户已授权进入 Phase E。[实验切片](../../services/api/authlab/README.md)在首条数据库验证后加入校邮发码／确认、最新码与预算、退役后的原确认续办、双方 HTTP／mTLS 和注册密码准备。实现、真实 PostgreSQL／TLS 故障验证及剩余门槛见[本轮报告](auth-privacy-eligibility-http-validation-report.md)。生产路由／迁移、用户名密码登录、独立恢复、七天注销、移动端及生产安全验收继续待做。

> **2026-09-28 规格阶段背景：**每次注册校邮收码，用户设置私有用户名和独立密码；日常用用户名和密码登录，不通过邮箱查找旧号。同一精确邮箱地址同时最多一个有效账号的配额依赖 V 按协议执行；正式注销后释放配额，再次收码建立全新账号。旧号找回需事先保存的独立凭据，邮箱验证码不能单独重置。V/C 通过本次资格槽位协调配额；串通或共同泄漏时能连接邮箱与账号。架构见[认证与隐私架构决策](auth-privacy-architecture-decision.md)，注册、退役与释放见[协议 v1](auth-privacy-registration-protocol.md)。[恢复策略](auth-privacy-recovery-decision.md)、[逻辑数据／API 契约](auth-privacy-data-api-contract.md)与[内部跨方威胁模型](auth-privacy-threat-model.md)已成稿；[V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)、[C OpenAPI](../../packages/openapi/community-auth-api.yaml)与[迁移设计](auth-privacy-database-migration-design.md)已成稿；[固定向量与静态复验](auth-privacy-protocol-vectors.md)、[独立评审输入包](auth-privacy-security-review-package.md)已整理；仍须生产库／实际SQL验证、双主体运营与**独立**安全评审，生产认证代码未开始。

盘点：2026-09-20。消息身份切换展开 v2、收到的 v2、我发出的正常状态 v1、系统通知失败详情 v1、顶部失败提示 v1、系统通知时间流 v2、举报处理结果详情 v1、违规处理通知详情 v1、申诉待复核详情 v1、结果通过 v1、结果未通过 v1 均已确认。首次申诉 v2、补充材料 v1、私信举报选择原因配色 A v1 已生成待评审。新页逐张试不同黑底配色，用户明确锁色后才统一。直接给图、不附 prompt；用户同意页面定稿就直接制作下一张。已确认不表示已实现或图稿齐全。

## 2026-09-29 认证实现接续

用户已明确授权校邮确认、退役后的原确认续办及双方 HTTP／mTLS。实现与故障验证见[本轮报告](auth-privacy-eligibility-http-validation-report.md)，当前代码和实验迁移均在独立验证目录。此后按 Phase E 继续登录、会话与独立恢复；生产门槛另行验收。

## 开发阶段（2026-09-23）

- 用户已暂停 UI 设计讨论，进入工程方案阶段。
- 已确认工程基线：Flutter + Dart 移动端、Go 服务端、模块化单体后端；记录见 [ADR 0001](../adr/0001-engineering-baseline.md)。
- 已确认通信与持久化基线：`net/http` + `chi`、PostgreSQL + `pgx`/`sqlc`、REST/JSON + OpenAPI、前台 WebSocket 事件、Drift/SQLite 与系统安全存储；记录见 [ADR 0002](../adr/0002-communication-and-persistence-baseline.md)。
- 已确认仓库、认证和首条切片：单仓库 monorepo、`goose` + `oapi-codegen`、服务端不透明会话令牌、宿主机 Flutter/Go + Docker Compose 基础设施，以及文字内容主链；记录见 [ADR 0003](../adr/0003-repository-auth-and-first-slice.md)。
- 首条切片直接实现基础导航树，拆为两次开发任务；未登录只显示树入口外壳，已有账号登录或新账号注册并建立会话后，完整目录校验通过才加载节点；目录失败保留无节点树并可重试；默认无热度时先露出吐槽、避雷、安利、搭子、情感。
- 首条切片保留可选 `#标签` 字段但暂不实现输入、复用和筛选交互；已发布内容和身份写入服务端数据库，本机草稿写入 Drift/SQLite，重启后须可恢复。
- 任务 1 的通道目录 API 定为 `GET /api/v1/channels`，采用英文不可变 `code`；迁移、API、客户端加载和树交互四层自动化验收纳入首批测试。代码骨架已建立，但测试和生成链因本机缺少 Go/Flutter/Docker 尚未执行。
- 通道编码和冷启动顺序已固定为 `vent`、`warning`、`recommendation`、`buddy`、`emotion`、`mutual_help`、`technology`；目录接口成功/未授权/暂不可用分别使用 `200`/`401`/`503`，OpenAPI 源文件为唯一契约。
- 首版可能超过 10000 用户；该规模不改变 monorepo 决定，容量和运行时扩展另行设计。
- 已确认 CI、测试、开发验证与部署基线：本地 Git + GitHub Actions、Go 单元测试 + Docker PostgreSQL 集成测试、Mailpit + 开发验证适配器、容器化无状态 API + 托管 PostgreSQL + S3 兼容对象存储；记录见 [ADR 0004](../adr/0004-ci-testing-email-and-deployment.md)。
- 用户不熟悉 Git/GitHub；后续提交、推送和 Actions 检查会提供逐步操作说明。
- 本地 Git 已初始化为 `main`，当前开发分支为 `feature/engineering-baseline`；远程 `origin` 已绑定 `https://github.com/zhubaozhenshuai666-lang/HnuHole.git`，并跟踪对应远程分支。
- 尚未确认：聊天本地加密方案、生产推送供应商、具体云厂商/区域、CI 密钥与发布流程、第一条切片之外的功能顺序。
- 已建立任务 1 的 Go API、PostgreSQL 迁移/OpenAPI 契约和 Flutter 入口树代码骨架；本机没有 Go/Flutter/Docker 可运行环境，测试与生成链尚未执行。
- 后续认证切片范围已确定：V 的每次新注册校邮验证与配额、C 的新号创建和用户名密码登录、事先设立的独立恢复方式、服务端会话恢复／退出，以及登录后加载通道；首次注册不自动创建身份，无身份账号仍可浏览。[协议 v1](auth-privacy-registration-protocol.md)、[恢复策略](auth-privacy-recovery-decision.md)及[数据/API 契约](auth-privacy-data-api-contract.md)已成稿，当前已按新规格开展隔离实现；生产接入仍须完整链路验证、双主体运营及安全评审。
- 认证主链的行为边界已补齐：账号可无身份浏览；首次公开发言时才创建/选择身份；服务端接受有效发送任务时原子绑定帖内身份，后续主评论和楼中楼回复直接复用；身份设置前保留原操作输入。主动退出保留按账号隔离的本机草稿和文件；恢复 `401` 清令牌与节点，`503`/超时保留本地状态重试；新设备接替旧设备返回 `401/session_replaced` 并保留本地文件。
- 旧“四接口、验证码确认即恢复旧号”设想已废止。新客户端认证主链须覆盖 V 的验证码申请／确认、C 的新号注册、用户名密码登录、独立凭据恢复、会话恢复／退出；通道目录仍为 `GET /api/v1/channels`。跨方资格、退役与释放的流程见[协议 v1](auth-privacy-registration-protocol.md)，精确调用契约见[数据/API 契约](auth-privacy-data-api-contract.md)，精确schema见[V OpenAPI](../../packages/openapi/verifier-auth-api.yaml)及[C OpenAPI](../../packages/openapi/community-auth-api.yaml)。认证成功后恢复原入口意图；V/C 各自使用本方幂等与重试规则，不能跨方共享幂等键。
- 2026-09-23 至 2026-09-25 的邮箱唯一登录和稳定匿名凭证方案已被当前决策替代，原始过程仅见[历史 ADR 0005](../adr/0005-privacy-preserving-email-authentication.md)及[第三十二轮](../discussions/2026-09-23-grilling-round32.md)。仍有效的产品规则：生产 V/C 必须实质独立；禁言可申请注销但正式注销后随旧号终止；封禁期间不可注销，缓冲期内新封禁取消申请。现有生产服务尚未接入这些认证路由；隔离包已实现发码、确认、账号创建和初始会话签发。
- 注册验证码申请的邮箱枚举保护已确认：格式和域名合规的申请对配额状态返回相同受理状态及通用提示；验证成功后才可能签发新号资格，不得返回已有账号或恢复旧号。实际投递、时延、限流侧信道及用户名登录枚举风险仍待安全评审。
- 2026-09-26 用户选定“校园资格与旧号控制权分离”的架构方向：恶意 V 可伪造新资格或阻止注册，但不能只靠邮箱接管已有账号。V 持邮箱→槽位，C 受限认证库持槽位→账号；共同槽位使串通可直接关联。旧 [GPT-6 交接](auth-privacy-gpt6-handoff.md)仅作为问题背景，当前可执行决策见[认证与隐私架构决策](auth-privacy-architecture-decision.md)。
- 2026-09-27 完成注册、退役与释放的[协议 v1](auth-privacy-registration-protocol.md)：槽位由客户端一次性公钥散列导出，C 验真实挑战的持钥证明；私钥丢失时先退役未开户旧槽位，正式注销后 C 保留最小终态拒旧票重放。协议尚未实施或经过独立安全审计；恢复体验及数据库/API 的规格见下条进展。

- 2026-09-27 完成[独立恢复策略](auth-privacy-recovery-decision.md)与[逻辑数据／API 契约](auth-privacy-data-api-contract.md)：恢复码注册前确认，Passkey 可选；全凭据丢失则旧号与同邮箱配额都无法找回。V 当前槽位全局唯一，C 关闭与释放事件共事务；注销状态秘密须申请前保存。仍未实施或通过独立安全评审。

- 2026-09-28 完成[内部跨方威胁模型](auth-privacy-threat-model.md)与规格复核：注册资格升级为限时 `REGISTER/V2`，严格校验持钥公钥；重设意图须原子替代且旧凭据证明在账号锁内复核；注销截止使用取锁后的数据库实际时间，申请后取消尚未公开的任务；登出及重设未知结果有重启后的安全核对路径。灾备还须守住时钟与受信钥单调性。该威胁建模轮次只改文档；当时 OpenAPI／迁移及其他门槛未完成，后续规格进展见下条。

- 2026-09-28 完成[V的5个操作](../../packages/openapi/verifier-auth-api.yaml)、[C的22个操作](../../packages/openapi/community-auth-api.yaml)和[数据库迁移设计](auth-privacy-database-migration-design.md)：固定二进制票据、独立16B安装ID／32B操作键、原结果核对、恢复管理、同令牌续期和内部mTLS边界均有机器可读schema；表约束、锁顺序、签名outbox、留存及演示会话升级顺序已写清。幂等原结果到期原位收缩为无身份永久摘要锚点，迟到旧操作不能重执行。三份OpenAPI通过完整规范静态校验；未创建／执行认证SQL，未写认证代码，未通过独立审计。该轮之后的向量与评审包进展见下条；双主体运营和真实客户端／迁移证据仍待核实。

- 2026-09-28 完成[固定协议向量与内部静态复验](auth-privacy-protocol-vectors.md)及[独立安全评审输入包](auth-privacy-security-review-package.md)：8组协议有效签名、3组RFC控制在PyNaCl1.6.2与Node24.11.1/OpenSSL3.5.4中逐字一致，11组错误签名拒绝。4组裸验签弱点反例说明库Verify不能代替公钥准入；明确A/R均规范、非单位元且处于主素数阶子群的项目配置。22组点、规范编码、域分离及时间算术已核对；12组事务案例未执行，独立审计未开始，未写认证代码或SQL。下一步确定实际评审者和V/C运营关系；获实施授权后以最小SQL约束、注册／退役竞争及提交后签名outbox产生真实证据，避免继续只扩文档。

- 2026-09-28 将19份认证评审材料锁定为提交 `41fba7761035ee5aafb0e3beb55bf7b8d21f539a` 的[送审快照](auth-privacy-review-snapshot.json)，导出逐文件哈希与压缩包并核验来源；[评审包登记](auth-privacy-security-review-package.md)已填入可自主确认的版本项。用户报告学校邮箱可用；已解释V是验证码与注册配额服务、C是Hnuhole后台、独立评审者是未参与设计的安全工程师或机构。V/C具名运营安排与独立评审仍待确认，不能因有校邮账号即认定V已独立运营。未外部发送、未签署独立结论，未进入认证编码；下一步先明确服务搭建和权限安排，再落实真实评审，新增模板不能补齐这些事实。

## 当前阶段

- 2026-09-28 将修正后的21份规格／评审材料锁定到 `05dc4a4b88797f5532829c1f2953484f7ac86c90`，形成[新快照清单](auth-privacy-review-snapshot.json)及逐文件摘要／压缩包；旧 `41fba77` 初审快照保留不改。新包包括退役ACK修正、AI交叉评审和本轮接口静态记录；版本登记补充不改已锁定协议或向量。实际SQL／服务和G1–G6缺失证据仍未验收。

- 2026-09-28 根据用户确认登记邮箱可用、C 正式后台未建、暂无人类独立评审者；完成不继承前文的新上下文 subagent 初审并记录[AI 交叉评审](auth-privacy-ai-cross-review.md)。确认并修正 RETIRED 收据缺少 V 持久 ACK 的规格闭环，新增内部退役收据入口，V 当前 6／C 22 个操作；保留原固定签名帧与向量。拉取／推送、原确认续办、重签、单调 ACK、清理与灾备均补入验收。评审 agent 对实际补丁回归复核结论为规格阶段 APPROVE WITH NOTES；三份 OpenAPI 结构及新请求／ACK Schema 已[静态核对](../../packages/auth-protocol-vectors/retirement-ack-static-verification.json)。Claude 九份固定源材料披露已获授权，调用因本机 CLI 未登录失败，没有模型评审结果；用户随后决定本轮先不做 Claude，采用 subagent 规格评审，不再等待外部登录。实际 SQL／服务、独立运营证据和人类第三方结论未验收，本轮未写认证代码。

- 当前新图（2026-09-21）：长按对方图片 M v1 重试生成成功，待评审；黑底灰青，同组两图仅单张选中，菜单删除／举报。无新增业务，额度失败不再是当前阻塞。
- 最新定稿：首发身份选择 L v2 紧凑弹框，已归档；L v1 大字大框被否决，灰褐不锁全局。J v2 居中撤回＋重编辑已确认，点击直接回填，不自动发送；K 回填图不再制作，替换确认不再提问。重编辑期限与本机临时原文清理仍待细化。
- 本轮定稿：长按本人文字 I v1 页面经用户“可以，下一个图”确认，复制／删除／两分钟内撤回结构有效，灰橄榄不因此锁为全局配色。
- 已认可的候选配色：长按对方文字 H 的黑灰＋低饱和蓝灰，用户明确要求纳入考量，未锁定全局主题；后续新图仍须换色。该答复未额外声明整页定稿。
- 此前试稿：首次私信等待回复 G、举报进度森林绿 v3 与陶橘暖砂 v2 均待明确评审；正常聊天 F 配色被否决为花哨，不作主题基准。
- 举报进度旧 E 版只改小图标被否决；C v2 已修订左右聊天，D v1 证据预览已交付。举报进度仍从系统通知进入，不改变提交后返回原页的规则。
- UI 评审同步检查业务影响；收到的 v2 图稿及对方头像／昵称随整条提醒回原帖已确认，消息与私信模块已同步；身份隔离、未读及固定身份回复规则不变，详见[评审记录](../discussions/2026-09-20-replies-ui-review.md)。
- 首版标题手写、文字搜索；旧生成和意图理解方案已清理。首版无视频、投票、聊天迁移或交易功能。
- 注册邮箱固定后缀、允许前缀别名、禁止空格、区分大小写；资格无周期复核。日常用户名密码登录、独立凭据恢复、单设备和三十天会话已定。
- 发帖可取消上传发布；旧帖编辑退出丢弃修改。评论回复关系可跳转、本人成功滚到评论区域顶部、分页约五十条已定。
- 离线待收持续保存到本地确认；首次保留图片入口并在发送时限制。热榜整五分钟更新、权重不公开已定。
- 第二十轮十项已确认：私信不备份导出、未发送文字本地保留、正文可搜、图片可主动保存、推送范围、拉黑在途消息、举报进度、删帖无回收站、通道热度删除口径、浏览量不参与排名。第二十一轮已收口：不做交易、违规昵称头像可重置、下架帖不允许整改重审；分类专项也已收口。UI 设计暂缓；认证主链当前只推进实施前规格化与安全评审。

## 模块现状与剩余

| 模块 | 已确认主干 | 尚需处理 |
| --- | --- | --- |
| [账号](modules/accounts.md) | 每次注册校邮验证、用户名密码登录、恢复码必配与可选 Passkey、资格协议 v1、逻辑数据/API 契约、内部跨方威胁模型、V/C OpenAPI与迁移设计、固定向量和评审输入包、单设备、三十天会话、七天注销 | 契约／实际SQL审阅、移动端 Passkey 适配、两组织运营安排、独立安全评审 |
| [身份](modules/identity.md) | 一至三个、服务端接受任务时绑定、同帖主评论/楼中楼回复复用、字符校验及十二字上限、删除范围 | 资料编辑交互、默认头像、输入法实现、图稿 |
| [导航](modules/navigation.md) | 七通道、默认五通道、两次任务的二维导航树边界 | 内容接入、文字搜索分组排序、历史范围及同步实现、最终树形视觉 |
| [标签](modules/tags.md) | 通道必选、#标签选填、无中间分类与统一治理；主题屏蔽后续设计 | #标签输入、筛选画面与检索实现 |
| [热度](modules/popularity.md) | 七天前二十、整五分钟刷新、权重不公开、浏览量只展示、通道删除后按有效内容重算 | 权重及衰减值、无数据呈现 |
| [发帖](modules/post-composer.md) | 标题手写、图片齐全公开、可取消、失败处理、新帖草稿 | 取消/发布并发实现、存储和正式图 |
| [详情](modules/post-detail.md) | 分屏可调、头像联系、图片查看、主动保存相册、赞藏反馈 | 点赞未知同步、图稿和屏幕适配 |
| [评论](modules/comments.md) | 分层删除、无引用块、对象定位、成功滚顶、约五十条分页、图片失败保文字 | 评论分页实现、输入法和图片状态图 |
| [消息](modules/messages.md) | 身份隔离、站内分类、预览开关、隐藏恢复、备注与正文搜索、推送范围 | 消息子页图、目标失效与陌生会话细节 |
| [私信](modules/messaging.md) | 首条文字限制、自动本地保存、未发送文字本地保留、补收与撤回规则 | 聊天页设计、保存格式与加密 |
| [我的](modules/personal.md) | 两页签、分别空状态、草稿混排、返回保位、删帖无回收站 | 卡片与设置图 |
| [管理](modules/moderation.md) | 处罚申诉、证据授权、待复核、举报进度、拉黑在途消息、旧帖编辑丢弃修改 | 证据保存期限、审核网页 |

## 继续顺序

第二十二轮业务主干已收口；用户确认屏蔽留到后续版本。UI 讨论暂缓，任务 1 的通道功能骨架可依既有工程决策维护；认证主链须先完成上方的实施前规格化和独立安全评审。旧 UI 评审记录仅用于追溯，不作为当前认证决策依据。

## 剩余图稿按八组推进

新增图稿包括消息身份切换展开 v1、v2，评论与回复收到的 v1、v2，以及我发出的正常状态 v1 和失败状态 v1。身份切换 v2、收到的 v2 与我发出的正常状态 v1 已确认；失败状态 v1 已作废，旧稿保留用于追溯。图片数量不等于完整流程已定稿数量。

1. 入口、登录与导航树。
2. 通道列表、筛选、搜索历史、热榜和结果。
3. 发帖编辑、确认、身份选择和图片状态。
4. 消息首页主布局、身份切换展开 v2、收到的 v2、我发出的正常状态 v1、系统通知失败详情 v1、顶部失败提示 v1、系统通知时间流 v2、举报处理结果详情 v1、违规处理通知详情 v1 已确认；旧分类列表及原发言列表内失败稿作废。
5. 私信聊天、首次联系、图片和失败状态。
6. 我的、收藏、草稿和设置。
7. 手机端举报、通知和申诉：待复核详情、结果通过、结果未通过 v1 已确认；首次提交 v2、补充材料 v1、举报原因配色 A v1 已生成待评审；电脑网页审核管理后台仍待设计。
8. 已有阅读、分屏和回复图同步新规则，补关键异常状态。

组数不等于页面数。当前按[UI 评审记录](../discussions/2026-09-20-replies-ui-review.md)推进申诉流程；旧稿仅作对照。

## 后续工程工作

认证主链已有规则、协议、恢复、数据/API、威胁模型、OpenAPI 和评审材料，并已按用户授权进入隔离实现：槽位／开户／ACK、校邮确认、原确认续办与 HTTP／mTLS 的证据见[资格报告](auth-privacy-eligibility-http-validation-report.md)；登录、会话接替／续期／撤销及 Gate 故障验证见[会话报告](auth-privacy-session-lifecycle-validation-report.md)；恢复码重设、七天注销、截止裁决与受信封禁联动见[恢复／注销报告](auth-privacy-recovery-closure-validation-report.md)。下一切片补齐恢复码轮换与可选 Passkey 的凭据管理，再串联移动端持久待办、设备通知与生产授权。每次实现提供必要的真实事务／故障验证；生产接入仍须完整迁移、可信灾备、运营权限事实与独立安全验收。旧 [ADR 0005](../adr/0005-privacy-preserving-email-authentication.md)不再是实现规范。

随后按任务 2 接入文字内容主链，再安排身份/内容/会话数据关系、可见性和账号去重等验证、联调内测与分发上线。这部分须单独估算，不把设计成熟度当成上线进度。
