# B5 主线增量整合

日期：2026-10-16（Asia/Shanghai）。分支 `codex/fix/b5-main-integration`，基于主线 `b164762b8cd58da592bf645cc4e2ada738bb79ec`，接续用户指定的本地 B5 候选。交付状态见[分支记录](../branches/fix-b5-main-integration.md)；实际命令、源码摘要与结果见[机器记录](auth-privacy-b5-main-integration-verification.json)。

## 实现

保留主线已有的帖子图片入口、业务存储与账号生命周期，只引入缺失的 B5 测试和历史证据。三个夹具通过有类型的 `b5CandidateRoot` 查找当前公开的 `HnuholeApp`；device 与 Bitwarden 候选同时修正 24 字节随机密码调用为现有守卫接受的 32 字节。旧报告、三份机器记录和原 checker 保持原始字节。

修复闭号结果持久化成功后业务清理抛错仍显示旧 PENDING 状态的问题：先持久化，在 epoch/closureId 围栏内恢复权威页面状态，再清理原账号业务数据。清理失败仍保留终态标识供重试，不影响后来登录的账号。

真实联调准备暴露了图片生命周期权限契约缺口。即使图片 API 关闭，撤销、删除、封禁、身份删除及闭号也要清除已有图片字节。C runtime 增加 `payload`、`erased_at`、`grant_digest`、`grant_expires_at` 四列更新权限；启动时核验缺失权限，审计仍拒绝上传/验证字段、整表更新和恢复/业务角色访问。真实 SQL 回归覆盖六种生命周期、他账号保留和墓碑不可复活，并逐项撤销必需列、注入十种越权授权后核对明确拒绝及恢复。

## 验证与范围

主应用分析、383 项宿主测试与 bundle 已通过；原生 Passkey 包分析及 9 项 Dart 测试、vault 包分析通过。签名构建守卫 15 项、协作工具 19 项通过。完整 SQL/race/vet、受限角色真实 PostgreSQL、R03 实际 C/V、图片组件及 Android 构建正在本任务独立 Linux 工作副本执行，结果汇总到机器记录后才计作通过。

[独立审查](auth-privacy-b5-integration-review-20261016.md)发现的两个候选夹具错误已修复并复核。审查未发现其他阻断；本增量未修改主线 Android/Passkey/vault 原生实现，不要求为合并重新跑完整双机窗口。候选原生设备验收仍为 `NOT_RUN`，构建和宿主 mock 不代证原生行为。

## 历史证据

历史 B5 提交为 `ea5cc52840f009b02106f928c444e423c6e61b3e`，产品基线及 B6 为 `d859cb05c772cdf8d8b75e439a2bfedf0414dd46`。原 B6 的 22 PASS/2 BLOCKED、B5 首轮的 23 PASS/1 FAIL、Bitwarden BLOCKED、同步路线最终 24/24 及全部失败历史分别保留。两个 B5 checker 在固定 B5 副本、完整 B6 checker 在固定 B6 副本复核通过；本轮没有重新发起手机认证。

[历史复现记录](auth-privacy-b5-historical-reproduction.json)保留 Windows 换行及构建夹具摘要的复现过程。162 个历史产品输入与主线有 141 相同/21 不同；历史集合之外主线另有 55 个 runtime 文件，完整清单及候选额外变更另记。历史 `nonIOSDevelopmentAcceptancePassed=true` 仅属于原输入与设备链，本候选保持 false，不以历史 APK 证明新 APK。

## 后续边界

iOS、原生设备专项复验、生产及未来业务保持各自门槛。原控制工具的固定机器路径、包名和设备约定属于历史环境，不直接用于当前候选。无部署或发布。
