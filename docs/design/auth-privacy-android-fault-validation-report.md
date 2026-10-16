# Android 真机异常链路记录

日期：2026-10-05。分支`codex/auth-privacy-handoff`，基线`0eff47a`及保留的未提交正常链路源码。任务单见[异常验收计划](auth-privacy-android-fault-plan.md)，逐项结果见[机器记录](../../services/api/authlab/android-fault-verification.json)。上一轮[正常链路](auth-privacy-android-live-validation-report.md)的PASS保留原源码摘要，不代证本轮改动。

当前三组故障范围已实现并取得实际运行证据，`scopedAndroidFaultAcceptancePassed=true`。完整 AC05、B02 及生产仍为 `BLOCKED`。手机 vivo S18（V2323A／Android 15／ARM64）已连接授权；无 RP 域名／HTTPS 宿主，系统 Passkey 保持 BLOCKED。用户有 Mac，但 Xcode／仓库／Codex 可执行条件尚未核对，暂无 iPhone，iOS 本轮未执行。

本轮 Flutter 分析、182 项 mobile 测试、完整 ARM64 调试测试 APK、七阶段实际 runner 均以退出码 0 通过。最终安装包 SHA256 为 `d3526b637021d03811ae057cafc5e1124cb865f8e34fe84d79b668180063b28a`，大小 100876138 字节，runId 为 `hnuhole-android-live-faults-20261005-r2`。只更新安装一次该版本，七阶段之间不重装；runner 每次核对安装摘要和归属。

| 阶段 | PID | 实际结果 |
| --- | --- | --- |
| write | 10229 | PASS：实际页面注册、恢复码完整确认、身份创建／改名 |
| unknown | 10535 | PASS：真实 C 提交后丢弃成功响应，原意图持久化 |
| reconcile | 12328 | PASS：从原生存储恢复原键，核对原回执，无重复提交 |
| frozen | 12825 | PASS：实际 App 暂停会话核对并保留会话，保护写 503 拒绝 |
| recovered | 13052 | PASS：旧代次令牌拒绝，App 清旧权威；主动登录取得新会话 |
| offline-logout | 13286 | PASS：撤销请求受阻，本地先清 Bearer，独立能力持久化 |
| drain | 13482 | PASS：重启排空待办，旧令牌 401，密码重新登录同一账号 |

每个阶段已使用受限 runtime 角色只读采集实际 SQL 和代理计数。代理最终计数为：真实创建请求转发 3 次（含被冻结拒绝的 1 次）、成功响应丢弃 1 次、撤销请求阻断 2 次、撤销转发 2 次（含清理原测试账号会话）、原回执核对 1 次。reconcile 与 unknown 的身份／创建回执数量相同；冻结期间没有生成“冻结应拒绝”资料；C Gate 从 FROZEN／generation 1 恢复到 OPEN／generation 2；drain 后撤销会话增加且仅 1 个活动会话。

数据库保留了初次部分尝试和 r2 的两个合成账号，各有两个身份，因此最终 SQL 总数为 2 个账号、4 个活动身份、4 次创建回执、2 次改名回执。当前 r2 账号的实际 API 断言是 2 个身份、累计创建 2 次；不能把全库 4 个身份误读为当前账号重复创建。逐阶段脱敏快照见机器记录 `sqlReadback`。

初次版本 `4a766005…` 的 write／unknown（PID 19807／24582）通过，第三阶段因未发现调试连接而未执行；后续阶段也未执行。其部分证据保存在 `attemptHistory`，不能代证新版。随后发现并修正末阶段脚本等待了错误页面：重新登录返回首页，再通过实际“我的”入口进入设置。新版用独立 namespace／账号重新执行全部七阶段。

S18 日志关闭时，拨号代码未打开日志页，直接 adb 打开也被系统权限拒绝。采用 Flutter 公开 `FlutterJNI.getVMServiceUri()`：仅 debuggable 包且显式 `hnuhole-device-driver` opt-in 时将带原认证码的 loopback URI 写入 App 私有文件，runner 通过已授权 adb 的 run-as 读取，按 PID 核对并移除文件。没有关闭 VM 认证、启用公网调试端口、绕过系统权限或上传系统日志。实际同一 APK 的无 opt-in 启动不生成文件、阶段后文件已移除；错误 APK 和异版本 resume 摘要在修改故障阶段前被拒绝。发布包实际运行未在本轮另行执行，不能把源码 debuggable 围栏称为发布包平台验收。

| 独立进程阶段 | 真实边界与必须断言 |
| --- | --- |
| write | 实际App注册、恢复码确认、身份创建／改名；真实SMTP、C/V、SQL和Keystore |
| unknown | 实际服务提交第二身份，HTTPS故障代理丢弃成功响应；App保留UNKNOWN原意图及同一键 |
| reconcile | 外部重启后从原生vault读取同一意图，实际App核对原SQL回执；两个身份且无重复创建 |
| frozen／recovered | 宿主开发authdev显式冻结／恢复C Gate；App暂停会话恢复、保留原令牌；冻结时保护写被503拒绝，恢复后旧授权代次令牌被拒绝并清除，用户主动密码登录取得新代会话，核对无冻结写入 |
| offline-logout／drain | 代理只阻断撤销请求；App先清Bearer并持久保存独立撤销能力；重启后真实请求排空待办、旧令牌401，再密码登录同一账号 |

入口：[真机测试](../../apps/mobile/integration_test/auth_fault_device_test.dart)、[HTTPS故障代理](../../tools/android-auth-fault-proxy.py)、[宿主控制器](../../tools/control-android-auth-fault.py)、[设备runner](../../tools/run-android-live-device.ps1)。故障代理验证上游私有CA和主机名、使用本轮loopback证书，不产生业务替身响应、不记录请求正文／头部或秘密。代理统计只保留计数，阶段报告只保留PID、场景及布尔断言；秘密只在本轮私有配置与原生测试namespace中。

宿主先执行现有`tools/run-auth-device-services.sh`建立带OWNER的私有工作目录，再执行`python3 tools/android-auth-fault-proxy.py --work <同一工作目录>`生成`fault-device-config.json`。当前App构建目标为`integration_test/auth_fault_device_test.dart`；安装来源及摘要确认后，使用现有PowerShell runner参数并添加`-FaultWork /var/tmp/hnuhole-android-live-faults-<本轮后缀>`，runner在各进程前调用宿主控制器，七阶段之间不重装。控制器没有公共API，只有私有宿主文件／受限开发Gate操作。

受影响模块 A00／A01／A05／A11／A12／A13／N01／B01／B02 的本轮场景已 PASS，完整模块仍 BLOCKED；相关 X01–X04／X08 只映射本轮认证、持久化与身份子场景。真实源码／测试入口及逐模块状态已同步模块台账。完整 Go／SQL／race／vet、R03／R05 尚未本轮重跑，服务端业务源码未改，保留 AC04 原范围。锁屏、系统备份／卸载重装、V Gate 设备链、正式关闭设备链、OEM 输入法／辅助服务、跨设备、系统 Passkey 与 iOS 仍未执行；完整矩阵、B02 和生产不记 PASS。

按用户最新指令，后续复用的测试环境／缓存／APK保留并记录归属，最终收口统一清理不用的临时产物，现有SDK／AVD和用户数据保留。未提交／推送／部署。

保留位置：Windows `D:\zewbbyTest\Hnuhole-android-live-faults-20261005`，WSL `/var/tmp/hnuhole-android-live-faults-20261005`，OWNER 内容为 `HNUHOLE_ANDROID_LIVE_DEV_V1`。Docker project 为 `hnuhole-device-hnuholeandroidlivefaults20261005`，手机测试 App 保留；本轮 C/V／Gate watcher、代理和构建缓存桥接进程当前仍运行。临时 USB reverse／VM forward 映射已移除，私有 VM 文件已删除，私钥／运行配置／大日志不进入 Git。原初始化器仍有退出清理 trap，因此不要把停止初始化器当作逐组清理；系统／进程重启后需另行核对运行时健康，缓存存在不表示服务仍可用。

中断后复验支持 PowerShell runner 的 `-ResumeFrom reconcile` 等真实阶段参数，只接受同一已安装 APK 摘要、完整前序 PID 链、已采集 SQL 证据及原生 nextPhase。最终已到 done 的 namespace 不能从头再跑；新一轮需单独测试 runId／账号，保留旧证据。当前七阶段已完成，下一步补其余设备矩阵及 Mac／Xcode／实际 RP 关联前提，不重复本轮场景或开发完整业务片。
