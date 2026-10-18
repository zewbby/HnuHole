# 任务2：单台 Android 原生存储与生命周期实测

2026-10-15，结果 **PASS_TASK2_APPROVED_SINGLE_ANDROID_SCOPE**。真实 vivo S18 / V2323A、Android15 / SDK35；CA-A08/A09/A11/A12 在批准的单机范围通过。整个模块/App、任务3系统Passkey、任务4双设备、iOS和生产未通过。TalkBack 当前关闭，未改设置、未验读屏。

起始 `7e185b129eef0269cb66f53e97b5efceed21bada`；产品固定 `b5accf36b90e27829b6d039cd58a5b9c189a3da8`，认证固定 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。仅修改 stage2 现场控制器、守卫测试和交接；没有产品、认证协议、依赖/锁、原生plugin、manifest或SQL/权限修改。保存/远端最终SHA见外部 `git-delivery.json`，最终HEAD也在交付回复列出。

| 本轮执行 | 结果 |
|---|---|
| AndroidBusinessStorageTest / AndroidAuthVaultTest | 7 / 16 PASS，实际 Android Keystore 和业务 vault |
| PasskeyCodecTest / PasskeyAcceptanceErrorsTest | 9 / 3 PASS，仅编码与错误边界，非系统Passkey创建/恢复 |
| AuthVaultProcessRestartTest | 3组PASS：write/read、kill-before-replace/read-before、kill-after-sync/read-after；预期测试进程崩溃原输出保留，不另计为35项 |
| storage write → read | PID 17214 → 19277，实际SQLite、原草稿/commandId/digest/身份/通道、认证合成记录与另一账号均保留 |
| 用户手动整机重启 → reboot-read | boot ID确实变化，PID 15787；原状态通过实际插件恢复，不声称断电或OEM迁移 |
| purge → closed新进程 | PASS：A本地清理、墓碑持久且拒重开、业务key/库文件不存在；B和认证记录保留。是合成本地adapter检查，权威服务端闭号另见任务1固定证据 |
| 正常App真实账号生命周期 | 原同签名normal APK，重新正常登录合成A后强停/重开及整机重启；用户分别确认草稿/中文/换行/emoji/原身份通道/列表和会话恢复 |
| 主机工具回归 | Windows155 PASS＋3 POSIX SKIP / 158；Linux158 PASS；stage2聚焦14 PASS，覆盖最终可执行修改 |

## 旧会话未恢复的现场证据

开始时原任务1的三个专用容器及五个进程已停止。核对精确project、volume、只读init bind和端口后，仅启动原资源，无reset/migration/新库/新材料；C/V 503安全冻结。先提供具体脚本并取得用户“允许仅恢复本任务临时库的两个Gate”后，才执行仓库原有authdev recover，推进授权代次，恢复ready200。

首次正常App重开，用户报告“让我登录或注册”。只读SQL确认Gate第3代、A的5条旧会话均旧代、当前代0条；`community_authorized.go`原规则明确拒绝旧代会话。这次**不记旧会话恢复PASS，也不据此宣称存储丢失**。保留原观察/SQL/独立强停记录。随后仅用既有合成A经正常UI密码登录一次，SQL当前有效会话1条，再进行新的强停/重启验证；没有注入token或回放旧业务。

重启前用户对明确清单答“正常的”；重启后的确切回答及清单见机器记录。人工确认只代表所问范围，不冒充逐项自动观察或新的手动IME输入。原phase状态仍为PARTIAL_MANUAL，由独立人工回执形成此汇总，未改写原自动记录。

## 源码、命令与证据范围

复用原stage2的三份独立新签名APK，安装后逐份SHA核对。签名 `9a9f24d8df422d013c85cdf8e7a9861e22669e4e184013c53d41b38450ee76da`，独立包名见机器记录。旧456输入指纹保留历史；当前199项镜像对照198项相同，仅本次storage入口未引用的stage1 scenario不同。Git核对产品/native/manifest/SQL/锁未变，测试入口本身相同，故没有重建APK或冒称历史全450输入当前仍相同。当前控制器独立SHA见JSON。

实际命令为 `E:/acanda/python.exe -B tools/community-android-stage2/phone.py --manifest E:/HnuHole-community-f4-20261012/stage2-preparation-20261015/device-window/manifest.json --device <已确认设备> --phase <suites|write|read|reboot-read|purge|closed>`，附五项窗口/安装/释放/USB/自有包强停确认及显式 `--allow-existing-host-usb-identity`；仅reboot-read附 `--confirmed-manual-reboot`。每次完整实参、UTC起止、exit与私有日志在 `*-execution.json` / `*-runner.private.log`，全部原生原输出为准备目录device-window下 `native-instrumentation.private.log`。现场重开与正常UI登录脚本只在外部归属目录保存，未存账号/密码/token入Git。

Windows `python.exe -B -m unittest discover -s tools/tests -p 'test_*.py' -v` 和 WSL `python3 -B -m unittest discover -s tools/tests -p 'test_*.py' -v` 各有独立日志。既有mobile327/分析0及Go七阶段引用其原日期/版本，本轮未重跑，不冒充新结果；本轮可执行改动仅Python现场控制器，已重跑全部相关host守卫，六设备phase均使用该最终控制器执行。

默认Windows key隔离仍阻断。用户先明确许可本轮既有USB身份，控制器才逐层验证真实OS profile metadata；不读取/复制/hash/改变key，保留其他全部门槛。自有ADB端口34881及PID/exe/start见原state；未调用全局5037，不停止其他服务。准备manifest的false字段保留原准备含义，现场授权另存state和用户回执。

外部目录：`E:/HnuHole-community-f4-20261012/device-validation-stage2-20261015`，制品与原state：`E:/HnuHole-community-f4-20261012/stage2-preparation-20261015/device-window`。保留了主机诊断失败：WSL首次git safe.directory错误用本次命令级配置修正；首次lab bind校验拒绝后核实精确只读bind才恢复；UI只读采证的/dev/tty与编码错误不涉及业务提交，修正后再读。503旧ready文件曾被同名诊断覆盖，现场观察按tool事实另作明确摘要，后续改为时间戳文件，不伪造原始日志。

## 后续

任务2单机范围完成；下一项是任务3的独立RP控制权、配置/部署确认、最终候选重建及真实系统Passkey。任务4仍需第二实体Android和可控OEM/恢复路径。iOS须macOS/Xcode及设备；生产另行验收部署，不在本轮通过范围。当前正常App/A数据、三个测试包、原库及自有server/reverse/SDK缓存材料按已授权接续安排保留，未卸载/清数据或改签名。
