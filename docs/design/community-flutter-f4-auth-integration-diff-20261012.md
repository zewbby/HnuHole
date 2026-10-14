# 2026-10-13 固定认证候选整合差异

> **本轮已提交比较快照：**C2=`b5accf36b90e27829b6d039cd58a5b9c189a3da8`，D=`d859cb05c772cdf8d8b75e439a2bfedf0414dd46`，M=`28cee4656edd710d60676a81794c20cd49f45351`。C2 已正常推送且远端一致；下述后续差异固定到 C2，不使用未提交认证源码。

> **2026-10-15 后续差异：**固定认证 D=`d859cb05c772cdf8d8b75e439a2bfedf0414dd46`，已整合产品 M=`28cee4656edd710d60676a81794c20cd49f45351`，本轮起始 P=`01ea1a13b89aac8bf76e5ab7eb20eca4fb2662ee`。相对 M/P，只增加 post_controller 的 DELETE 原结果轮询登记和 auth_screen 对 C 已确认 CANCELLED 的显式完成入口，以及对应测试/验收工具。main/settings、AuthFlows、session/HTTP、closure 协议、原生 vault/passkey、manifest、SQL/权限和锁字节不变。回归与450项输入见[准备报告](community-android-stage1-preparation-20261015.md)，本轮发布固定 SHA 见 Git 回执；未取认证工作树或浮动基线。

当前用户已明确指定认证 **D=`d859cb05c772cdf8d8b75e439a2bfedf0414dd46`** 用于单台Android范围整合，不再等待第二实体Android。社区整合前成果已审查为20个源码／测试／脱敏交接文件，保存并正常推送 **S=`7452dadefb52e7b695cdd1079d21083fcb6cae02`**；原起点 **C=`4d58116bdde2c1d2d406b965590bc1625a5c7955`**，共同祖先 **B=`0eff47a21cd4f4ab1636b4468f7d5df9769a264f`**。下面2026-10-12静态差异是历史快照，原“最终SHA未指定”已由本次用户指令解除。

D的认证候选边界为固定24项 **22 PASS／0 FAIL／2 BLOCKED**，B6及不需第二实体Android的范围PASS；NI-X01／NI-X02、iOS、生产未通过。389项原产品输入与378项最终源码/工具快照通过固定Git对象核对，三个原交接检查器均在D的独立Git对象副本通过，未改变检查器。iOS Classes路径在Git中为符号链接：Windows原证据记录的是link文本blob；初始Linuxarchive读取了link目标，导致摘要失败。静态材料核对以精确Git blob及独立临时索引复验，未改写旧证据，也不作为iOS执行通过。详细小型外部记录在 `E:/HnuHole-community-f4-20261012/integration-20261013/logs`。

整合采用 `git merge --no-commit --no-ff D` 的三方比较，未整枝覆盖、未访问认证会话变化中的工作树。实际冲突是main/settings和HANDOFF/module handoff/ledger/progress；AuthFlows合并后逐项核对。当前联合主机七stage（mobile320、R05、F4-H01–08、六包server、posts权限、实际cmd/迁移R03、最终vet）及Android构建已PASS，详见[联合报告](community-auth-integration-report-20261013.md)/[机器记录](community-auth-integration-20261013.json)。设备窗口用户明确延期，原生/物理设备实际运行NOT_RUN；整合前mobile311及认证22项保留自己的原版本，不计联合证据。整合后源码28cee4656edd710d60676a81794c20cd49f45351已正常推送，见[Git交付回执](community-auth-integration-delivery-20261013.json)；三方差异的比较SHA仍为本页固定S/D/B。

| 范围 | S→D / B→D审查与本次整合决定 | 联合复验 |
|---|---|---|
| main/settings | 保留公开HnuholeApp、MobileEnvironment在开库前校验、社区主导航和“账号与安全”现有布局；候选debug私有CA客户端接入目录、认证及帖子三类请求，RP只由显式合法配置注入；Settings回调仍可选、实际根必定提供 | 完整mobile、F4根路由、原生实际main启动 |
| AuthFlows | 保留D的显式过期OTP重验、禁止C未知commit/ticket或已有session/reset/closure时重发；保留社区originalAccountId、权威关闭回调、forget并发检查和codec字段 | flows/widget、R05、闭号清理和账号隔离 |
| session/HTTP | session/store相对B未改；纳入D固定RP、byte-limit、合法大attestation及受信签名digest别名；保留禁止redirect/cookie/POST自动重试和所有帖子HTTP路由 | HTTP／Passkey负向、全Go race、R05 |
| closure | 社区Dart owner codec／业务purge和服务端帖子stop/receipt/cleanup成组保留，权威正式关闭后清原账号；冻结／退出／未知不清库 | controller／SQLite、真实formal closure SQL、F4-H08 |
| vault/passkey | 保留社区业务key/path/closed tombstone与多engine临界区，纳入D原生Passkey状态、错误分类及实际进程测试；没有用D不含文字模块的vault覆盖社区扩展 | 两插件分析、Passkey Dart及JVM、Android native7／原生请求与重启 |
| manifest/build | 保留D的allowBackup=false/fullBackupContent=false及Android12+所有数据域排除，覆盖文字数据库/key；debug诊断Activity及compileOnly固定版本保留，release不能带诊断类或开发入口 | 标准Debug／Release、manifest／DEX边界；OEM跨设备仍不验 |
| SQL/permissions | D相对B无正式迁移／授权文件增量。保留社区0013、隐私白名单、此前批准的29行最小c_posts授权和锁文件；不回退schema、不放宽权限 | server、真实posts runtime正/负权限、R03实际cmd及旧版本前向升级 |
| 设备测试入口 | 已有纯认证fixture的root类型、账号tile及My→设置导航适配当前公开社区根；仅测试入口变更，无页面重做。原设备版本不会因此升格为本版PASS | 分析／构建，取得明确设备窗口后按本版清单执行 |
| 文档/台账 | 两侧原日期／SHA／证据并存；新currentCommunityAuthIntegration重新打开共享回归，旧host311及原认证22项不换绑新指纹 | JSON／链接／最终证据与源码一致性 |

R03增加本任务root runner的 `auth-runtime` 入口，使用既有固定镜像、独立project/动态端口/新C/V库/合成材料和自身trap，不操作其他Docker资源。所有Flutter/Android SDK及JDK复制到E盘上的专用WSL工具目录，bin/cache独立，未调用共享SDK。缺少的普通构建依赖仅按既有锁定版本处理，不删除锁或升级。

本轮终点为固定联合源码的主机回归及单台Android验收；安装／设备占用／App数据影响须在构建与清单可审阅后另获明确确认。第二实体Android、iOS、生产部署、main合并及Release发布均不在本轮通过／发布范围。

---

## 以下为2026-10-12历史差异快照

# F4 认证整合差异清单（只读已提交快照）

日期：2026-10-12（Asia/Shanghai）。状态：**差异审查完成；最终认证整合 SHA 待认证会话明确交付，FP14 仍为 BLOCKED_DEPENDENCY。** 本文没有合并、复制认证未提交代码、改变认证协议或重放认证设备证据。对照仅使用本任务独立 clone 内的 Git 提交对象；本轮社区验证产生的未提交修改不属于此快照比较。

## 比较版本与候选资格

| 角色 | 精确 SHA | 本次确认的含义 |
|---|---|---|
| 社区比较快照 C | `4d58116bdde2c1d2d406b965590bc1625a5c7955` | 本次独立 clone 的实际起始 HEAD，`codex/community-flutter-pages`；含最后的设置入口修复及 F4 交接 |
| 认证共同祖先 B | `0eff47a21cd4f4ab1636b4468f7d5df9769a264f` | `git merge-base C A` 实测结果；也是原 F4 锁中的认证基线 |
| 认证已发布实现候选 A1 | `4c40f9015095ebd84dc2b17e30e6ef7ef159321f` | 认证换机交接明确列为已推送的实现／测试／排错源码；没有明确指定为最终社区整合基线 |
| 认证远端交接候选 A | `976c0048aaa40d9b7f589cb735f3bf9c47571486` | 本轮 `git ls-remote origin refs/heads/codex/auth-privacy-handoff` 实际返回；A1 后的归档／清理回执提交 |
| 固定后端来源（历史） | `514a944560988e3d8d599e6f9fe9d5d99fe07f88` | 社区 F2/F3/F4 既有逐文件来源锁，不能替代认证候选或本轮测试 |
| 最终用于整合的认证提交 | **未指定** | 不自行把 A 或 A1 认定为最终整合基线 |

A1→A 的 `git diff --name-only` 仅涉及设计交接／清理脚本及两份归档验证 JSON；`apps/mobile`、`packages/auth_vault`、`packages/auth_passkey`、`services/api/internal`、正式 SQL 迁移没有差异。因此下文 C→A 的实现差异也适用于 A1，但两者的交接内容不同。

本次已阅读社区 AGENTS、HANDOFF、F4 machine/plan/report/verification、F3 report、模块交接与台账，以及 A 内的 `auth-privacy-machine-handoff.md`、`auth-privacy-machine-transfer-20261010.md`、原认证 Git delivery。认证换机交接写明非 iOS 固定 24 项为 **19 PASS／3 FAIL／2 BLOCKED**，B6／iOS／生产未通过，且交接没有重跑完整当前 Flutter／SQL／原生回归。这些是认证自己的历史证据边界，不计入本轮社区结果。发布实现 SHA 的事实与“明确供最终整合且已完成约定回归的 SHA”不同。

## 对照方法及真正重叠

先看 B→C 与 B→A 的各自增量，再看 C→A 净差，防止把认证分支尚未包含社区文字模块的文件误判为认证主动删除或实际回归。两侧同时改动的产品源码只有以下三份：

- `apps/mobile/lib/main.dart`
- `apps/mobile/lib/src/auth/auth_flows.dart`
- `apps/mobile/lib/src/identity/settings_screen.dart`

另有 `.gitignore` 和 HANDOFF／模块交接／台账／progress 同时修改；未来整合须保留两侧证据的日期、精确版本和证明范围。其余原生业务 vault、闭号 codec、帖子 SQL／权限等是社区相对 B 的扩展；Passkey／OTP／开发 TLS 等是认证相对 B 的扩展。不能整文件替换后宣称边界自动保持。

## main/settings 与 AuthFlows

| 文件／边界 | C 快照 | A 候选快照 | 未来整合必须保留／待确认 |
|---|---|---|---|
| `apps/mobile/lib/main.dart` | `MobileEnvironment` 在开库前校验 HTTPS C/V；公开 `HnuholeApp` 与主机真实链共用；创建 `PostController`／`HttpPostApi`；闭号回调到 `posts.purgeClosedAccount`；通道页、我的、设置、身份返回刷新及账号切换围栏 | 引入 `src/development/app_transport.dart`，给目录／认证 API 提供显式 debug CA client、给认证 API 提供固定 debug RP；仍为私有 `_HnuholeApp`，通道选择为提示、个人入口到设置，不含社区控制器 | 认证负责确认开发 trust／RP 与 release guard 的最终实现；社区保留已定页面、公开测试根、帖子依赖、刷新及账号围栏。整合后对目录、认证、帖子三类 client 使用一致且合法的 trust 配置；保持原 scope 字符串字节及开库前校验，不直接复制 A 的整个 main |
| `apps/mobile/lib/src/identity/settings_screen.dart` | 新增 `onManageAccount`，“账号与安全／登录、退出与注销”，从我的→设置可达 | 也新增 `onManageAccount`，“账号与注销／退出本机与申请注销账号” | 同一功能入口文字有差异，回调签名已趋同；保留账号页可达以及身份／设备入口，按已定社区布局处理，不重做页面。最终根路由测试要覆盖这些入口 |
| `apps/mobile/lib/src/auth/auth_flows.dart`：OTP | B 上旧 OTP 逻辑，社区主要增加业务闭号桥 | 增加 `canRestartOtpVerification`；422 的 `OTP_FLOW_INVALID`／`OTP_EXPIRED`／`REVERIFY_REQUIRED` 允许显式放弃已失效 V 操作；放弃前后都校验没有 C commit/ticket、session、reset、closure | 这是认证归属的流程修复，等待指定固定 SHA 后整合并运行 auth flows／R05。保留“不因未知 C 注册结果重发”的边界；本轮不修改其协议 |
| 同文件：闭号桥 | pending closure 持久保存 `originalAccountId`；restore、闭号结果落盘、forget 前在权威 `CLOSED_RELEASE_PENDING`／`RELEASED` 状态清原账号业务库；forget 防止清理期间 closure 被替换 | 无业务清理回调、`originalAccountId` 或桥逻辑（相对 B 未引入社区扩展） | 社区负责保留此扩展。清理只针对原账号，不猜当前账号；先持久权威关闭再清理，退出／冻结／401／未知不能清库。同文件整合不得漏掉回调与 forget 竞争检查 |
| `apps/mobile/lib/src/auth/auth_state_codec.dart` | 接受并校验本地 closure `originalAccountId` UUID，旧无 owner 记录仍可读取 | 不接受这个社区新增字段；其余净差主要为格式 | codec 与 AuthFlows 必须成对保留社区字段。只从 A 覆盖 codec 会拒绝 C 已持久化闭号状态；不能用删字段／猜当前账号解冲突 |
| `apps/mobile/lib/src/auth/auth_screen.dart` | 原验证失效按钮条件 | 改用 flows 的 `canRestartOtpVerification`，不再显示原已失效验证码的继续确认动作 | 与认证 flows 同组审查／回归；不把按钮开放与 C 未知提交核对分开整合 |

## session/HTTP 与服务端认证

| 文件／边界 | 已提交差异 | 责任与复验要求 |
|---|---|---|
| `apps/mobile/lib/src/auth/auth_session_controller.dart`、`auth_store.dart` | B→C、B→A 以及 C→A 均无内容差异 | 不需要靠替换 session/store 解冲突。仍须复验冻结／恢复代次、旧会话接替、A→B 账号切换及迟到回调，因为 main／flows／HTTP 的接入变更会影响使用方式 |
| `apps/mobile/lib/src/auth/http_auth_api.dart` | A 新增可选且验证 canonical DNS 的 `passkeyRpId`；响应 RP 必须精确匹配已配置值，未配置时仍依 HTTPS API host 原规则；base64url 字段按协议字节上限派生文本上限，允许合法大 attestation；大量其余差异是格式 | 认证负责固定 RP、响应 bytes 与现有验签约束；社区负责在最终 main 注入合法配置。保持固定 HTTPS origin、无 redirect/cookie、POST 不自动重试；不得让服务器响应选 RP |
| `apps/mobile/lib/src/development/app_transport.dart`（A 新增） | 显式 CA 只允许 debug、独立 loopback HTTPS origins、有效端口／无用户信息／query／fragment；使用私有 CA `SecurityContext`，没有关闭 hostname／chain 验证；RP 要求显式 debug trust | 该文件是候选开发环境入口，不是生产 trust fallback。本任务不安装 CA／复用认证 CA 或改安全设置；最终需认证交付其 release 排除／固定配置证据 |
| `services/api/internal/authprivacy/eligibility_confirmation.go`、`verifier_gate_business_test.go` | A 在 confirmation 原键缺永久 anchor 时，只有归属匹配的原 flow 经可信时间／代次及最终 Gate 复核才返回 `REVERIFY_REQUIRED`；当前／未知 flow 仍 PENDING，不由“无 anchor”推断未提交 | 认证负责此 V 生命周期补充及对应 SQL／Gate 测试；本轮社区不修改 V 协议。整合后 R05 及受影响 verifier SQL 回归 |
| `services/api/internal/authprivacy/passkey_verification.go`、对应 test | A 从受信 Android signing digest 派生无 padding 标准 Base64 origin 别名，不改签名认证的 clientDataJSON 原字节；padding／混合编码仍拒绝 | 认证负责验签来源兼容与负向证据；社区不新增来源／RP／签名，不把通用原生取消当关联拒绝 |
| `services/api/internal/authprivacyhttp/endpoints.go` | C 增加 PostBackend／帖子路由、帖子方法／query 白名单、429 帖子错误、CORS `Server-Time`；A 没有社区扩展，B→A 该文件未改 | 社区负责保留 14 操作与授权边界；不能用认证旧 endpoints 覆盖。整合后 HTTP、真实 handler/PG fixture 及 server/vet 重验 |
| `services/api/internal/authprivacyruntime/config.go`、`server.go` | C 增加显式 PostsConfig、三种独立用途 key、跨所有私有 key 查重、仅 C 启用 posts；A 没有该扩展，B→A 文件未改 | 保留 C-only 配置、关闭默认及用途隔离；实际 deployed cmd／最小角色仍独立验收，fixture 不代证部署 |

## closure 与原生 vault/passkey

| 文件／边界 | 已提交差异 | 保留与责任界线 |
|---|---|---|
| `services/api/internal/authprivacy/community_closure.go`、`community_identities.go`、`workers.go`、`community.go` | C 在申请闭号／封禁时停发布，正式闭号同一事务执行 `closePostAccount`，身份删除／worker 接入文字生命周期；A 相对 B 没有这些社区扩展 | 社区负责保留原事务 Gate 和内容清理；认证账号关闭契约本轮不改。需要正式 worker 闭号后业务残留／身份投影／原命令回执检查 |
| `packages/auth_vault/lib/hnuhole_auth_vault.dart` | C 增加 `DurableBusinessVault` 的 read/write/path/purge；A 没有（B→A 无实现变更） | 保留业务与认证独立 namespace，首写相同值约束、闭号墓碑和原 scope。不能用认证 vault 整文件覆盖 |
| `packages/auth_vault/android/src/main/kotlin/org/hnuhole/authvault/AndroidAuthVault.kt`、`AndroidBusinessStorage.kt`、`AuthVaultPlugin.kt` | C 增加业务专用目录／alias、writeOnce/delete、SQLite sidecar 清理、closed marker，`withPreparedScope` 与 purge 共用同进程多 engine 锁；A 没有业务能力 | 保留 F3 修复及 7 项业务 instrumentation 源码。主机替身不能证明 Keystore 删除、跨原生进程锁或备份行为；认证新的 `AuthVaultProcessRestartTest.kt` 另有文件集合覆盖改动，不能移除业务测试 |
| `packages/auth_vault/ios/hnuhole_auth_vault/Sources/hnuhole_auth_vault/AuthVaultPlugin.swift`、`AuthInstallationMarker.swift` | C 增加 `HnuholeBusinessV1`、独立 Keychain service、只首建业务 key、closed marker／SQLite sidecar／Keychain 清理；A 相对 B 没有此扩展 | 保留 C 实现但标 iOS NOT_RUN；需 macOS/Xcode/签名目标复验，不把 Swift 源码或 host marker 测试当 iOS 通过 |
| `packages/auth_passkey/android/src/main/kotlin/org/hnuhole/authpasskey/AuthPasskeyPlugin.kt`、`PasskeyCodec.kt`、`PendingOperation.kt`、新增 `PasskeyAcceptanceErrors.kt` | A 增加有界原生错误类别、debuggable＋专用 phase 的验收观察／迟到回调／合成显示标签／指定公开 ID 入口；provider base64url 允许规范 padding 并规范化传输拼写，保留签名二进制字节；产品正常恢复仍拒绝 `allowCredentials` | 认证负责候选实现和 release guard／原生证据；社区不启设备入口、不把调试验收入口变成产品 fallback。最终整合需正常 codec、ownership／迟到回调及 release 禁用检查 |

## manifest、构建与锁文件

| 文件 | 候选差异与整合注意点 |
|---|---|
| `apps/mobile/android/app/src/main/AndroidManifest.xml`、新增 `res/xml/auth_data_extraction_rules.xml` | A 保留 `allowBackup=false`／`fullBackupContent=false` 并增加 Android 12+ cloud/device transfer 各数据域排除。最终规则必须继续覆盖 C 业务 SQLite/key 路径；源文件存在不代证 OEM 搬家／系统备份 |
| `apps/mobile/android/app/src/main/kotlin/org/hnuhole/hnuhole_mobile/MainActivity.kt` | A 增加 guarded driver/lifecycle/验收入口，与原生测试源码同组审查；正常 App、release guard 与社区根启动均需最终版本证据 |
| `apps/mobile/android/app/src/debug/AndroidManifest.xml`、新增 debug Java `GoogleFidoDiagnosticActivity.java`／`GoogleFidoDiagnosticPolicy.java`、debug `res/values/passkey_associations.xml`、`apps/mobile/android/app/build.gradle.kts` | A 增加 debug FIDO 诊断 Activity 及四个 `debugCompileOnly` 公共 API 依赖；不是产品认证 fallback。认证交接明确最终诊断 prepare／release 排除尚无成功 manifest，候选 APK 不可安装。本任务不构建或安装它；最终由认证会话处理并交付 guard 证据 |
| `apps/mobile/pubspec.yaml`／`pubspec.lock`、`services/api/go.mod`／`go.sum` | C 为文字 Unicode16／Drift／SQLite 增加并锁定依赖、保留 Linux 系统 SQLite hook；A 不含文字依赖，净差中的移除是分支范围差异。保留 C 锁文件，不以覆盖／删除锁或升级依赖解决整合；最终固定版本运行 enforce-lockfile |
| iOS manifest／Passkey 原生 | A 相对 B 的 `apps/mobile/ios`、`packages/auth_passkey/ios` 没有变更；这不提供 iOS 构建、Keychain、AuthenticationServices、AASA 或手机 UI 证据 |

## SQL 与权限

C 增加正式迁移 `services/api/migrations/0013_community_text_posts.sql`，创建 `c_posts` 文本状态、任务／尝试／内容／command receipts／cleanup／身份公开标签、协议 key 及 ordinal sequence。A 相对 B 的正式 C/V 迁移无变化，也没有 0013；不能为“匹配认证”回退 schema 或绕过权限审计。

`services/api/authlab/privacy-role-audit.sql` 的 C 扩展只为 **C runtime** 放行明确 `c_posts` 表的 SELECT／INSERT／UPDATE 和 `publication_ordinal_seq`／`acceptance_ordinal_seq` 的 USAGE；普通 business、独立 recovery 与 V 不获得帖子任务／正文权限。未来整合要保留白名单及负向审计，重新跑新库和受限角色／迁移检查。C 的 `run-post-schema-isolated.sh`、`posts_config_test.go`、帖子 SQL/HTTP 测试和实际 runtimeprobe posts 路径均不能被 A 的旧同名入口覆盖。正式库升级／实际 cmd 角色／运营与生产批准仍无本轮全链证明。

**已提交快照中的社区授权遗漏：**`infra/postgres/grant-community.sql` 在 B→C 无差异，C 仍没有 `c_posts` 授权；B→A 同样无差异，A 本就不含文字模块。C 虽已导入 0013 文字 schema 与上述权限审计白名单，却未同步导入对应 grant，属于社区选择性导入遗漏，不是认证回归。本轮补丁应用前的社区独立 `posts-privileges` 实际 FAIL，具体命令／失败／责任边界见[本轮验证报告](community-flutter-f4-validation-report-20261012.md)；动态结果不改写本文 C/B/A 静态比较对象。

**本轮未提交工作区修复：**用户已明确确认最小安全配置修改，根任务已在本任务独立 clone 应用固定后端 `514a944560988e3d8d599e6f9fe9d5d99fe07f88` 的 `infra/postgres/grant-community.sql`，新增29行，原认证授权前缀保持不变，文件与该来源完整一致。此补丁属于本轮未提交工作区，不纳入上述已提交 C/B/A 的静态 Git 对象比较；补丁后的实际动态复验结果与源码覆盖范围以[本轮验证报告](community-flutter-f4-validation-report-20261012.md)为准，不以补丁已应用、审计白名单或 owner fixture PASS 推定受限 runtime 授权已通过。

## 最小复现与责任归属（静态已证实，未运行认证候选）

以下是整文件替换会造成的确定性接口／状态不兼容，不登记为认证候选本身运行失败，也不在本轮做实际替换：

1. **丢闭号 owner／拒绝持久状态**：在 C 的 `pendingClosure` 包含合法 `originalAccountId` 时，A 的 `AuthWorkflowCodec` 字段白名单不含该字段；仅复制 A codec 会拒绝 C 的已保存状态。仅复制 A flows 又会失去权威关闭到原账号业务清理的桥。证据为 C→A 两文件 diff；责任为社区整合保留扩展、认证确认最终流程接口。
2. **丢原生业务能力**：保留 C `PostStore.openNative` 却复制 A vault Dart／plugin，会缺 `DurableBusinessVault` 或 `business*` MethodChannel 方法；缺 key/path/purge，无法证明闭号清理。证据为 C→A vault diff；责任为社区原生扩展，认证 vault 状态语义保持。
3. **丢文字路由与服务端生命周期**：复制 A 的 main／endpoints／runtime／closure／权限脚本，会失去通道帖子入口、原命令核对、文字服务或关闭清理。证据为 B→A 无这些社区改动而 B→C 有扩展；责任为社区整合，不归咎认证分支未开发文字功能。
4. **认证剩余真实缺口**：A 的 transfer 文档记录 NI-D01–D03 完整验收 FAIL、第二实体 Android X01/X02 BLOCKED、B6 NOT_RUN；Google/vivo 通用取消没有明确上游根因。最小重现和各版本证据在 A 内的 `services/api/authlab/android-b3b4-google-provider-verification.json`、`android-passkey-selector-diagnosis-verification.json`、`android-matrix-verification.json`。本任务没有复用其账号／签名／CA／数据库／手机，也不尝试代修或把类别推断改为通过；等待认证会话固定交付与责任边界。

## 待确认项及固定整合后的复验

- 认证会话明确声明用于社区整合的**完整 40 位提交 SHA**、已完成的最终回归范围与剩余验收边界；确认 A1、A 还是后续提交，不能用移动分支名替代固定提交。
- 确认最终 main 的 debug trust／RP 注入、OTP 显式重验、HTTP byte-limit／来源兼容、原生验收／诊断 release guard；不要复制构建镜像 overlay、未提交代码或旧测试秘密。
- 在新独立目录核对最终认证固定 SHA 相对本文 A 的增量，再处理 main／flows／settings 三处双侧源码重叠，成组保留 closure codec、vault、业务 SQL／权限与锁文件。更新实际最终源码指纹和每项证明范围。
- 固定实际整合代码后重跑仓库入口的 checks、auth-regression（R05）、integration、server、posts-privileges、最终 vet；重点重复提交只核原命令、失败 retry 原身份／通道、切账号迟到结果隔离、DELETE 丢响应／compact 写盘失败、正式闭号业务清理。原 F3 308／F4 8 项、认证历史 188／249 等均不能代证最终整合代码。
- 手机 Android：构建本版、业务 vault 7 项、原生跨 engine／进程／重启／备份恢复、真实 main 启动与自动 poll、IME／TalkBack／大字／系统字体；只在有明确归属设备／凭据／端点并另获授权后执行。iOS：macOS＋完整 Xcode＋Team/Bundle/签名／目标 iOS，复验构建链接、Keychain／安装 marker／业务 purge／跨进程、AuthenticationServices／AASA 及 UI。当前均未在本任务执行。

## 本次只读命令

工作目录：`E:/HnuHole-community-f4-20261012/repo`。所有比较对象已提交；fetch 只写本 clone 的 Git 对象／FETCH_HEAD，没有 checkout／merge 或触碰认证会话工作目录。

```powershell
git rev-parse HEAD
git ls-remote origin refs/heads/codex/auth-privacy-handoff
git fetch --no-tags origin 976c0048aaa40d9b7f589cb735f3bf9c47571486
git merge-base 4d58116bdde2c1d2d406b965590bc1625a5c7955 976c0048aaa40d9b7f589cb735f3bf9c47571486
git log --oneline 0eff47a21cd4f4ab1636b4468f7d5df9769a264f..976c0048aaa40d9b7f589cb735f3bf9c47571486
git diff --name-only 4c40f9015095ebd84dc2b17e30e6ef7ef159321f 976c0048aaa40d9b7f589cb735f3bf9c47571486
git diff --name-status 0eff47a21cd4f4ab1636b4468f7d5df9769a264f 4d58116bdde2c1d2d406b965590bc1625a5c7955
git diff --name-status 0eff47a21cd4f4ab1636b4468f7d5df9769a264f 976c0048aaa40d9b7f589cb735f3bf9c47571486
git diff 4d58116bdde2c1d2d406b965590bc1625a5c7955 976c0048aaa40d9b7f589cb735f3bf9c47571486 -- apps/mobile packages/auth_vault packages/auth_passkey services/api
git show 976c0048aaa40d9b7f589cb735f3bf9c47571486:docs/design/auth-privacy-machine-transfer-20261010.md
```

上述 Git 检查成功，只证明固定对象的静态差异与候选资格。本文没有运行认证 A 的 Flutter／SQL／native，也未认定任何联合终验通过。本轮社区独立测试结果以本轮报告／机器记录为准；验收口径仍是“当前固定基线在主机范围可复验，等待最终认证整合”。
