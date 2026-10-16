# Android手机窗口：专用ADB key隔离阻断

2026-10-15（Asia/Shanghai），当前结果 **BLOCKED_KEY_ISOLATION**。用户已确认vivo S18和30–45分钟窗口、认证会话释放、隔离包安装及本任务USB key。CA-A01–CA-A13全部NOT_RUN；stage2当前同样阻断。定位由gpt-6-astra只读完成；修复、主机验证和交接由gpt-6.1-sol high执行。

本turn起始7ded6bda975684a7a6c07869d9ac02130fb7223b，修复起点0c8e2470d6281785ba9e6ff647cfc2aa7fc19cc4（期间新增文档提交已保留）。产品固定b5accf36b90e27829b6d039cd58a5b9c189a3da8；认证固定d859cb05c772cdf8d8b75e439a2bfedf0414dd46。本次不改Dart、Go产品、SQL、协议或APK，不构建SDK/安全配置。

原stage1带全部四项授权与launch-manual实际运行：专用37.0.1-15733141 ADB启动60761 server（PID75036，10:38:31.326771+08:00），等待90秒后“selected physical device is not authorized/ready”，exit1；devices列表为空。原stderr保留于stage1-preparation-20261014/device-window/device-private.log。没有device-started/result/mappings，没有安装、启动App、注册或业务写入。手机标识只以摘要存于机器记录。

已定位缺陷：AOSP Windows `adb_get_homedir_path`通过`SHGetFolderPathW(CSIDL_PROFILE)`定位profile；认证`load_userkey`先尝试默认profile/.android/adbkey，`ADB_VENDOR_KEYS`追加key。因此环境HOME/USERPROFILE/ANDROID_USER_HOME/ANDROID_SDK_HOME及专用端口不能证明key隔离。来源：[adb_utils.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/adb_utils.cpp)、[client/auth.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/refs/heads/main/client/auth.cpp)。这是源代码诊断，不是对本机二进制实际读哪把key的观测；未检查用户key内容。既存5037 server占用USB仅为疑似，未确诊、未停止或连接它。

stage1/2现均在manifest读取/状态写入、socket绑定和任何ADB前明确拒绝当前Windows设备路径；环境构造helper也阻断。没有默认true的验证值、manifest信任位或授权flag绕过。真正独立profile或专用key目录机制尚未在此runner验证，不代表Windows主产品不受支持。plan-only保持无manifest/ADB访问。

| 本轮实际检查 | 结果与范围 |
|---|---|
| 原尝试前host预检（父会话同turn执行并交接） | 450项输入、APK/ADB哈希、60761空闲、TLS ready、C/V各200、新空库与clock0、9项phone host unit PASS；不是手机通过 |
| Windows完整Python host suite | 139项运行：136 PASS、3 POSIX SKIP，exit0 |
| 专用WSL Linux完整Python host suite | 139 PASS，exit0；包括Windows跳过的POSIX范围 |
| 两平台聚焦phone host suite | 各23 PASS；新增stage1全授权、环境helper和stage2全部6阶段零manifest/socket/进程副作用回归 |
| 两runner plan-only | exit0，无manifest/ADB访问 |
| Windows两runner实际全授权synthetic CLI | 预期exit1，BLOCKED_KEY_ISOLATION，使用不存在manifest且未调用ADB |
| 原APK/ADB及支持文件重新哈希 | 与原manifest一致；原制品/签名与历史source fingerprint记录保留 |

完整host suite使用E:/acanda/python.exe以及HnuHole-Ubuntu-24.04的hnuhole纯Python，无SDK/手机操作。新源指纹仅更新四个runner/test输入，机器记录保留原456项历史指纹与新指纹。前段预检的stdout未另存；原空库核对脚本曾更新stage2-preparation-20261015/stage1-lab-preservation.json，本修复未覆盖该旧文件。当前C/E空闲观察分别19,085,795,328 / 154,126,004,224 bytes，未安装大工具。

结束时重查自有exe、精确start、60761监听、完整fork-server命令行，且没有其他自有ADB client，仅Stop-Process PID75036。确认该进程与60761消失，既存PID59948的exe/start未变，未调用默认5037或kill-server。用户已结束本轮社区手机窗口，继续前须重新确认窗口及认证释放；专用材料按原授权保留，不清任何key/账号/数据。

后续必须先证明真正独立OS profile或已验证支持专用key目录的ADB，再由原服务归属方安全释放目标USB，重新核对当前源码/制品摘要、TLS ready、新空库和clock0后才能设备流程。新OS账户、安全配置或共享ADB/key例外须用户明确变更授权；不自行新建、编译工具或试默认profile。stage2仅自身强停与整机重启分别按后续授权处理。系统Passkey/RP、双实体NI-X01/X02、iOS、生产与完整模块继续独立待验。

外部新证据根E:/HnuHole-community-f4-20261012/device-validation-20261015已确认绝对路径且新建owner；windows-host-tests.log、linux-host-tests.log、runner-cli-0–3.log、owned-server-stop.json及sanitized-result.json保留本轮结果。只提交源码、测试与小型脱敏交接；原私有配置/日志、APK、key不进Git。提交/远端SHA回执独立保存到同目录git-delivery.json。
