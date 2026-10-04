# 身份管理验证与剩余验收

日期：2026-10-04（Asia/Shanghai）。分支 `codex/auth-privacy-handoff`，远端基线 `d624ea30943a2b12096c20dbeefd844ba0e5e840`。实现任务见[身份计划](identity-management-plan.md)，最新源码摘要与命令结果见[验证记录](../../services/api/authlab/identity-runtime-test-verification.json)，历史原版本检查见[身份机器记录](../../services/api/authlab/identity-management-verification.json)。

## 当前结论

基础身份管理的后端SQL／实际服务、客户端Dart和真实Dart→SQL场景已取得运行证据；Android构建、原生vault和共享认证跨进程验证通过。**B02仍为基础管理已实现、业务联动待实现，整模块BLOCKED。**身份整账号关闭AC02未实现，原生身份草稿／输入法／无障碍矩阵未验，不能以共享AuthStore探针代证。

| 检查 | 结果与范围 |
| --- | --- |
| Go全量SQL／race／vet | PASS，一次性C/V PostgreSQL库；没有以无DSN跳过计通过 |
| R03实际cmd | PASS，非owner权限、HTTPS/mTLS、正式迁移、升级10→11、身份CRUD／原回执／重启、冻结／恢复和缺表／缺DML拒绝启动 |
| R04 mobile | PASS，分析无问题；175项单元／controller／widget，含身份35项及共享认证／安全管理回归 |
| R05真实Dart＋SQL | PASS，身份CREATE/PATCH/DELETE提交后丢响应、同键核对、客户端对象重建、会话接替、终态拒绝与配额；vault为内存替身 |
| R07 Android | PASS，完整ARM64 app与两个插件；API36模拟器vault16项和3组正常／提交前／同步后中断探针 |
| R08 Passkey | PASS，Dart9项和Android codec5项；真实系统ceremony仍BLOCKED |
| R09 Flutter原生共享状态 | PASS，write/read两个不同PID，退出标记／原凭据key跨进程保留，启动不调用授权API；API为专用替身 |
| 契约／生成／交接 | PASS，四份OpenAPI完整校验、固定sqlc/oapi生成与本地baseline比较、生成Go编译／vet、5项关联生成器测试、台账／指纹／链接和补丁检查 |

## 本轮修复

两处页面括号遗漏导致编译失败；补齐后通过分析和Android编译。安全管理页只在controller未加载时自动load，避免重复异步加载。取消围栏测试在实际持久边界同步触发，不再使用延迟microtask错过边界。widget异步crypto／storage操作在runAsync内通过真实按钮执行并等待完成。Passkey负向响应夹具使用动态值Map，让缺失userHandle验证真正到达校验器。

第一次Flutter设备read阶段失败：默认drive清理会卸载app，删除write阶段数据。新增两阶段启动脚本使用keep-app-running后显式force-stop，再安装相同签名的read APK；不同PID的最终复验通过。失败原因与复验保留，不修改产品存储来迎合测试。

## 尚未验与未实现

- AC01 V独立Gate、AC02身份整账号关闭生命周期未实现；与后续帖内绑定、旧内容／私聊投影、治理、媒体上传分别登记。
- B02物理设备IME、无障碍、小屏大字平台矩阵和身份专属草稿／意图跨进程恢复未执行。已有widget布局测试通过，只证明相应Flutter测试范围。
- iOS完整app／Keychain／进程探针缺macOS完整Xcode；两平台系统Passkey缺RP、发布签名、Team与关联部署。
- Android物理设备硬件安全等级、锁屏／OEM／完整备份矩阵未验。模拟器原生故障注入覆盖的精确范围以测试源码／最新记录为准。
- AC03与P02–P06隐私／生产／独立审计继续待执行，生产未放行。

## 接续与资源

环境安装、各runner和原生两阶段命令见[本机环境](local-test-environment.md)；总体范围见[匿名清单](auth-privacy-closure-checklist.md)、[模块交接](module-acceptance-handoff.md)和[台账](module-acceptance-ledger.json)。所有测试源码保留；缓存清理后复验需重新pub get及获取wrapper。工具SDK／JDK／AVD配置按用户选择留在D盘，测试产物／缓存／临时库清理状态以最新机器记录为准。

历史检查保留当时命令、失败、版本及摘要；旧缺工具结果在机器记录的历史部分，不描述当前测试结论。
