# 2026-10-10 认证分支换机交接

分支 `codex/auth-privacy-handoff`。用户要求停止当前验收，提交全部认证开发、验收及排错工作，交接缓存／测试秘密，远端确认后清理本任务本地缓存。当前入口以本文和 `auth-privacy-machine-transfer-verification.json` 为准，旧文档“缓存保留／未提交”是当时历史状态。

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
