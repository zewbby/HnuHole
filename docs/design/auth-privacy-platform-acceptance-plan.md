# AC05 当前版本平台验收任务单

> **2026-10-17 B5 主线增量已合并：**[PR #9](https://github.com/zewbby/HnuHole/pull/9) 已通过 Squash Merge 进入 main，合并提交 `eff7461`。闭号状态与图片擦除修复、B5 材料和夹具适配已交付；受影响宿主测试、真实 SQL/C/V、Android 构建、独立审查及最终 head GitHub 检查通过。见[整合报告](auth-privacy-b5-main-integration-report.md)、[机器记录](auth-privacy-b5-main-integration-verification.json)和[分支记录](../branches/fix-b5-main-integration.md)。历史24/24仅证明原认证版本；当前 APK 原生设备验收仍 NOT_RUN，iOS、完整产品及生产批准不在本轮范围。未部署或发布。

> **历史认证证据独立保留：**B5 来源为 `ea5cc52840f009b02106f928c444e423c6e61b3e`，产品基线仍是 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。历史 B6 为 **22 PASS／0 FAIL／2 BLOCKED**；B5 双实体首轮为 **23 PASS／1 FAIL**（NI-X02），随后 Bitwarden 原生路线仍 **BLOCKED**；B5-sync 后续为 **24／24 PASS**。原四次 hybrid 失败、同步成功后夹具失败、用户报告未出现选择／验证页的第六次失败及后续重试均保留在原[首轮报告](auth-privacy-b5-validation-report.md)、[同步报告](auth-privacy-b5-sync-validation-report.md)和三份机器证据中。历史 `nonIOSDevelopmentAcceptancePassed=true` 仅属于原 B5-sync 输入及设备链，不是本候选通过；iOS、生产及未来业务边界不扩张。

> **候选证据规则：**两个 B5 checker 仍在固定 `ea5cc528` 历史副本验证，完整 B6 checker 在固定 `d859cb05` 副本验证；不改历史摘要或降低门槛。候选须记录全部历史 runtime 输入的差异及集合以外新增 runtime 文件，另记三份 B5 夹具由 `_HnuholeApp` 适配 `HnuholeApp` 后的摘要及运行时根组件发现回归。旧 APK／旧夹具结果不代证新候选；当前原生设备回归为 **NOT_RUN**，Dart mock、分析和构建不能替代原生存储与设备验收。

平台验收分层记录：宿主自动测试／构建与 Android 原生、实体设备分别计数。AndroidAuthVaultTest、AndroidBusinessStorageTest、AuthVaultProcessRestartTest 在本候选尚未运行；没有获准的隔离设备时保留 NOT_RUN／BLOCKED，并在候选记录说明原因。下方 AC05 任务单的日期、基线及平台缺口维持原范围，iOS 与生产不因此收口。

日期：2026-10-05。分支：`codex/auth-privacy-handoff`。基线 `cbc99b010ba23bba42f76e2523269e3952b14392`，保留本轮已完成但未提交的 AC04。

## 三步实施

1. 固定当前源码与 AC04 历史证据，核对现成工具、设备及真实 RP／平台关联配置。用户已明确允许本轮重建必要 Gradle／项目依赖，验收后清理；保留现成 SDK／AVD。没有真实 RP／签名／关联域时不生成假生产配置或启用系统 Passkey。
2. 运行本机可执行的完整 Android app 构建、vault instrumentation／两进程故障探针、Passkey codec，以及 Flutter 真实原生持久状态双进程测试。补身份首次昵称草稿、账号隔离及原意图跨进程、平台运行的合成 IME 组合输入／大字／语义场景；不将合成事件当作 OEM 输入法或真实辅助服务验收。
3. 逐项登记实际结果、被测源码、失败修复与所需环境。iOS／系统 Passkey／物理设备／备份恢复等缺证项继续 BLOCKED 或 NOT_RUN；B02 基础与整模块分开。更新模块交接／台账、HANDOFF／progress，保存小型脱敏记录并清理明确归属的临时环境。

## 证明范围

Android 模拟器真实 Keystore／文件提交和独立 PID 证明原生及进程边界。设备 Flutter 测试使用显式测试 API，不能证明实际 C/V 授权；AC04 R03／R05 保留原指纹和不同证明范围。没有 macOS／Xcode、RP／发布签名／关联部署和物理设备时，AC05 整项不能计 PASS。既有业务消费者未实现的状态保持，生产 P02–P06 不由本任务批准。

结果见[平台报告](auth-privacy-platform-acceptance-validation-report.md)和[机器记录](../../services/api/authlab/platform-acceptance-verification.json)。
