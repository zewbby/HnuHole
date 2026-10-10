# 2026-10-10 认证分支换机交接

分支 `codex/auth-privacy-handoff`。用户要求停止当前验收，提交全部认证开发、验收及排错工作，交接缓存／测试秘密，远端确认后清理本任务本地缓存。当前入口以本文和 `auth-privacy-machine-transfer-verification.json` 为准，旧文档“缓存保留／未提交”是当时历史状态。

## 最终换机回执（2026-10-11）

- 实现／测试／排错源码已推送：`4c40f9015095ebd84dc2b17e30e6ef7ef159321f`；本次最终回执随分支后续提交。
- [加密归档 Release](https://github.com/zewbby/HnuHole/releases/tag/auth-machine-handoff-20261010)：7 个归档、22 个加密分片、9,254,048,479 字节。每个远端资产的 SHA-256／大小和本地认证解密／文件内容 SHA-256 均核对通过。完整清单、链接和结果在 [归档验证记录](../../services/api/authlab/auth-machine-cache-archive-verification.json)。归档成员清单与脚本位于加密 transfer-metadata；密钥单独交付。
- Windows 原始 15,812 文件／10,880,056,025 字节完整保存；只读故障第一轮 WSL 读取有 25,324 错误，该不完整包未作为交付。修复副本后五个任务目录 45,774 文件／9,450,592,080 字节预读和恢复核对成功、错误 0。与故障时可读材料相比的 54 个版本差异另存 recovery-delta，保留最后诊断产物。
- 数据库包含当前 C/V 两份 pg_dumpall，以及四组开发环境 8 个已停止 PostgreSQL 16.6 卷的 tar.gz 快照。所有内容仅限合成测试数据／测试秘密；不能在未知／正式库执行旧 runner。
- 已停止本任务 C/V／代理／构建进程，删除 12 个专用容器、8 个专用卷、4 个专用网络和五个 WSL 任务缓存根。原 Ubuntu 文件系统 e2fsck 复查成功，正常以 rw 挂载；Docker Desktop 收尾停止。没有删除整个 Ubuntu／Docker VHD、SDK／AVD、其他项目资源或手机数据。
- **Windows 文件清理未完成。** 自动审批对临时校验文件和精确任务目录删除均返回 `blocked by policy`，未提供进一步理由；包含文件清单／哈希保护的更窄命令仍被拒绝，未通过其他方式绕过。D 盘原任务缓存已可逆迁移至 C 盘暂存区，约释放 6.6 GB，不等于删除。仍有本机交接暂存目录、仓库 android-matrix／android-fault 缓存及小型 finalize 脚本。
- [Windows 清理脚本](auth-transfer-local-cleanup-20261010.ps1) 已准备，默认仅核对远端和显示目标；实际删除需用户在原机器手动执行 `-Execute`。脚本语法解析与远端校验、目标预演均通过，删除未运行。单独密钥文件在 `C:/Users/Administrator/Documents/HnuHole-auth-archive-key-20261010.txt`，脚本保留它。先把密钥带到新机器，再处理旧机器副本。

### 新机器恢复命令

先拉取分支最新版并下载 Release 全部 22 个 `.enc` 分片。为下载、拼接、解密和恢复内容准备至少 60 GB 空间，另留 SDK／工具安装空间。Python 需有 `cryptography`；脚本每包先校验分片和完整包、通过 GCM 认证后才允许提取。

PowerShell 示例（路径按新机器修改，解密密钥文件从单独交付取得）：

```powershell
git clone --branch codex/auth-privacy-handoff https://github.com/zewbby/HnuHole.git
cd HnuHole
gh release download auth-machine-handoff-20261010 --repo zewbby/HnuHole --pattern '*.enc' --dir D:\HnuHole-transfer\parts
python -m pip install cryptography
python tools/restore-auth-machine-archive.py --manifest services/api/authlab/auth-machine-cache-archive-verification.json --parts-directory D:\HnuHole-transfer\parts --key-file D:\HnuHole-transfer\archive-key.txt --output-directory D:\HnuHole-transfer\restored --extract
```

未安装 gh 时从 Release 页面下载所有分片，不能漏分片。WSL 缓存要进一步恢复到新机器的 Linux 文件系统；旧路径和构建 overlay 按下文修正。recovery-delta 用 mapping.json 映射 blob，只作故障版本参考，不能自动覆盖完整恢复版本。历史 finalize 脚本会重写交接，禁止盲目重跑。

## 已完成与尚未通过

- AC01–AC03 已实现并有各自历史运行证据；具体实现、被测版本及影响范围见 closure checklist、模块台账和原机器记录。
- B1＋B2 固定 11 项已通过。B3＋B4 固定 11 项通过 8 项：NI-C01–C04、NI-D04–D05、NI-K01–K02；NI-D01–D03 完整验收仍为原执行 FAIL。
- 固定非 iOS 24 项：19 PASS／3 FAIL／2 BLOCKED。两项 OEM 搬家需要第二台实体 Android，当前只有 vivo S18；B6 未执行、iOS 未执行，完整 AC05／B02及生产未通过。
- 当前源码包含实体输入法、TalkBack、锁屏／重启、账号关闭／同邮箱新号隔离、迟到结果、故障核对、实际 Keystore／AtomicFile、签名／package 对照等测试入口。历史 PASS 保留自己的源码／APK／PID及证明范围，未迁成当前所有代码已通过。
- 当前交接仅执行记录校验／源码检查，没有重新执行完整 188 项 Flutter、249 项 SQL、12 项原生或 13 项 release 边界；这些数值引用原记录的限定版本。

## 本次 Google／vivo 排错

1. Google 批准正向七次在证明返回前失败；另一次 App 被 OEM single-cleaner 强停，发生在原生请求之前，分别记录。没有新增绑定证明提交。用户确认点击继续，不能把通用取消归咎于用户。
2. 实际安装的 vivo Credential Manager 15.0／10001 APK SHA-256 为 `e7f7daa3654e7bcc68dc691c058fb68617fba9270d131add4463f0393e2ebe81`。静态代码证实 provider 非 RESULT_OK／内部失败被统一映射为 selector 取消，原 provider Intent／错误未传给 App。具体 Google 上游失败原因及当前精确 runtime 分支未证实。
3. 27 字符错误摘要匹配公开 AOSP 常量，但旧 JDI 原型没有区分 callback 参数与 heap fallback，不作为严格回调或验收证据。新有界观察器已保存并编译，未在新 ceremony 上运行。
4. 手机 Google 账号存在；用户确认 Chrome 同步／实时搜索／全局网络可用，密码管理工具无“完成设置／验证是您本人／解锁加密数据”提示。这些不证明 Google 凭据存储创建可用。公开 DAL 检查正确签名 true、错误签名及未关联 package false，不证明实际提供方拒绝原因。
5. 已编写 `src/debug` 的 Google FIDO2 直接结果诊断入口，固定 RP、合成随机 challenge／user、单次 nonce、精确 APK／签名／phase admission；默认仅 prepare，不启动系统窗口、不读取 App vault、不提交 C。host 有 OS 排他锁、持久启动记录和未决结果保护；未知 native 结果禁止直接重试。它是诊断入口，不是产品认证 fallback，也不能代替 NI-D01–D03 验收。
6. 诊断源码 Java 编译、debug APK 组装、批准证书及 debug manifest／dex 检查成功；完整准备没有完成：离线依赖与 Flutter 空 CMake 占位先失败，随后 release 检查遇到 included-build init 问题，重试期间 WSL I/O／只读故障。没有最终 PASS manifest；候选 APK 673,296,778 字节，不可安装。API prepare 和系统窗口均 NOT_RUN，手机未安装此候选。
7. ultra 审查因用量限制中断，主任务续审并保留源码／证据。没有宣称 ultra 已查明 Google 根因。

正式记录：`services/api/authlab/android-passkey-selector-diagnosis-verification.json`、`android-b3b4-google-provider-verification.json`、`android-matrix-verification.json`。

## 环境与缓存交接

- 旧 Windows 根：`D:/zewbbyTest/Hnuhole-android-live-faults-20261005`，OWNER `HNUHOLE_ANDROID_LIVE_DEV_V1`；matrix 子目录 OWNER `HNUHOLE_ANDROID_MATRIX_V1`。统计 15,527 文件／6,638,668,139 字节，包含当前／历史 APK、driver 镜像、构建／失败日志、小型证据和专用 Windows Pub 缓存。
- WSL Ubuntu-24.04 根 `/var/tmp/hnuhole-android-live-faults-20261005` 为专用 Gradle／Pub／构建镜像；C/V 当前根 `/var/tmp/hnuhole-android-live-b3-b4-20261009`。旧 boundary／closure／batch 根日期分别 20261006／20261007／20261007，必须核对 OWNER 后处理。
- 最后 D 盘仅剩 11,141,120 字节；Ubuntu ext4 出现 Errno 5／30，部分旧 OWNER 也无法读取。不能把这份镜像当作完整正常构建环境，不能删除整个 Ubuntu／Docker VHD。恢复或归档失败须逐项写在 transfer verification 中。
- 仓库 `infra/.cache/android-matrix` 含 setup／build／采集历史脚本、APK 静态审查和原型；这些属于加密缓存归档。正式可执行源码在 tools／integration_test，未经正式验证的历史脚本仍按其历史条件使用。
- 已存在 `D:/zewbbyTest/Hnuhole-env` 的 SDK／AVD／Flutter／JDK 等安装不属于本任务缓存清理；不删除其他项目、Mock-Damai容器／未知卷或手机数据。任务签名／C/V 测试秘密可进入加密归档，GitHub／Google／个人登录凭据不采集。
- 所有大缓存／测试秘密以 AES-256-GCM 加密归档上传本仓库 Release；分支中保存资产链接、大小、SHA-256、归档成员清单及遗漏／损坏结果。解密密钥单独交给用户，不在公开仓库中发布。先确认远端资产完整，再清理原缓存及临时数据库。状态以 transfer verification 的实际结果为准。

## 下一台机器的固定步骤

1. 拉取 `codex/auth-privacy-handoff` 最新提交，先读本文、machine-handoff、B3/B4 plan、transfer verification 和模块台账。下载 Release 的全部归档分片，按 SHA-256 核对，用单独收到的密钥解密；失败不得继续提取。
2. 在有足够空间的盘建立新 OWNER 目录。WSL 缓存恢复到 Linux 文件系统；旧 APK／镜像只作历史材料。不要复用损坏镜像的未恢复 overlay，也不要把旧 DSN 传给会 reset schema 的 runner。新一次性测试库与历史快照须明确分开。
3. 核对 Flutter 3.47.5／Dart 3.13.4、JDK17、Gradle9.3.1、Android SDK／NDK、Go／PostgreSQL／Docker 及锁文件；真实版本由原验证记录限定。恢复旧测试签名后核对 `fd26b276cb170bf084a932d3b3919bd3aa44874395809968bdd74ddab87389dc`；公开 RP `zewbby.github.io` 关联主 package 与 acceptance。不要意外发布未批准签名或 unassociated package。
4. runner 目前含旧绝对路径、手机序列号 `10CEAG17RY003M7` 和已审阅摘要；换机须显式改为新 OWNER／路径／新设备，并重新做 guarded preflight。旧原生结果与原帐号/操作只能核对，不能重放证明。
5. 先修完 debug 诊断离线构建／arm64 大小／release source-set 与 merged-manifest 排除检查，取得新的实际 manifest。默认 Google `prepare` 成功后如仍需系统结果，再安排一次明确人工窗口；具体错误证实前不重复旧 Credential Manager 正向。
6. 取得可用实际提供方批准正向后，才集中执行 NI-D01／NI-D02／NI-D03。不能用通用取消、公开 DAL 或直接 FIDO 诊断成功把三项改为 PASS。之后安排两台实体 Android 的 X01／X02、B6收口；iOS设备／macOS及生产门槛单列。

手机主 App 保留 v16 SHA `ac66d81ffb760e17aca0770906b93c18b031bf8ffb9e0733974ef8b65abe5871`，批准隔离 App v17 SHA `7c0230c7df2cbcf1fc0074607bc621fe85395c3964308b092bc8e4f9df981f89`。Google凭据与自动填充已按原备份恢复 vivo；Clash 全局模式需用户在手机恢复原模式。旧服务清理后这些 App 的旧本地测试端点不可用，不代表生产平台已部署。

## 诊断构建镜像残留 overlay

以下只涉及 WSL 专用构建镜像 `/var/tmp/hnuhole-android-live-faults-20261005/repo`，不能覆盖正式 Windows 仓库。诊断 runner 的 finally 首次恢复即遭遇 Errno 30，不能假定镜像已恢复：

- debug Java Activity／Policy 原本不存在；debug manifest 原有 asset_statements，仅新增诊断 Activity。
- `android/app/build.gradle.kts` 临时改为 acceptance applicationId 并加入 debugCompileOnly；原件在 `matrix/b3b4-build.original`。
- `android/build.gradle.kts` 临时切换诊断 build 根；以正式仓库版本恢复。
- main AndroidManifest 的 `.MainActivity` 临时改为完整类名；原件在 `matrix/b3b4-manifest.original`。
- AuthVaultPlugin.kt 存在此前隔离 IO overlay，以正式仓库文件恢复；AndroidAuthVault.kt 本轮没有语义修改。

四次构建均已结束：75748 离线 coroutine 依赖缺失；60246 CMake 占位失败；28665 debug APK 检查成功但 release init 无 app；9666 修复 included-build guard 后遭遇只读／I/O 故障。host JVM policy test 本轮 NOT_RUN，release 排除没有成功运行证据。复用缓存之前必须先按源码重建镜像。
