# AC05 当前版本平台验收任务单

> **2026-10-16 B5同步恢复收口：**NI-X02已由真我本机同步Passkey完成原生断言、C恢复意图、新密码及完整恢复码确认、无自动登录、旧会话／密码／恢复码401、旧Passkey移除和同号显式新登录。固定 **24／24 PASS**，结合原B6匹配且未变的产品输入，`nonIOSDevelopmentAcceptancePassed=true`。原4次hybrid失败、首个同步成功后夹具失败、未点选的系统超时和Bitwarden ROM阻塞均保留；iOS延期，生产及未来业务仍未通过。真我临时设置已恢复，源机当前Bitwarden设置保留，环境和隔离数据保留，未提交／推送。见[同步最终报告](auth-privacy-b5-sync-validation-report.md)及[机器记录](../../services/api/authlab/android-b5-sync-20261016-verification.json)。

> **2026-10-16 Bitwarden路线预检：**真我RMX3366虽为API34，但实际缺少`android.software.credentials`与系统`credential`服务；已安装Bitwarden只接入普通自动填充，这条原生Passkey路线BLOCKED。新夹具分析／构建PASS，未安装、未新建凭据、未发起认证，两台原设置已恢复。NI-X02仍未通过，固定累计23 PASS／1 FAIL。见[B5报告](auth-privacy-b5-validation-report.md)及[Bitwarden预检记录](../../services/api/authlab/android-b5-bitwarden-20261016-verification.json)。

> **2026-10-16 B5双实体Android实测：**NI-X01官方搬家已PASS；NI-X02已执行但FAIL，真我累计4次原生get均超时，后两次vivo实际提示“设备无法连接”。当前固定24项为 **23 PASS／1 FAIL／0 BLOCKED**，唯一剩余ID为NI-X02，已不再缺第二台手机。没有真实跨设备证明／恢复意图，后续重设与登录链本轮NOT_RUN；两台provider／autofill已按原值恢复，未自动追加重试。既有B6与历史版本记录保留，完整非iOS开发验收、iOS和生产均未通过。隔离包／私有测试状态及可复用环境保留，本轮未提交／推送。见[B5报告](auth-privacy-b5-validation-report.md)及[脱敏记录](../../services/api/authlab/android-b5-20261016-verification.json)。

日期：2026-10-05。分支：`codex/auth-privacy-handoff`。基线 `cbc99b010ba23bba42f76e2523269e3952b14392`，保留本轮已完成但未提交的 AC04。

## 三步实施

1. 固定当前源码与 AC04 历史证据，核对现成工具、设备及真实 RP／平台关联配置。用户已明确允许本轮重建必要 Gradle／项目依赖，验收后清理；保留现成 SDK／AVD。没有真实 RP／签名／关联域时不生成假生产配置或启用系统 Passkey。
2. 运行本机可执行的完整 Android app 构建、vault instrumentation／两进程故障探针、Passkey codec，以及 Flutter 真实原生持久状态双进程测试。补身份首次昵称草稿、账号隔离及原意图跨进程、平台运行的合成 IME 组合输入／大字／语义场景；不将合成事件当作 OEM 输入法或真实辅助服务验收。
3. 逐项登记实际结果、被测源码、失败修复与所需环境。iOS／系统 Passkey／物理设备／备份恢复等缺证项继续 BLOCKED 或 NOT_RUN；B02 基础与整模块分开。更新模块交接／台账、HANDOFF／progress，保存小型脱敏记录并清理明确归属的临时环境。

## 证明范围

Android 模拟器真实 Keystore／文件提交和独立 PID 证明原生及进程边界。设备 Flutter 测试使用显式测试 API，不能证明实际 C/V 授权；AC04 R03／R05 保留原指纹和不同证明范围。没有 macOS／Xcode、RP／发布签名／关联部署和物理设备时，AC05 整项不能计 PASS。既有业务消费者未实现的状态保持，生产 P02–P06 不由本任务批准。

结果见[平台报告](auth-privacy-platform-acceptance-validation-report.md)和[机器记录](../../services/api/authlab/platform-acceptance-verification.json)。
