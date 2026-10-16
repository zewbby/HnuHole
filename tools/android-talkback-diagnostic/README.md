# vivo TalkBack 公开错误节点诊断

这是独立的 shell DEX 工具，用于检查当前 HnuHole 调试 App 的公开错误“密码复验失败，请重新输入密码。”是否被 Android 暴露，以及实际无障碍焦点是否在该节点。它不安装或更新产品 APK，不读 App 私有文件，不修改辅助服务、隐藏 API 策略或平台安全设置。

2026-10-08确认阶段诊断增加`inspect-public`：仅被动检查固定允许名单的错误、恢复码确认字段／确认按钮、UNKNOWN说明／原结果核对、COMMITTED说明／返回按钮及轮换／隐藏按钮。不对新增目标执行任何动作。密码字段只比对公开 hint／description，不读取其 text/value；输出只包含允许名单目标名及各属性是否匹配的布尔。

工具固定设备 `10CEAG17RY003M7` 和包名 `org.hnuhole.hnuhole_mobile`。宿主先核对指定 PID 与 `pidof` 完全一致，并用 `run-as ... id -u` 确认调试包可访问；Java 再核对 PID、当前窗口包名和唯一公开错误节点。未知标签、输入值、事件 arguments、完整语义树、截图、音频都不会保存或输出。

## 已验证范围

2026-10-08 的构建和保留辅助服务的只读检查已执行。App PID `21465` 上发现唯一错误节点：`focusable/enabled/visibleToUser=true`、`clickable/password=false`，具备 `ACTION_ACCESSIBILITY_FOCUS`，边界 `[72,282,1008,342]`。只读检查时实际无障碍焦点存在，但不在错误节点。小型记录保存在明确归属的 matrix 缓存 `diagnostics/talkback-ultra-v1/read-only-inspection.json`。

主验收执行者随后在这个失败后保留的 PID 上执行自动焦点诊断：动作返回 true、收到了错误节点的实际 `TYPE_VIEW_ACCESSIBILITY_FOCUSED`，且 `findFocus(FOCUS_ACCESSIBILITY)` 返回错误节点；其独立记录同时核对了 Google TalkBack PID、Bound 和 TouchExplorer 前／中／后稳定。该自动结果用于诊断，**不计 NI-U03 人工验收 PASS，也不证明全部 TalkBack 流程或真实 IME 输入通过**。人工验收须在独立测试 PID 中保留真实手势事件和朗读确认。

## 运行

PowerShell，工作目录 `C:\Users\Administrator\Documents\ChatGPT\HnuHole`：

```powershell
python -X utf8 tools/android-talkback-diagnostic/run.py build
$taskAppPid = (& 'D:\zewbbyTest\Hnuhole-env\android-sdk\platform-tools\adb.exe' -s 10CEAG17RY003M7 shell pidof org.hnuhole.hnuhole_mobile).Trim()
if ($taskAppPid -notmatch '^[1-9][0-9]+$') { throw '需要唯一的实际 HnuHole 调试 App PID' }
python -X utf8 tools/android-talkback-diagnostic/run.py inspect --pid $taskAppPid --observe-seconds 2
```

`inspect`只查询节点及当前无障碍焦点。`--observe-seconds`为0–10秒，默认2秒；观察期间只输出公开错误的焦点／hover事件以及计数。

需要识别当前确认／UNKNOWN／COMMITTED页面时，使用同样不请求焦点的模式：

```powershell
python -X utf8 tools/android-talkback-diagnostic/run.py inspect-public --pid $taskAppPid --observe-seconds 1
```

该模式输出`known_public_nodes`及当前实际焦点，不要求错误节点存在。PID14231的实际被动检查发现UNKNOWN说明和“核对原结果”按钮，当前焦点在后者，确认字段已经不在页面。记录见缓存`passive-public-inspection-pid14231.json`；它不能追溯已消失的确认字段收到过什么事件，也不计人工验收。

可选自动焦点诊断只能用于明确授权的诊断进程，不能与正在等待真实人手事件的 NI-U03 进程混用：

```powershell
python -X utf8 tools/android-talkback-diagnostic/run.py focus-error --pid $taskAppPid --observe-seconds 2
```

它只对已验证唯一、可见、启用、可聚焦、非密码、不可点击的公开错误节点请求一次 `ACTION_ACCESSIBILITY_FOCUS`。它不执行 tap/click/文本输入，不操作恢复码、Passkey、凭据或按钮。输出始终包含 `diagnosticOnly=true`、`humanAction=false`、`countsAsNiU03Acceptance=false`。

## 输出与服务边界

- `connected.actualConnectionFlags`必须精确等于1，即 `FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES`；检查失败即终止。
- `public_error_node`输出匹配数量、公开 target 名、节点 ID、bounds、可见／可聚焦／动作 flags。ID仅描述本次运行，不作跨进程稳定标识。
- `focus_before`／`focus_after`通过 Android 实际 `findFocus(FOCUS_ACCESSIBILITY)`核对公开错误。未知焦点只输出 available／匹配布尔，不输出其标签或资料。
- `public_event`只输出公开错误的实际 `TYPE_VIEW_ACCESSIBILITY_FOCUSED`或`TYPE_VIEW_HOVER_ENTER`；计数包含原始焦点数、错误焦点／hover数和无法解析 source 数。
- `disconnected.disconnected=true`及宿主退出码0是本次诊断正常收尾的条件。缺少最终记录、进程退出137、反射不可用或 PID 改变都不能计诊断 PASS；应核对服务和残留进程，不能更改系统安全策略重试。

执行者应另行记录 Google TalkBack 的实际 PID、Bound、`touchExplorationEnabled`／TouchExplorer 前／连接期间／断开后状态，避免只凭设置列表判断服务仍运行。工具自身不切换服务，因此 Google-only 对照及恢复原设置由持有原始快照的主验收执行者处理。

这台 vivo 的 legacy `uiautomator.jar`已只读核对：其 wrapper 调用无参数 `UiAutomation.connect()`。该默认连接会临时抑制辅助服务，不能用普通 `uiautomator dump/events`代替在线 TalkBack 诊断。本工具明确调用 `connect(1)`并读取实际 flags。参考：[Android UiAutomation 源码](https://android.googlesource.com/platform/frameworks/base.git/+/master/core/java/android/app/UiAutomation.java)。

初版 shell 进程在连接时因 OEM 无障碍客户端使用空 MainLooper 导致 NPE／137。当前版本只在缺少 MainLooper 时调用公开 `Looper.prepareMainLooper()`，完成普通 shell Java 运行时初始化；修正后实际只读连接／查询／断开已通过。没有改变 hidden-api 或安全策略。

## 归属与清理

源码是本目录的 `AndroidTalkBackDiagnostic.java`与`run.py`。本机 JDK17、SDK `build-tools/36.0.0`及`platforms/android-36/android.jar`用于 Java→D8 构建；本次没有下载工具。

构建缓存固定为 `D:\zewbbyTest\Hnuhole-android-live-faults-20261005\matrix\diagnostics\talkback-ultra-v1`，由 `OWNER=HNUHOLE_PUBLIC_TALKBACK_DIAGNOSTIC_V1`限制归属。`build.json`保存源码／DEX／JAR摘要及构建范围；其 `deviceExecution=NOT_RUN`是构建阶段状态，实际设备检查另见小型运行记录。

扩展允许名单之前的Java／host／README／DEX／JAR／build及只读记录已逐文件核验原始SHA256并归档在`archive-error-only-be04ccac747a`。旧版本证据保留旧源码摘要，不由新允许名单版本代证。

每次运行在 `/data/local/tmp/hnuhole-talkback-diagnostic-<随机ID>`创建精确归属的临时目录。Java在 finally 中断开连接；宿主核对 OWNER 后只删除本次 JAR、OWNER，再用非递归 `rmdir`移除本次空目录。已执行的正常检查确认清理成功。缓存按当前用户授权保留；不清理其他 SDK、缓存、App 数据或设备材料。

异常边界：部分 push、OWNER 读取或删除命令失败时，顺序执行的宿主清理可能留下本次 UUID 目录。工具不会因此扩大删除范围；应保留这次精确路径供人工核对，不能宣称所有异常路径均已验证清净。
