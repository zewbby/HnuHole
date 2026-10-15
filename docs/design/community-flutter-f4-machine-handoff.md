# Flutter社区 F4 换机接续

> **2026-10-15 当前任务2单机范围通过：**原生35项＋3组进程中断、实际SQLite跨进程/用户整机重启/本地闭号清理PASS；正常App合成A重新正常登录后强停/重启的草稿、身份通道与会话由用户确认。先前旧会话因获准Gate恢复推进代次被拒绝，保留负向观察，不冒充恢复PASS。Windows155＋3 POSIX SKIP／Linux158。见[实测报告](community-android-stage2-device-validation-20261015.md)及[机器记录](community-android-stage2-device-validation-20261015.json)。产品/native/manifest/SQL/锁未改；默认USB隔离守卫保留，仅本轮显式批准既有身份。TalkBack关闭未验；任务3系统Passkey、任务4双实体、iOS和生产仍待验，模块/App不升级整体PASS。以下历史条目保留原日期范围。

> **2026-10-15 当前任务1实测完成：八自动点PASS＋人工IME USER_CONFIRMED。**真实vivo S18/Android15，中文/换行/emoji与草稿重开由用户对明确清单综合答“一切正确”；原自动PARTIAL记录未改，汇总另存。最终mobile327、分析0，Python Windows144＋3 POSIX SKIP／Linux147；历史失败及修复全过程保留。见[实测报告](community-android-device-validation-20261015.md)与[机器记录](community-android-device-validation-20261015.json)。normal/A会话、当前server/reverse/fixture与专用材料保留。任务2–4、iOS和生产仍独立未验；并行stage3准备保留原范围。

> **2026-10-15 第三项主机独立准备已收尾：**起始0c8e247，保留并行e0c1280；产品b5accf3、认证d859cb0不变。本轮七阶段/mobile322、Passkey Dart9、JVM24、固定手机守卫快照＋新工具的Linux148／Windows145＋3SKIP通过；199镜像/560签名对照/3基线APK核对。RP方案已由用户选定但仅继续核实，域名控制权与安全配置/公开部署未获准，未创建新RP环境或最终可验候选，未用ADB/手机。457项本轮输入明确排除并行手机4项，后者单独固定e0c1280，不采用其后未提交代码。见[报告](community-android-stage3-preparation-20261015.md)、[记录](community-android-stage3-preparation-20261015.json)、[关联方案](community-android-stage3-rp-proposal-20261015.md)、[工具入口](../../tools/community-android-stage3/README.md)。后续先处理托管/配置审批、独立lab/重建，再按手机会话新的固定USB交付确认设备窗口；任务1/2实际设备、双实体、iOS、生产仍待验。

> **2026-10-15 手机窗口当前阻断：BLOCKED_KEY_ISOLATION。**用户已确认 vivo S18、30–45分钟窗口、认证会话释放、隔离包和专用USB key；原stage1实际等待90秒后exit1，未发现目标设备，未安装/启动App、注册或业务写入。Windows环境变量不能证明专用key隔离，已给stage1/2添加不可凭授权flag绕过的前置守卫；CA-A01–13全部NOT_RUN，stage2也阻断。Windows136 PASS＋3 POSIX SKIP、Linux139 PASS仅为host；自有60761 server已按exe/start/port核实后停止，既存5037未动；用户已结束本轮窗口，后续须重新确认。见[本轮报告](community-android-device-blocked-20261015.md)与[脱敏记录](community-android-device-blocked-20261015.json)。历史准备/指纹/APK证据保留原范围；先证明真正独立profile或验证专用key目录的ADB，再由原服务归属方安全释放USB并重验摘要/ready/空库。新增OS账户/安全配置或共享key例外须用户明确变更授权。

> **2026-10-15 任务2非手机准备已收尾：**起始d686d65，产品仍b5accf3、认证固定d859cb0，task1全部450项输入与制品/空库未改。task2独立App及两个self-target native包已构建签名/manifest/DEX核对，新增实际插件跨进程与合成A本地清理/B保留探针和35项精确测试选择；mobile322、Linux136／Windows133＋3POSIX SKIP、分析0及199项镜像核对通过。设备均NOT_RUN，未调用ADB。见[报告](community-android-stage2-preparation-20261015.md)、[机器记录](community-android-stage2-preparation-20261015.json)、[制品交付](community-android-stage2-delivery-20261015.json)、[手机SOP](../../tools/community-android-stage2/README.md)。E盘与WSL专用材料按用户要求保留；不能将task1旧密钥、删除材料的历史段落当作当前状态，先读顶部两项准备入口。设备窗口、整机重启/系统设置分别须确认；RP/双实体/iOS/生产仍待验。

> **2026-10-15 第一项非手机准备完成：**修复 DELETE 首次核对失败后遗漏 poll 集合，以及 C 确认取消注销后的 UI 完成入口。最后产品修改后 mobile322/R05/F4 通过，真实 server/权限/runtime/vet 通过；新增整段 host 八检查点和最终隔离 Debug/标准未签名 Release 构建通过，实际设备与 IME 仍 NOT_RUN。见[准备报告](community-android-stage1-preparation-20261015.md)和[机器记录](community-android-stage1-preparation-20261015.json)。按用户要求保留专用环境、手机新空库和 APK；未调用 ADB 或创建真实账号/USB key。后续确认设备窗口、隔离包/USB 授权并补真实输入法，任务2–4、iOS和生产分别待验。

> **Git与清理回执：**整合后源码提交`28cee4656edd710d60676a81794c20cd49f45351`（父提交为上述社区保存SHA和固定认证SHA）已正常推送且远端核对一致。此后交接回执仅改文档/台账，443项运行输入未变。三处canonical任务根经owner与进程核对后清理PASS，约11.07GiB逻辑文件、SDK副本/缓存/APK/合成CA及调试私钥均删除，源码、测试、脱敏记录与外部复验脚本保留；不做VHD压缩或全局清理。见[交付回执](community-auth-integration-delivery-20261013.json)。设备仍按用户指令延期，后续须重建独立材料并获得窗口，不能把已删除APK/签名当作可直接安装的制品。

## 2026-10-13 当前接续（下方早期计划与未提交状态为历史）

固定认证d859cb05c772cdf8d8b75e439a2bfedf0414dd46已按用户新指令整合；整合前20文件保存提交7452dadefb52e7b695cdd1079d21083fcb6cae02已正常推送。当前联合主机七stage、mobile320及原生构建PASS，单台Android验收用户明确延期，所有设备用例NOT_RUN；第二台Android、iOS和生产不纳入本轮通过。最终443项源码指纹599757bf3bb84043d5903e8dad375b0650b469dc5088fcc82a16f1b45e1173c7及命令/失败修复/复验条件详见[20261013联合报告](community-auth-integration-report-20261013.md)、[机器记录](community-auth-integration-20261013.json)、[整合差异](community-flutter-f4-auth-integration-diff-20261012.md)和[设备清单](community-single-android-acceptance-20261013.md)。旧“不得提交/未指定认证/20未提交”的指令与结果仅适用其原日期；本轮用户授权正常提交推送本分支，禁止强推、main合并、Release发布与生产部署。F1–F3不重新开发。

## 2026-10-12 当前接续入口

本任务独立clone `E:/HnuHole-community-f4-20261012/repo`，起始／HEAD均为 `4d58116bdde2c1d2d406b965590bc1625a5c7955`，改动未提交；不提交／推送／合并／部署。以下2026-10-10正文为历史记录，旧308和旧8不计本轮。当前结果以 [20261012报告](community-flutter-f4-validation-report-20261012.md)、[机器记录](community-flutter-f4-validation-20261012.json)、[认证差异](community-flutter-f4-auth-integration-diff-20261012.md) 为准。

**当前固定基线在主机范围可复验，等待最终认证整合。** 用户确认后补入固定后端514a944最小c_posts授权29行，认证前缀不变。最后修改后六stage全部重跑PASS：分析0／全mobile311、R05、本轮F4主机8项、6包server/SQL/race、真实受限runtime／PostSchema9顶层及4生命周期、最终vet。20文件全未提交；授权前PARTIAL／FAIL日志与机器记录固定保留于logs/pre-approved-grant-rerun。F4最终仍BLOCKED_DEPENDENCY等待明确认证整合SHA，Android／iOS／实际cmd／Goose旧库升级未验。owned PG、SDK副本和缓存已清，未触及共享或认证资源。

root runner现在要求显式独占SDK及 `F4_SDK_OWNER_VALUE` marker，SDK的bin/cache也必须独占；不能直接套用下方历史sharedSDK例子。先只读核对工具，然后只读复制已有Flutter到本任务独占canonical目录，在其父目录建立匹配 `.owner`；F4_TASK_ROOT仅允许已登记HOME或/tmp下专用前缀，创建对应repo owner marker。显式配置Go/PG/SQLite和PGPORT，逐stage checks→auth-regression→integration→server→posts-privileges→vet；完整环境与已执行wrapper、日志位置见新报告。任何不能确认隔离的命令不运行，保留锁文件，认证资源优先。

日期2026-10-10。对应分支 **codex/community-flutter-pages**，源码提交`68d35af745098be0ed52d0d448f290795665afa1`。先读[HANDOFF](HANDOFF.md)、[F4计划](community-flutter-f4-plan.md)、[报告](community-flutter-f4-report.md)、[机器记录](community-flutter-f4-verification.json)与[台账](module-acceptance-ledger.json) currentCommunityFlutterF4。F1—F3已完成，不重复画图或开发既有文字页。

## 当前已完成和未完成

固定后端514a944＋认证基线0eff47a上的生产根路由、登录、文字编辑／确认／固定身份、列表／详情／我的、原命令恢复／删除、冻结／会话接替、A/B隔离与B闭号SQLite边界8项主机真实HTTPS/PG检查PASS。源码／测试／小型证据在仓库中；原生vault在主机链使用替身。

最终认证候选尚不存在，FP14/F4联合终验BLOCKED。最终设置入口改动后尚未完成全量mobile与R05/vet回归：WSL系统命令段错误、根文件系统emergency_ro；早期308及Go/SQL结果保留原范围。F5本轮APK／native7／跨原生进程／物理Android／IME／读屏／备份／iOS等NOT_RUN。

## 新电脑拉取（PowerShell）

在你准备存放项目的目录使用一个不存在的目录名：

```powershell
git clone --branch codex/community-flutter-pages --single-branch https://github.com/zewbby/HnuHole.git HnuHole-community
cd HnuHole-community
git status --short
git branch --show-current
git log -2 --oneline
```

预期分支codex/community-flutter-pages，工作区无输出；最新为本轮交接提交，上一条源码68d35af。若已有仓库，先保留未提交改动，再fetch并选择本分支；不要在auth工作树强制reset/checkout，也不要把其他会话未提交包拷进来。

## 下一执行顺序

1. 在新的可写WSL/Linux文件系统核对现有Flutter/Dart、Go1.22、PG16、sqlite3、rsync/python3；PG runner必须非root。未安装工具时如实登记，不自动下载大型SDK或复制本机专用缓存。
2. 先运行最终mobile checks，再auth-regression和最终vet；保留相同pubspec.lock并enforce-lockfile。认证依赖未固定前不要宣称F4完成。
3. 取得认证会话最终提交SHA，逐项解决与本分支main/settings/AuthFlows/session/HTTP/closure/native/manifest/SQL重叠，保留F3原命令／闭号／删除围栏。只借固定提交，不借旧SHA或T4未提交设备证据。
4. 在最终整合SHA重跑integration、checks、auth-regression和受影响Go/SQL检查；重新更新四份交接、台账和指纹。之后按F5补原生平台；完整业务未实现部分另行任务，不扩范围。

runner路径为`tools/run-community-flutter-f4-linux.sh`。本机默认Flutter路径不适合新电脑；通过环境变量F4_FLUTTER_ROOT指定已有SDK，F4_TASK_ROOT指定新任务专用/tmp/hnuhole-community-flutter-f4-*目录。例如在Linux终端，仓库根目录（将SDK路径替换为实际路径）：

```bash
export F4_FLUTTER_ROOT=/your/existing/flutter
export F4_TASK_ROOT=/tmp/hnuhole-community-flutter-f4-new-machine-20261010
bash tools/run-community-flutter-f4-linux.sh checks
bash tools/run-community-flutter-f4-linux.sh auth-regression
bash tools/run-community-flutter-f4-linux.sh integration
bash tools/run-community-flutter-f4-linux.sh server
```

每条分别核对退出码，失败先处理该步；server使用真实一次性PG，耗时可能数分钟。Go vet可在runner复制后的`$F4_TASK_ROOT/source/services/api`目录使用已有Go运行。脚本的Go/PG路径按本机已存在工具写死；新机先审查并适配，不发明--module参数。Windows Git可能转换换行，执行Linux shell前核对LF；库／服务／Gate均在Linux副本与专用/tmp运行。默认DSN由runner新建，不把正式库／未知库DSN传给reset fixture。

## 原电脑剩余缓存

本任务Linux缓存尚未删：`/tmp/hnuhole-community-flutter-f4-01a11f1a-20261010`，marker为`hnuhole-community-flutter-f4-01a11f1a-20261010|/mnt/c/Users/Administrator/.codex/worktrees/community-flutter-pages/HnuHole`。删除errno30，WSL根ext4 emergency_ro；相关PG／进程已结束。先由本机另行恢复文件系统可写，核对绝对路径与marker后只删这个任务目录；不要删除WSL虚拟盘、SDK、全局缓存或其他会话目录。当前电脑不安全做全局WSL停机，认证会话仍有设备工作。缓存无需搬到新机。

可交给新会话的指令：

> 在codex/community-flutter-pages接续F4。先读HANDOFF、community-flutter-f4-machine-handoff.md、F4报告/机器记录/计划和台账currentCommunityFlutterF4；已有文字页与主机8项真实链PASS。先在可写Linux环境补最终mobile/R05/vet；等待并固定最终认证提交，整合重叠源码后重跑真实链，最后更新四文件。F4终验和F5平台尚未通过，保留历史证据和未验边界，不重做F1—F3。
