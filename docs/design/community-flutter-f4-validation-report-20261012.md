# F4 当前固定基线主机验证收尾

日期：2026-10-12（Asia/Shanghai）。分支 `codex/community-flutter-pages`。**当前固定基线在主机范围可复验，等待最终认证整合**：本轮主机范围PASS，用户确认最小授权修复后全部六个stage重跑通过；F4最终联合验收仍BLOCKED_DEPENDENCY，完整App／平台未通过。本轮不合并认证、不操作设备、不提交、推送或部署。结果和命令退出码见 [本轮机器记录](community-flutter-f4-validation-20261012.json)；2026-10-10 的 308 项及 8 项记录仅保留历史范围，不计入本轮。

## 版本、目录与修改

本次 `git ls-remote` 和独立 clone 的实际起始 SHA 均为 `4d58116bdde2c1d2d406b965590bc1625a5c7955`。最终 HEAD 仍为同一提交，改动全部未提交；实际修改文件见机器记录 `changedFiles` 和外部 `logs/final-git-status.txt`。源码指纹见 [本轮指纹](community-flutter-f4-source-fingerprint-20261012.json)，282 份源码／测试／配置文本（含平台源码不代表平台执行）。文档不纳入运行源码摘要。

独立 clone：`E:/HnuHole-community-f4-20261012/repo`。原入口 `C:/Users/24237/Documents/ChatGPT/Hnuhole` 是无提交的外层 master，只有三个未跟踪环境交接文件。Windows `E:/Hnuhole-env/source/HnuHole` 和 WSL `/home/hnuhole/HnuHole` 均为认证分支 `976c0048aaa40d9b7f589cb735f3bf9c47571486`，且有未提交修改；本轮仅初始只读核对，未切分支、pull、reset、clean 或覆盖其文件。认证 fetch 仅写本任务 clone 的对象，不读取或复制认证未提交源码。

本轮集成测试夹具仅修复 `apps/mobile/integration/f4_main_https_postgres_test.dart` 两处不必要 `${root}` 插值，改成等价 `$root`，使最后设置入口后的实际夹具通过现有 lint。未改变页面布局、业务、认证协议或依赖版本。

补充 `apps/mobile/test/post_controller_test.dart` 四项及 `services/api/internal/authprivacy/community_posts_test.go` 一项必要回归；修正新闭号夹具先持久清除 session 再暂停授权的顺序。生产闭号流程由 F4-H08 另证，未把夹具错误当生产缺陷。runner 改动见下一节。

另修复实际最小权限遗漏：按用户明确授权，`infra/postgres/grant-community.sql` 只新增固定后端文字授权块29行，原认证40行前缀不变。当前SQL逐字等于后端 `514a944560988e3d8d599e6f9fe9d5d99fe07f88` 同名文件；真实受限角色正／负权限复验通过，来源与修复证据见下文。

## 执行隔离与工具

实际 WSL2 `HnuHole-Ubuntu-24.04`，非 root UID1000；Go `/usr/lib/go-1.22/bin/go` 1.22.2；PG `/usr/lib/postgresql/16/bin` 16.15；SQLite `/usr/lib/x86_64-linux-gnu/libsqlite3.so.0`；rsync/Python3 使用现成系统工具。Go/PG/SQLite 的路径现在可由 `F4_GO_BIN_DIR`、`F4_PG_BIN_DIR`、`F4_SQLITE_LIBRARY` 显式配置，未自动安装工具链。

Flutter 从现成 `/mnt/e/Hnuhole-env/linux/flutter` **只读复制**到本任务 `/home/hnuhole/community-f4-sdk-20261012/flutter`，没有调用源 SDK。版本 3.47.5／Dart3.13.4，SDK revision `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`；复制前后 Dart 二进制 SHA256 相同 `327991241585ee23f10d8b239a3f8484cb55e5060c665700d19d7e01e62ec94a`。专用 SDK marker 为 `community-f4-20261012 dedicated SDK copy`，runner 拒绝 marker 不符、非 canonical 路径及链接 cache。

最终任务根 `/home/hnuhole/hnuhole-community-flutter-f4-20261012-01`；实际 Go、POSIX runner、Gate、PG 和 Flutter 源副本均在该 Linux 文件系统。HOME/XDG/TMPDIR/GOTMPDIR/PUB_CACHE/GOPATH/GOMODCACHE/GOCACHE/GRADLE_USER_HOME 全部位于该任务根。清除继承的 PG*/AUTHLAB_/AUTHRUNTIME_/F4_MAIN_ 变量，不接收外来 DSN。每个 SQL stage 新建独立 initdb 集群、C/V 库与合成角色，私有目录/socket 权限0700、不监听 TCP；本轮 PG socket 端口显式55432，HTTPS 为 Go 分配的 loopback 动态端口。TLS 保持正常证书验证，仅使用当次 fixture 自建 CA／密钥与合成账号，无真实凭据；最小SQL授权源码变更已获用户确认，未改系统或认证运行安全配置。

根 runner 要求显式任务根、SDK 与 owner；任务根仅允许 `/tmp/hnuhole-community-flutter-f4-*` 或当前 UID 的系统登记 HOME 下同名前缀，保留 marker/canonical/无链接检查。最终审查另补 `realpath -m` 的**首次写入前**检查，拒绝含 `../` 或链接祖先的非canonical根，避免原先拒绝前已mkdir／写owner。三份下层 runner 显式校验 PGPORT 并传给 pg_ctl；不通过未知环境连接系统5432数据库。prepare 补复制 `infra/postgres`，新增 `posts-privileges` 和最终 `vet` 入口。Go 固定 local toolchain／readonly module；Flutter 使用 `pub get --enforce-lockfile`。`pubspec.lock`、`go.mod`、`go.sum` 的 Git规范化LF文本均与起始提交相同；原Windows checkout含CRLF，不把换行差异误报为依赖变化，也未改锁定版本／校验值。

16 条合成 runner guard PASS 只证明调度／写入／端口／外来 DSN 清除／owner 及 cache 链接拒绝，Flutter/Go/PG 都是 stub；新增 traversal 用例验证拒绝后目标目录不存在、原task owner不变，不计 App 或数据库验收。

## 实际命令与最终范围

实际各 stage 通过外部可读 wrapper 调用：

```powershell
wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/run-stage.sh checks
wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/run-stage.sh auth-regression
wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/run-stage.sh integration
wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/run-stage.sh server
wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/run-stage.sh posts-privileges
wsl.exe -d HnuHole-Ubuntu-24.04 -u hnuhole -- bash /mnt/e/HnuHole-community-f4-20261012/run-stage.sh vet
```

wrapper 只设置本文的任务环境，逐条实际执行 `bash tools/run-community-flutter-f4-linux.sh <stage>`，记录开始／结束、退出码并将日志复制到 `E:/HnuHole-community-f4-20261012/logs`。最后最小授权修复后重新只读复制同版SDK并重建专用缓存，通过同目录 `run-approved-batch.sh` 串行调用上述六条命令，10:33:27Z–10:41:13Z全部退出0。canonical guard修改前批次存 `logs/pre-canonical-guard-rerun/`；授权前PARTIAL的日志、机器记录和指纹存 `logs/pre-approved-grant-rerun/`。当前以最终approved batch为准；SDK重建核对见 `logs/sdk-recopy-verification.json`。

| 检查 | 本轮最终范围 |
|---|---|
| checks | `flutter analyze --no-pub` 0问题；20文件311项非隐藏测试 PASS、FAIL0／SKIP0，排除22个隐藏 loading/setup 事件；controller38／SQLite30。机器协议计数规则明确，未把旧308移入当前记录 |
| auth-regression／R05 | fresh PG 日志隐私断言及 `TestMobileClientHTTPSPostgres` race；真实 Dart→TLS C/V handler→PG 复合流程，vault 为主机替身 |
| integration | `TestF4MainAppHTTPSPostgres` race；两个独立 Flutter 主机进程、生产 HnuholeApp 根路由、正式 HTTP/controller、TLS/Gate/fresh PG、文件 SQLite，F4-H01–H08 本轮8项重新 PASS |
| server | 全 `go test -race -count=1 -p 1 ./...` 及 runner 内 `go vet ./...`，6测试包PASS，包括新增闭号 SQL 用例；mobile opt-in 在此SKIP、由R05/integration重跑；AUTHLAB_POSTS_RUNTIME_DSN的TestPostSchema受限角色检查在此SKIP、由posts-privileges重跑，不泛化为 native／实际cmd部署 |
| posts-privileges | **PASS**：新一次性 PG，`go test -race -count=1 -p 1 ./internal/authprivacy -run '^TestPostSchema' -v`；9个顶层用例PASS／FAIL0，生命周期4子例PASS。真实非owner C runtime schema／权限矩阵、身份／标签创建及整份正文擦除通过；不可变列、过宽／缺必要授权、business/recovery越权均拒绝 |
| vet | 最后对同一源码镜像再执行 `go vet ./...`，包括最后 F4 Go fixture |

六项全部在最后SQL修复后重跑，覆盖最终运行代码；没有借前一轮owner通过代替受限runtime权限。最终源码指纹 `186915148fa007eaa5fd2692744adf1af05f500df02b54388270f922d68e7d46`，282份文本，Linux被测副本274份逐文件一致；其余6份OpenAPI未执行，root与guard直接执行源文件。文档更新不改运行代码；机器记录保存比对与退出码。raw-Up新库／部分回填不代证Goose旧库升级、实际cmd或全数据库最小角色。

## 五个关键边界

| 边界 | 本轮证据及限定 |
|---|---|
| 重复提交结果核对 | 新 CREATE409 原 commandId/digest 核对、无第二 key，属于客户端故障注入；真实 SQL `TestPostConcurrentReplayAndSealPostgres`／原回执，F4-H03/04 CREATE丢回包跨进程恢复；F4 SQL counts creates=1 |
| 失败重试保留身份／通道 | 新“已受理 RETRY 后丢响应＋重开”保持原 command/digest/identity/channel/attemptVersion，不再发送；真实 SQL `TestPostMuteExpiryAndExplicitRetryPostgres` 证明原绑定。F4-H06 的 retry 是**会话**核对，不借其证明帖子 RETRY |
| 账号切换隔离 | 当前 controller 的迟到 feed/CREATE/DELETE 围栏、SQLite scoped 数据，新闭旧A保留B session/draft；F4-H07 真实A→B不继承草稿／未知／删除事实 |
| 删除丢响应核对 | 当前 controller DELETE持久 compact及重开／迟到围栏；F4-H05真实提交后丢响应，核原命令、清正文并返回，deletes=1 |
| 正式闭号业务清理 | 新 SQL正式 RequestClosure→Finalize→Cleanup：未公开载荷擦除、owner回执去关联、任务隐藏／停止、清理幂等、另一账号不变；公开内容按规范保留并显示 ACCOUNT_CLOSED。新 controller清rows/index及永久关闭墓碑；F4-H08真实关闭B清本地业务而保留A。主机替身不证明原生key/file删除 |

## 失败、修复和环境排障

1. 首次 checks 分析 FAIL：F4 fixture 581／584两处 `unnecessary_brace_in_string_interps`，测试未启动。等价修改后最终分析0问题／全量PASS。日志 `logs/checks-attempt-01/`。
2. 早期 `/tmp` 任务在 WSL 调用间被清空，owner/pub/source/log重新生成；原因未确认，不归咎其他会话。改用本任务独占 HOME 临时根，无系统配置变更。第二 checks 分析与全测试完成，但调整 runner 与其退出阶段重叠导致 shell解析错误、stage exit2；该批不算最终PASS。最终 runner固定后在 HOME 根全量重跑退出0。日志 `logs/checks-attempt-02/`。
3. server 首次未执行测试：`goproxy.cn` 下载锁定 `github.com/go-chi/chi/v5@v5.2.1` zip 超时；Linux直接官方proxy的同版info也超时。日志 `logs/server-attempt-01/`、`locked-go-chi-download.json`。Windows仅下载官方proxy同版info/mod/zip（108726字节zip）到本任务，再放进专用GOMODCACHE；Go在未改go.sum下验证 Sum `h1:KOIHODQj58PmL80G2Eak4WdvUzjSJSm0vG72crDCqb8=`，没有关闭校验、升级依赖或改全局代理。具体操作脚本及 `locked-go-chi-verified.json` 在任务外部目录；随后重跑整个server。
4. **已修复的社区整合缺陷（授权前历史）**：`TestPostSchemaRestrictedRuntimePrivilegesPostgres` 在 `community_posts_schema_test.go:234` 修复前两次失败。迁移0013已撤销PUBLIC对c_posts的权限，起始提交的 `infra/postgres/grant-community.sql` 只有旧认证授权、没有任何c_posts块；`CheckPostSchema` 对 `c_posts.schema_meta` 的首次SELECT即失败。prepare确实复制了该文件，不是被测镜像遗漏。历史FAIL固定在 `logs/posts-privileges-attempt-01/` 和 `logs/pre-approved-grant-rerun/posts-privileges.log`；当前 `posts-privileges.log` 是修复后的PASS。

最小复现为本文 `posts-privileges` stage；它在每次新建的私有socket数据库中创建合成 `hnuhole_c_runtime` 后执行仓库授权文件，无外来DSN。缺陷归属社区F4选择性导入遗漏，不要求认证会话改协议或复制未提交代码。

用户明确回复“允许应用最小授权补丁并复验”后，应用 `E:/HnuHole-community-f4-20261012/missing-post-grants.patch`，原样来自后端已提交 `514a944560988e3d8d599e6f9fe9d5d99fe07f88:infra/postgres/grant-community.sql`。原40行认证授权前缀规范化LF后完全一致，只追加文字块；授schema USAGE、12表SELECT／11表INSERT、7表指定列UPDATE、2序列USAGE及1函数EXECUTE，无schema CREATE、表级UPDATE、DELETE/TRUNCATE/TRIGGER，business/recovery保持无文字权限。补丁SHA256 `15e39400c57bd413af82ebbc955911dadbcde324ba10f7a545949f5ec4a82c2e`，详情 `logs/grant-proposal.json`。当前SQL SHA256 `43348ded5c1227f367b1968d3087989fb2763b94e587ab36f486423193f28c10`、Git blob `6b47c0013ed186e804ce3bef1dc386602f55c484`，与固定来源和提案逐字一致。重建独占SDK／缓存和新一次性库后六stage全部重跑PASS；未向认证或真实库应用该授权，未提交或部署。

夹具lint、runner隔离缺口和实际权限遗漏均已修复，五个边界的必要回归已补齐。当前固定基线的本文主机范围PASS；最终认证SHA、原生设备、iOS和实际部署／升级仍未验，不登记完整App或最终联合验收通过。

## 认证整合及手机／iOS剩余验收

见 [带精确SHA的差异清单](community-flutter-f4-auth-integration-diff-20261012.md)：社区 C=`4d58116bdde2c1d2d406b965590bc1625a5c7955`，认证共同祖先 B=`0eff47a21cd4f4ab1636b4468f7d5df9769a264f`，认证发布实现候选 A1=`4c40f9015095ebd84dc2b17e30e6ef7ef159321f`，远端交接候选 A=`976c0048aaa40d9b7f589cb735f3bf9c47571486`。A1→A无产品源码增量，但没有明确最终用于整合的SHA；FP14仍BLOCKED_DEPENDENCY。真正双侧产品源码改动为 main／AuthFlows／settings；closure owner codec、业务vault、帖子HTTP/runtime/SQL/权限扩展必须成组保留。认证归属的OTP/RP/Passkey/开发trust及设备缺口等待认证会话固定交付。本轮只比较已提交对象，没有改认证协议或借用其设备/秘密。

Android完整构建、原生业务7项、实际 main() 插件启动、自动poll、跨engine／原生进程／重启／备份恢复、真实IME/TalkBack/大字/系统宋体/48dp命中均NOT_RUN（本轮明确不操作手机/模拟器/ADB）。iOS构建、Keychain/安装marker/业务purge、AuthenticationServices/AASA、签名链接和物理UX均NOT_RUN（缺macOS完整Xcode与iOS目标）。真实部署cmd全权限／旧库前向升级／生产运营与独立审计不由fresh handler fixture代证。

复验顺序：认证明确交付40位整合SHA及其证据→独立目录比较相对A增量并处理上述重叠→固定实际整合源码，重跑本轮六stage及受影响回归→另获设备/凭据操作授权后，在同版源码构建Android并按F3报告运行 `AndroidBusinessStorageTest` 七项、跨进程／备份／IME/TalkBack矩阵；iOS在macOS/Xcode明确Team/Bundle/目标上构建、验证Keychain及系统Passkey。未实现评论、私信、图片、搜索、推送等仍为NOT_IMPLEMENTED，不写成只差测试。

Android业务7项的现有后续入口（**本轮未执行**，需先在归属明确的专用目标安装同版App／test APK并获设备授权）：

```text
adb shell am instrument -w -e class org.hnuhole.authvault.AndroidBusinessStorageTest org.hnuhole.authvault.test/androidx.test.runner.AndroidJUnitRunner
```

`tools/run-android-vault-probes.ps1` 当前只选认证类，不能代验这7项。iOS尚无本轮可用的完整构建／设备runner，需先提供macOS/Xcode及签名目标；不能发明筛选参数或拿主机marker结果补平台PASS。

## 清理与复验日志

各SQL stage已由自身trap停止并清理一次性PG。最终仅清本任务 canonical/marker 所属专用SDK和缓存：执行前匹配本任务路径的进程0，未停止任何额外进程；授权后任务根11412文件／588649386字节、SDK副本18824文件／2606300494字节均已删除，早期同任务/tmp根已不存在。保留独立clone、测试源码、已应用SQL补丁、外部命令脚本、机器记录与上述小型脱敏日志。授权后最终清理完成于10:42:06Z，结果见机器记录 `cleanup` 及 `logs/cleanup.json`；上一轮清理保留在授权前归档。未停止其他服务、未全局WSL shutdown、未Docker prune、未删除锁、共用SDK/AVD/数据或未知资源。

复验需从现成SDK重新只读复制到新的独占目录并创建匹配owner，选择新的同前缀HOME任务根，再按本文环境与六stage顺序执行。外部 `prepare-sdk.sh` 是本轮实际只读复制与二进制hash核对入口，仅在其目标目录不存在时运行；先核对源SDK是否仍为本文版本，否则记录工具差异，不能升级／清理共用SDK来配合测试。runner会自动创建新task根及repo owner marker，禁止复制旧未提交认证材料或其秘密。清理不改变源代码／被测指纹。
