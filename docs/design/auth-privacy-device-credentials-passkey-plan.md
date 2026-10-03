# 设备与恢复凭据管理＋原生 Passkey 实施任务单

日期：2026-10-02（Asia/Shanghai）。只基于 `codex/auth-privacy-handoff`，HEAD `3edf8c4c2f888f3d0cf9783d6ea358e2ab30383e`，保留此前 T0–T6 和模块验收交接的未提交改动。用户授权本片开发及测试源码；动态／设备验收可按 AGENTS 延期。

## 目标与边界

用户能查看当前及最近接替设备、主动退出，重新输入密码后轮换恢复码／绑定或移除 Passkey，并在登录页通过可发现 Passkey 进入现有密码重设流程。恢复码只展示一次，隐藏后完整确认；未知提交持久保存原操作核对能力，不保存密码、新恢复码或原生证明。

沿用 C 最终 Gate、当前会话／凭据版本及操作归属规则；Passkey 不建立普通会话、不自动登录或取消注销。V Gate、身份／帖子、生产部署与全局 UI 重设计不在本片。用户已明确尚无 RP 域名、Android 签名或 iOS Team 关联配置：实现配置边界，平台关联部署与真机成功证据单列，不伪造可运行部署值。

## 顺序与归属

| 步骤 | 源码与动作 | 证明／依赖 |
| --- | --- | --- |
| D0 | 读 `AGENTS.md`、HANDOFF、账号／恢复规则及 B01/N03/A09 台账；核实已有 HTTP helper 与正式 runtime 缺口 | 分支／工作区、实际工具检查；不覆盖历史证据 |
| D1 | `authprivacyruntime/config.go`／`server.go` 配置并装配固定 WebAuthn；`passkey_verification.go` 单列 Android 签名 origin，iOS 沿用关联域 HTTPS origin | 配置负向、origin／RP／UV／challenge 用例；依赖原授权版本边界 |
| D2 | `community_credentials`／HTTP 增加无秘密 `credential-change-result`；复用意图／挑战和持久结果，最终 Gate 内判断原会话与终态 | 轮换／绑定／移除未知提交、冻结、接替、过期、清理与归属；OpenAPI 同步 |
| D3 | 新 `packages/auth_passkey` Dart channel＋Android Credential Manager＋iOS AuthenticationServices，bounded JSON、系统取消／并发及生命周期 | 桥契约和 native 验证测试；真实平台需关联域及签名；不覆写 clientDataJSON/origin |
| D4 | `credential_management_api.dart`、`security_management_controller.dart`、AuthStore／codec 持久原键和同会话 fence；HTTP 权威截止先存再发布 | 单元／TLS 契约：写失败不提交、重启核对、迟到响应、接替、Gate503、终态不回退 |
| D5 | `security_management_screen.dart`、main／AuthScreen 路由；当前／最近设备、一次码展示／确认、密码复验、系统 Passkey、两步移除、原结果核对；AuthFlows 复用密码重设 | Widget 表单、无原码返回、退出、错误和小屏／大字体；依赖 D1–D4 |
| D6 | 真机 AuthStore 和进程重启入口、iOS Keychain XCTest、原生桥测试与平台关联配置检查；报告、机器记录、B01/N03 等台账更新 | 实测工具不足记 BLOCKED／NOT_RUN，设备替身不代证 C/V 或真实 Passkey；完整回归后验收 |

## 关键契约

- 管理 API 仅当前 Bearer；成功解析且持久保存 `Session-Expires-At` 后发布界面数据。401 清本权限；503 暂停显示保留安全 token。
- `GET /api/v1/auth/credential-change-result` 使用 Bearer、`Credential-Change-ID` 和原 `Idempotency-Key`，只返回 PENDING／COMMITTED／NOT_COMMITTED。未知 ID 不推断未提交；仍有效意图不得误报终态，过期必须在同锁和最终 Gate 下终止。
- 原生桥只传受信服务端的 publicKey 选项及真实系统证明；可发现恢复不指定账号／用户名或 allowCredentials。Android origin 绑定已配置签名摘要；iOS 依赖 RP 的 AASA 与 host entitlement。
- 原码／密码／attestation 不进 AuthStore、普通日志或剪贴板。未知结果在进程重启后核对原键；退出／新登录／新请求使旧 callback 无权发布。
- 取消客户端 sheet 不能撤销服务端已提交事实；只丢临时 UI 状态，持久核对记录保留。

## 执行与回退

现有命令：仓库根 `git diff --check`、OpenAPI checker；`services/api` 的 `sh authlab/run-isolated.sh`、`go test -race -count=1 -p 1 ./...`、`go vet ./...`；`apps/mobile` 的 `flutter analyze`／`flutter test`，真实 HTTPS fixture 用 `sh authlab/run-mobile-isolated.sh`。新增设备入口以实际写入的 README 为准，不杜撰已存在命令。

缺工具时继续源码开发和轻量可用检查，不恢复大型 SDK／缓存。动态 DB 仅明确归属的一次性库；Windows 服务端及 Gate 文件在 WSL2 Linux 文件系统。故障冻结并前向修复，保留终态及原核对记录，不回退旧 validator。任务收尾必须同步 `module-acceptance-handoff.md`、`module-acceptance-ledger.json`、HANDOFF、progress 与本片报告，提交／推送／部署另按用户授权。
