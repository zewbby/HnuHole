# AC05 当前版本平台验收任务单

日期：2026-10-05。分支：`codex/auth-privacy-handoff`。基线 `cbc99b010ba23bba42f76e2523269e3952b14392`，保留本轮已完成但未提交的 AC04。

## 三步实施

1. 固定当前源码与 AC04 历史证据，核对现成工具、设备及真实 RP／平台关联配置。用户已明确允许本轮重建必要 Gradle／项目依赖，验收后清理；保留现成 SDK／AVD。没有真实 RP／签名／关联域时不生成假生产配置或启用系统 Passkey。
2. 运行本机可执行的完整 Android app 构建、vault instrumentation／两进程故障探针、Passkey codec，以及 Flutter 真实原生持久状态双进程测试。补身份首次昵称草稿、账号隔离及原意图跨进程、平台运行的合成 IME 组合输入／大字／语义场景；不将合成事件当作 OEM 输入法或真实辅助服务验收。
3. 逐项登记实际结果、被测源码、失败修复与所需环境。iOS／系统 Passkey／物理设备／备份恢复等缺证项继续 BLOCKED 或 NOT_RUN；B02 基础与整模块分开。更新模块交接／台账、HANDOFF／progress，保存小型脱敏记录并清理明确归属的临时环境。

## 证明范围

Android 模拟器真实 Keystore／文件提交和独立 PID 证明原生及进程边界。设备 Flutter 测试使用显式测试 API，不能证明实际 C/V 授权；AC04 R03／R05 保留原指纹和不同证明范围。没有 macOS／Xcode、RP／发布签名／关联部署和物理设备时，AC05 整项不能计 PASS。既有业务消费者未实现的状态保持，生产 P02–P06 不由本任务批准。

结果见[平台报告](auth-privacy-platform-acceptance-validation-report.md)和[机器记录](../../services/api/authlab/platform-acceptance-verification.json)。
