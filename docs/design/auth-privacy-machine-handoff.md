# 匿名分支：另一台机器接续入口

日期：2026-10-04（Asia/Shanghai）。仓库 `zewbby/HnuHole`，分支 `codex/auth-privacy-handoff`。本轮从远端基线 `d624ea30943a2b12096c20dbeefd844ba0e5e840` 接续；交付 commit 以包含本文件的提交为准。

## 当前交付与证据

> **2026-10-04 最新验证与环境交付：**基于远端 `codex/auth-privacy-handoff` 的 `d624ea30943a2b12096c20dbeefd844ba0e5e840`。Flutter分析与175项mobile测试、真实Dart→HTTPS→PostgreSQL R05、Android完整app构建、16项vault＋3组跨进程探针、9项Passkey Dart／5项Android codec和真实Flutter双进程共享AuthStore探针均PASS；Go/SQL/race/vet、R03实际C/V进程及完整OpenAPI已在本轮复验。环境与可复验命令见[本机环境](local-test-environment.md)，精确证明范围／失败修复见[最新记录](../../services/api/authlab/identity-runtime-test-verification.json)。**B02整模块仍BLOCKED：AC01 V Gate、AC02身份整账号关闭尚未实现，iOS、真实Passkey ceremony和物理设备／B02设备矩阵仍未验。**用户要求保留D盘工具环境、删除全部测试缓存和临时产物，完成后直接推送对应分支。


本轮修复真实执行发现的移动端页面语法、异步测试时序、重复加载与Passkey负向测试夹具问题；增加D盘环境加载脚本、原生探针脚本与Flutter drive入口。源码、测试和小型脱敏记录提交到远端；SDK／缓存／APK／数据库不纳入Git。

R03为实际非owner C/V服务＋HTTPS/mTLS／迁移／Mailpit；R05为真实Dart＋HTTPS＋handler＋SQL，使用内存vault；Android双进程为真实原生vault＋授权API替身。三者证明范围分别登记，不能合并声称完整真机端到端已通过。

## 拉取与阅读

```sh
git status --short
git fetch origin codex/auth-privacy-handoff
git switch codex/auth-privacy-handoff
git pull --ff-only origin codex/auth-privacy-handoff
git rev-parse HEAD
```

保留已有改动，不使用reset／clean丢弃工作。没有本地分支时可在fetch后 `git switch --track origin/codex/auth-privacy-handoff`。服务端、POSIX runner和Gate文件放WSL2 Linux文件系统。

依次阅读根[AGENTS](../../AGENTS.md)、[HANDOFF](HANDOFF.md)、[匿名清单](auth-privacy-closure-checklist.md)、[模块交接](module-acceptance-handoff.md)／[机器台账](module-acceptance-ledger.json)、[本机环境](local-test-environment.md)。B02实现与剩余边界见[身份报告](identity-management-validation-report.md)、[任务单](identity-management-plan.md)和[机器记录](../../services/api/authlab/identity-management-verification.json)。

## 剩余工作

1. AC01：实现V独立Safety Gate，不能以C Gate或本次测试替代。
2. AC02：将现有身份接入整账号正式关闭生命周期，协调最后一个身份、累计创建、永久墓碑／回执和独立注销投影。
3. AC03：完成指定隐私／日志范围核对；后续帖子／聊天／治理契约继续单列，不扩展本分支业务。
4. AC04：现有B02 R03/R05已补并通过；未来AC01/AC02实现后需补对应迁移和真实故障链。
5. AC05：补macOS完整Xcode／iOS、RP与平台关联身份、真实Passkey系统ceremony、物理设备和B02设备矩阵。
6. P02–P06：运营分权、发布、备份／灾备及独立审计仍缺；生产未放行。

Windows Gradle有本机loopback问题；使用已通过的WSL构建，再用Windows Flutter drive运行预编译APK。模拟器通过不代表物理硬件、iOS或平台ceremony通过。环境脚本只作用当前终端；测试缓存清理后首次复验需要重新获取依赖和Gradle wrapper。

一次性runner会reset schema，只能使用runner自己建立的测试库。不能传真实用户／未知DSN，不能全局prune。修复共享边界后重验相应场景，保留历史版本，不把历史结果换绑新指纹。[一致性检查](../../tools/check-identity-handoff.py)仅核对台账／文件／摘要，不能代证动态验收。

## 历史证据

2026-10-03的后端／实际进程及更早的缺工具记录保留在[最新记录的attemptHistory](../../services/api/authlab/identity-runtime-test-verification.json)与[原身份记录](../../services/api/authlab/identity-management-verification.json)。旧机器路径、缺Flutter与“尚未补B02链”不再描述当前环境。
