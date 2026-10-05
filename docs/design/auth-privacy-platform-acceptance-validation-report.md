# AC05 平台验收报告

日期：2026-10-05。分支 `codex/auth-privacy-handoff`，基线 `cbc99b010ba23bba42f76e2523269e3952b14392`，叠加未提交 AC04／AC05。任务范围与三步安排见[任务单](auth-privacy-platform-acceptance-plan.md)，精确源码摘要、结果与命令见[机器记录](../../services/api/authlab/platform-acceptance-verification.json)。

## 当前证明范围

AC05 整项保持 BLOCKED。Android 模拟器上的有范围结果和完整设备矩阵分开登记；B02 基础管理已有实现和既有回归证据，整模块仍 BLOCKED。本文不批准生产发布。

本轮新增[身份设备场景](../../apps/mobile/integration_test/identity_device_scenarios.dart)，通过[双进程入口](../../apps/mobile/integration_test/auth_security_device_test.dart)使用真实 FlutterAuthVault／Android Keystore。授权与身份 API 是显式测试提供者，不能将该探针与 AC04 R03／R05 合并称为完整 App→实际 C/V。注入 composing 输入、2 倍字缩放和 Flutter semantics 是平台运行的合成场景，不能代证物理键盘／OEM 输入法或 TalkBack 操作。

## 配置与环境核对

仓库及本机工程仅发现示例服务配置和测试 RP 值，未找到实际 RP 配置、assetlinks／AASA 部署文件或宿主关联域配置。示例 `community.config.example.json` 的 webAuthn 为 null；原生测试使用 `auth.example.invalid`。本轮没有外部部署清单，结论是当前可见材料不足以执行系统 ceremony，并非断言所有外部部署均不存在。正式域名、Android 签名来源／关联部署、Apple Team／Bundle ID 和关联域仍需要提供。

现成 Flutter 3.47.5／Dart 3.13.4、JDK 17.0.20、Gradle wrapper 9.3.1、Android API36 SDK／NDK28.2、Google APIs x86_64 模拟器可用。没有 macOS／Xcode 和 iOS 目标设备。用户明确授权本轮重建必要依赖并在验收后清理；临时 Linux Gradle／项目构建、共享 pub／APK 和模拟器数据使用专用目录，保留原有 SDK／AVD。

## 执行结果

| 执行项 | 本轮结果 | 证明边界 |
| --- | --- | --- |
| 四份 OpenAPI 完整校验 | PASS | 固定 validator 0.9.0／PyYAML6.0.1，含身份／目录契约 |
| Flutter analyze／mobile 单元与组件 | PASS，179项 | 新设备场景修复后重新 analyze 无问题；没有更改产品逻辑 |
| 完整 Android arm64 debug App | PASS | 标准构建及原生链接，未使用 prebuilt-debug init-script 绕过 NDK |
| vault／Passkey instrumentation 组装 | PASS | 当前两个 Android 包均编译／组装 |
| Android vault | PASS，16项＋3组双进程 | 模拟器真实 Keystore／文件提交；故障与丢钥场景包含显式注入，2次受控杀进程的读取对端均通过 |
| Passkey Dart／Android codec | PASS，9项／5项 | 策略、取消／迟到及 codec／归属；没有系统 ceremony |
| Flutter 双进程 native AuthStore／身份 | PASS，每阶段3个 widget 场景 | write PID7062、read PID7189；恢复合法草稿，保留原操作键且不自动重提，切换账号隐藏旧编辑器，登出围栏阻止旧token启动认证；合成 composing／2倍字／语义通过 |
| Gradle9.3.1下载完整性 | PASS | 下载包 SHA256 与 services.gradle.org 公布值一致，摘要见机器记录 |
| 交接结构／源码摘要 | PASS | 284个当前源码／资源文件；149个隔离移动端、包及工具输入逐项比对，仅声明的文本换行转换，协议向量与PNG保持字节精确 |

上述 PASS 只覆盖各行范围。Go／SQL／race／vet及实际 C/V 没有在 AC05 重跑；AC05 只补测试／runner和交接，产品、迁移及授权实现未改，保留[AC04证据](auth-privacy-regression-validation-report.md)的原指纹与证明范围。

## 已发现问题与处理

首次 Gradle 构建无法从插件仓库解析 kotlin-dsl 6.4.2；核对后确认 WSL 直连依赖源超时，Windows 本机连接可用。本轮使用已有本地代理，临时转发只绑定 WSL 虚拟接口，JVM 代理属性只写专用 Gradle 用户目录。未改变项目版本、依赖源或 TLS 校验。构建重试与后续结果逐项登记。

Windows 沙箱身份访问已有 Flutter SDK 时触发 Git ownership 检查，改用授权的正常宿主执行环境；未添加全局 safe.directory。锁定 mobile 依赖没有升级。

临时源码包首次漏带启动图标，AAPT 报 `mipmap/ic_launcher` 缺失；补齐仓库 PNG 资源后标准 App 构建通过，未修改产品资源。

设备场景首次错误要求“草稿表为空”，而输入框聚焦已保存合法空草稿；改为对比活跃 composing 前后持久状态不变。随后断言均通过，但 `SemanticsHandle` 的 addTearDown 晚于结束检查，整场仍 FAIL；改为在测试体 finally 中卸载页面并释放句柄后，重新构建两个 APK、两阶段均 PASS。失败及诊断日志摘要留在机器记录，不覆盖成首次成功。

## 未验项目与下一入口

| 项目 | 状态与原因 | 所需条件／入口 |
| --- | --- | --- |
| 系统 Passkey 绑定、移除、可发现恢复与取消／冻结／接替 | BLOCKED：缺实际 RP／发布签名／平台关联部署 | [Passkey 包说明](../../packages/auth_passkey/README.md)、R08／R09；准备配置后执行真实系统交互与实际 C/V |
| iOS 完整构建、原生链接、Keychain／双进程与 AuthenticationServices | BLOCKED：无 macOS／完整 Xcode、签名与设备 | [iOS 测试入口](../../apps/mobile/ios/RunnerTests/RunnerTests.swift)、R06／R09；marker／codec 历史证据不能代证 |
| Android 物理设备／厂商锁屏与硬件差异、OEM 中文／日文组合输入、辅助服务 | NOT_RUN：本机只有模拟器；合成事件覆盖有限 | R09／R10 与 [模块交接](module-acceptance-handoff.md) 的 B02 设备矩阵 |
| 系统备份／跨设备恢复、真实卸载重装生命周期 | NOT_RUN：本轮故障注入与进程探针不含系统级备份 | N01／N02 和 R09；独立准备可确认归属的设备／备份材料 |
| 完整手机 App→实际 C/V→SQL | NOT_RUN：本轮设备 API 为替身，R03 和 R05 为不同证明边界 | R03／R05／R09 需整合真实端点、TLS／RP与设备配置后补测 |
| 帖子、评论、聊天等消费者及生产分权／灾备／独立审计 | NOT_RUN：消费者未实现，生产证据未提供 | 后续[业务契约](auth-privacy-business-contract.md)；本分支不扩展 B03／B05 等完整业务片 |

完成本机可执行证据整理后进入 AC06 最终交接，保留平台阻塞，不把延期当作 PASS。未提交、推送或部署本轮修改。

## 清理与交付状态

专用 Linux Gradle／源码／build／debug签名私钥、Windows pub／APK／大日志／临时 AVD 数据和本轮生成的 Flutter 测试产物已清理，相关进程已停止；保留现成 Flutter／JDK／SDK 和原有 AVD 配置／SDK内部既有目录。源码、测试和小型脱敏验证记录保留。WSL 清理内联参数首次转义失败，改为严格 realpath／OWNER 核验脚本后独立确认目录不存在；ADB console 的跨用户令牌差异通过精确识别专用 AVD 进程处理，未停止未知模拟器。

模块台账 currentAC05／交接结构与源码摘要检查通过；历史 AC04 指纹和通过记录保留。临时打包脚本／归档已删除并核验不存在。本轮未提交、推送或部署。
