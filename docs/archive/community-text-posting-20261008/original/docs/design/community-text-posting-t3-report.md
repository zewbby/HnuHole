# 文字社区 T3 Flutter 与本机业务状态交付

日期：2026-10-08（Asia/Shanghai）。工作树 `C:/Users/Administrator/.codex/worktrees/community-text-posting/HnuHole`，分支 `codex/community-text-posting`，本轮开发基线 `0879dfda1df075e752d8e168c30aa25bf342445f`；T2服务端源码提交为 `0644f5ae5ef0c92ae99ed81fd40dac97ed447bc3`。当前T3尚未提交、推送或部署。机器结果、最终源码指纹及完整执行数量由[总记录](community-text-posting-t3-verification.json)登记；本轮最终Flutter分析和279项mobile测试通过；分层证明范围及未执行项以下列记录为准。

用户本轮授权“做T3”，本会话已实际实现Flutter文字页面、HTTP适配、发布状态机及独立加密业务SQLite。原并行 `codex/community-flutter-pages` 任务当前负责产品图审核，其实现未作为本工作树的源码或运行证据。这里保留T1/T2原职责与被测版本的历史记录；本轮客户端实现以当前源码为准。确认／任务／我的／详情产品视觉仍在独立任务审核；3张实际Flutter渲染图已逐图查看，无可见裁切或溢出，这项布局核对不等于产品视觉已批准。

本轮范围仍是文字闭环。图片、标签交互、评论、赞藏、搜索、私信、推送、热榜、作者编辑及完整治理后台未开发。当前有Flutter实现和分层测试证据，完整手机App到实际C/V、原生业务存储跨进程及生产验收仍属于T4，均未以本轮替身结果计为通过。

## 1. 真实源码与测试位置

| 范围 | 实现位置 | 测试入口 |
|---|---|---|
| 14操作HTTP适配、严格JSON/DTO、错误及会话截止元数据 | `apps/mobile/lib/src/posts/http_post_api.dart`、`post_api.dart`、`post_models.dart` | `apps/mobile/test/post_api_test.dart`、`post_models_test.dart` |
| Unicode16字素、原文保留和命令摘要 | `apps/mobile/lib/src/posts/post_protocol.dart` | `apps/mobile/test/post_protocol_test.dart`；共享 `packages/post-protocol-vectors/` |
| 原操作持久、恢复／核对、取消／retry／hide、本人混排和分页 | `apps/mobile/lib/src/posts/post_controller.dart` | `apps/mobile/test/post_controller_test.dart` |
| 通道最新列表、编辑／确认／身份返回、个人内容、任务与详情 | `apps/mobile/lib/src/posts/post_screens.dart`、`post_theme.dart`；`apps/mobile/lib/main.dart`、`hnuhole_mobile.dart` | `apps/mobile/test/post_screens_test.dart` |
| 独立Drift／SQLite、认证加密payload、CAS、闭号墓碑和终态压缩 | `apps/mobile/lib/src/storage/post_store.dart`；`apps/mobile/pubspec.yaml`／`pubspec.lock` | `apps/mobile/test/post_storage_test.dart` |
| 独立原生业务密钥、noBackup路径及单账号擦除 | `packages/auth_vault/lib/hnuhole_auth_vault.dart`；Android `AndroidAuthVault.kt`、`AndroidBusinessStorage.kt`、`AuthVaultPlugin.kt`；iOS canonical `AuthVaultPlugin.swift` | Android `AndroidBusinessStorageTest.kt`；原 `AndroidAuthVaultTest.kt`、`AuthVaultProcessRestartTest.kt` 编译回归 |
| 原账号权威闭号后的本机业务清理 | `apps/mobile/lib/src/auth/auth_flows.dart`、`auth_state_codec.dart`；`main.dart`接入回调 | `apps/mobile/test/post_closure_cleanup_test.dart`及原 `auth_flows_test.dart`／`auth_vault_test.dart` |

SQLite不保存Bearer、密码、恢复码或定向撤销秘密。业务密钥位于独立原生命名空间，数据库按环境＋账号scope隔离；标题、正文、全部提交payload、commandId与digest均以AES-GCM认证密文落盘，命令唯一索引只保存用途隔离的HMAC。AAD绑定环境、账号、scope、逻辑项目、schema、revision和state。已有数据库缺钥或钥不匹配时拒绝打开，不能静默换钥重建。

Android数据库及包裹密钥记录在 `noBackupFilesDir/hnuhole-business-v1`，Keystore alias为独立业务前缀。iOS业务Keychain service与认证文档独立，使用非同步、ThisDeviceOnly项，数据库／安装marker／闭号marker目录排除备份。以上是已实现的原生源码边界；当前Dart内存vault测试及Kotlin编译不证明设备上的Keystore、Keychain、备份或持久性。

## 2. 已实现的用户流程与状态边界

- 通道真正进入所属最新列表，卡片只显示标题、作者和发布时间；正文只在详情显示。未实现的评论、赞藏、图片、搜索等入口不展示可点击占位。
- 编辑页可先填写正文；下一步进入确认页，返回保留原文字。零身份用户通过既有身份设置返回原确认步骤，不自动发表。输入组合态、文字计数和正式验证分别处理。
- 加号新建独立草稿；有内容退出先完成持久保存，空白新稿不新增记录。写入失败保留编辑页和输入，提供重试、复制、明确放弃。多个草稿可以关闭／重开SQLite后恢复。
- 发布前原子保存原command、operation、精确payload、digest、身份及逻辑项目，然后才请求服务端。丢响应、401、冻结或进程重建不把UNKNOWN变成新草稿；原账号恢复后先核对原操作，不擅自另发或换身份。
- 原受理回执与任务当前状态分别读取。处理中按原任务核对公开结果；取消、封印、失败重试、隐藏和删除使用各自持久原命令。跨设备导入任务和维护锚点直接原子创建非草稿项目，不经过可换身份草稿中间态。
- 失败重试保留原通道和帖内身份，编辑缓冲按固定任务／版本独立保存；UNKNOWN重试不能开启第二次发表。未受理CREATE仅在权威封印／拒绝后由用户明确恢复新草稿或放弃；服务端查无本身不等于未提交。
- 成功截止元数据先经AuthStore持久确认，再公开响应内容。旧账号或旧authority的迟到网络响应不能续期当前账号或写入其SQLite。正文页和删除确认在authority变化后遮蔽或停止。
- 正式帖由权威本人列表确认资格；已删除身份旧帖不能由本机PUBLISHED缓存补回“我的”。作者删除从权威capabilities进入，丢删除响应先核对已存原命令，不因capabilities变404新造删除键。
- 明确PUBLISHED／CANCELLED／HIDDEN／DELETED／CONTENT_UNAVAILABLE压缩本机全文，仅保留不可变防重事实；NOT_ACCEPTED压缩还要求调用方先得到用户明确放弃。未决操作保留精确原payload。
- 申请注销、PENDING、FINALIZING、CANCELLED不清业务。`CLOSED_RELEASE_PENDING`／`RELEASED`在认证vault中保留原账号私有归属并回调该账号，清理故障保留标识供重启重试；普通退出、401、冻结不触发清理。闭号scope永久墓碑阻止迟到写和重开，新账号不继承旧数据。

## 3. 实际检查与证明范围

| 检查 | 本轮结果 | 范围与限制 |
|---|---|---|
| 最终Flutter analyze与全量mobile测试 | PASS：No issues found；279/279项，exit0 | 当前源码；原179项认证回归＋本轮100项分层测试。详细文件计数见 `community-text-posting-t3-test-summary.json`，旧版本PASS不代证本轮 |
| 业务SQLite存储专项 | PASS：22项 | Linux真实文件SQLite 3.45.1、Drift2.35.2／sqlite3 Dart3.7.0；重开、多草稿、两个连接CAS、SQL触发器写故障回滚、AAD／密文损坏、scope越权、缺钥拒绝、闭号墓碑／迟到写、终态压缩。BusinessKeyVault是内存替身，未测原生设备 |
| 闭号本机清理专项 | PASS：11项 | AuthFlows／codec／内存AuthVault；非终态不清、权威闭号只清原账号、故障／重启／fresh forget／迟到forget竞争、legacy不猜owner。非真实C/V，不代证服务端闭号 |
| 闭号＋既有auth_flows／auth_vault聚焦 | PASS：35项 | 同一当前源码的Dart回归；认证状态和存储fault测试，不是系统安全存储或完整手机App |
| 存储／闭号当前Dart analyze | PASS：No issues found | `post_store.dart`、`post_storage_test.dart`、`post_closure_cleanup_test.dart`的最终聚焦检查 |
| HTTP严格适配／摘要／DTO／controller／widget | PASS：14／8／7／22／16项 | 源码入口在上表；HTTP用loopback实际TLS测试端点，controller用真实SQLite＋替身PostApi/AuthVault，widget使用测试controller。不得登记为实际C/V→SQL→App通过 |
| Android vault生产＋instrumentation Kotlin源码编译 | PASS：6个文件，exit0、无warning | 直接Kotlin2.4.0 CLI、Android SDK36、Flutter embedding及现成只读依赖；生产3文件和测试3文件均编译。非Gradle APK、测试未在设备执行 |
| Flutter实际页面PNG与人工布局核对 | PASS：额外1项渲染、3张图均实际查看 | 390×844逻辑尺寸、2倍输出；列表、编辑、我的均无可见裁切或溢出。证据在 `evidence/community-text-posting-t3/`；产品视觉批准／物理设备显示另验 |
| Android／iOS业务vault与完整App、T4真实C/V链路、生产 | NOT_RUN | 原因及下一入口见下文 |

本轮修改了共享认证workflow codec、闭号清理回调及native vault装配，必须重新打开A08/A10/A12/N01等受影响平台回归。旧AC04／AC05 Android、Passkey、跨进程、iOS记录保留原SHA和证明范围，不能因为本轮Dart通过或旧设备通过就把新业务原生存储计为PASS。T2真实Go／SQL／R03证据仍按T2原源码版本阅读，本轮未重新执行或扩充服务端数据库验收。

## 4. 本轮失败、审查修复与保守处理

1. 初次依赖固定为 `characters 1.4.0` 与现成Flutter SDK的约束不一致，pub解析失败；改为SDK要求的 `1.4.1`，字素协议仍冻结Unicode16，不能只凭升级包版本声称边界相同；`post_protocol_test.dart`保留共享向量及全部1093官方案例。
2. sqlite3 3.7.0默认GitHub预编译Linux库下载在 `release-assets.githubusercontent.com` 超时。官方hook支持Linux system来源，手机维持默认bundled来源；本机仅有 `.so.0`，首次system loader仍找不到 `.so`。最终在本任务专用目录建立软链并以 `LD_LIBRARY_PATH` 加载现存系统SQLite3.45.1，真实存储专项通过。未装SDK、改系统库或把替身替代实盘。
3. 存储／controller交叉审查补齐原子维护锚点：跨设备FAILED任务和DELETE操作不能先生成普通草稿再提交，否则中断可造成固定身份丢失；`createSubmitted`单事务创建及SQL失败回滚有实盘测试。
4. 闭号审查补齐永久scope墓碑与native单scope清理；已有钥不能被首次并发创建覆盖，丢钥的正式闭号仍可清理。普通退出／冻结保留业务数据，原账号清理不删除新账号资料。
5. `forgetClosureStatus`原来依赖内存 `_store.current`，重启后直接forget可能跳过业务清理。现在先读持久记录，再等待原账号清理，并在删除标识事务复核closureId；fresh启动、清理故障、vault写故障和迟到forget竞争均由11项专项覆盖。
6. 修复编辑UI擅自递增数据库revision、取消／重试命令未受理误隐藏原任务、重试缓冲不落盘、原始postId丢失、retry缓冲误当维护锚点及SQLite结果写入前发布内存状态；UNKNOWN／seal／旧authority／正式帖子资格／终态正文清理进入当前源码与测试；最终22项controller及16项widget已PASS；含旧CANCEL回执不得回退新尝试、NOT_ACCEPTED RETRY保留原FAILED、原意图写入及结果UPDATE故障、retry缓冲排序、权威最新顺序和分页cursor、原账号迟到响应。

7. 新发布采用权威latest页顺序合并，不把历史PUBLISHED回执顶到首位；My本人资格由本人task归属和当前公共作者状态核对，不能用第一页缺席或canDelete代替。身份管理返回刷新已加载投影而不重置游标；My发布同通道复用现有route，异通道回entry后打开目标。controller排序／游标测试通过；完整App设备路由仍T4未验。

## 5. 模块与跨模块映射

| 模块 | 本轮实现／证据映射 | 当前未验与下一步骤 |
|---|---|---|
| B02 | 确认页有效身份选择、零身份设置返回、固定绑定任务的重试；controller/widget | 认证最终候选＋真实身份API／设备IME；完整身份业务模块不PASS |
| B03 | 真实通道导航、最新卡片／翻页、标题无正文摘要、插入新帖保留锚点 | 实际C分页、设备滚动与返回位置；热榜／搜索等仍待开发 |
| B05 | 编辑／确认、多草稿、持久原命令、UNKNOWN／seal／取消／retry／hide | 实际C/V＋SQL＋Dart丢响应、杀进程、冻结和生命周期；图片／标签另片 |
| B06 | 正文详情、当前作者投影提示、删除确认及旧authority遮蔽 | 真实HTTP身份变化／删除结果、完整App设备；评论等未实现 |
| B10 | 正式帖／草稿／任务混排，原操作核对，草稿恢复与明确删除 | 设备跨进程、真实本人资格及关闭清理；完整个人内容模块不PASS |
| A01/A03 | 当前Bearer、成功元数据先持久、旧authority迟到响应阻断 | 本轮PostApi替身/loopback不测最终C Gate；T4实际授权回归 |
| A06 | UNKNOWN原键／摘要恢复与封印、禁止隐式重发 | 原生跨进程＋真实C故障链；T2历史SQL回执证据保持原版本 |
| A08/A10 | 原账号闭号private owner／codec、非终态不清、失败重试与scope墓碑 | 当前11项Dart＋SQLite证据；native device和实际闭号worker联调待验 |
| A12/N01 | 业务独立vault namespace、认证加密SQLite、noBackup、CAS、缺钥拒绝 | Android instrumentation5业务场景未执行；完整App／跨进程／备份恢复及iOS待验，旧native结果不能代证 |
| A13 | 14操作客户端契约、严格公开/本人DTO、固定origin、拒绝响应不续期 | 实际C handler与完整App集成；不把loopback test server当正式服务 |
| X06/X07 | 公共作者DTO与本人任务分隔、无共同账号字段，原账号终态清理 | 独立匿名/权限审查、所有业务消费者及生产隐私边界待验 |

逐模块机器台账由 `currentCommunityTextT3` 指向当前源码／结果；所有完整模块和全体CP均不自动升为PASS。CP01–CP04／CP06–CP14本轮取得的是列明客户端层证据；CP05/07/09–12/15的T2服务端证据仍保留其版本。CP14真实原生跨进程、CP15完整App到实际服务以及设备／生产部分继续NOT_RUN。

## 6. 复验入口与所需环境

终端：WSL `Ubuntu-24.04`。工作目录为本工作树的 `apps/mobile`；使用现成 `D:/zewbbyTest/Hnuhole-env/linux/flutter`（Flutter3.47.5／Dart3.13.4），本片专用 `PUB_CACHE=/tmp/hnuhole-community-t3-pub`。不要复用认证验收任务的数据库、代理、Gate、APK、AVD运行磁盘或命名空间。

```sh
export PUB_CACHE=/tmp/hnuhole-community-t3-pub
export PUB_HOSTED_URL=https://pub.dev
export LD_LIBRARY_PATH=/tmp/hnuhole-community-t3-sqlite-test-lib
export PATH=/mnt/d/zewbbyTest/Hnuhole-env/linux/flutter/bin:$PATH
cd /mnt/c/Users/Administrator/.codex/worktrees/community-text-posting/HnuHole/apps/mobile
flutter pub get
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
# 仅存储和本机闭号专项；没有虚构 --module 选项。
flutter test --no-pub test/post_storage_test.dart test/post_closure_cleanup_test.dart --reporter expanded
```

Linux测试加载目录只含指向现存 `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0` 的 `libsqlite3.so` 软链。清理后复验先确认系统库存在，再在本任务专用目录重建软链；其他系统路径或架构需用实际存在的系统库，不能把本机环境路径当手机原生库。Android／iOS仍走默认校验下载的bundled SQLite，当前未构建其资产。

实际页面渲染测试在 `post_screens_test.dart` 中，由 `HNUHOLE_UI_RENDER_DIR` 开启；可选 `HNUHOLE_UI_RENDER_FONT`／`HNUHOLE_UI_RENDER_ICON_FONT` 只读取现成字体供截图，不变更App资产。普通全量widget测试没有渲染变量时不执行这条额外输出场景。本轮开启该入口的17/17 widget＋render通过，3张图已实际查看；截图使用脱敏替身数据，不能称产品图已批准。

Kotlin直接CLI编译使用现成compiler jars、SDK36、Flutter embedding和测试依赖，没有独立保留的仓库runner；临时输出已删除。Android完整复验需执行标准Flutter APK构建和真实 instrumentation／跨进程测试，不能把这个编译记录改写成Gradle APK／设备测试通过。iOS须有完整macOS／Xcode／设备环境，当前没有可执行结果。

T4真实链路仍从现有 `services/api/authlab/run-mobile-isolated.sh` 的认证runner框架接入；帖子业务Dart故障场景和完整App到真实C/V的入口需补齐后执行，不能拿既有认证R05或本轮loopback TLS结果代证。固定认证最终候选、新旧共享边界差异及独立设备窗口未完成，本轮不占用正在验收的环境。

## 7. 剩余验收与收尾

- NOT_RUN：固定认证候选整合后的实际C/V→PostgreSQL→Dart／完整手机App；真实丢响应、后台worker、冻结／恢复、账号接替及闭号设备故障链。
- NOT_RUN：Android业务vault5项instrumentation、业务SQLite原生跨进程／杀进程、系统备份恢复／卸载重装／锁屏／低磁盘；完整APK及生产发布签名。
- NOT_RUN：iOS业务Keychain、SQLite排除备份及closed marker、SwiftPM／CocoaPods完整链接、设备跨进程和AuthenticationServices共享回归。
- 产品视觉审核：NOT_RUN，仍由独立任务与用户确认。PNG逐图检查PASS，当前全量279项PASS；清理结果见总记录，不把布局检查当真机或最终视觉批准。
- NOT_RUN：独立安全／匿名边界审查、历史容量、7天应用清理SLA、监控、WAL／备份／恢复、授时／锚点／操作员及生产运营。未开发模块保持NOT_STARTED，不改成只差测试。

本任务只保留源码、测试源码和小型脱敏记录。存储test自建SQLite、Kotlin临时输出／展开依赖及Windows helper已清理；专用pub cache、loader软链、Flutter build/.dart_tool及大型JSON日志按明确归属清理；仅保留3张小型脱敏布局PNG、源码和结构化计数／指纹记录，最终清理状态写总记录。现成SDK／AVD、认证任务资源、未知Docker卷及用户数据保持原归属。

总交接入口为[模块交接](module-acceptance-handoff.md)、[台账](module-acceptance-ledger.json)、[HANDOFF](HANDOFF.md)、[progress](progress.md)及[计划](community-text-posting-plan.md)。T3实现不构成提交、推送、部署或生产授权。
