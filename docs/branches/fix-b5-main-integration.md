# codex/fix/b5-main-integration

基于最新主线接入 B5 验收增量，修复闭号清理失败时的页面状态与关闭图片 API 后的生命周期擦除权限。

核对日期：2026-10-16。基线 `b164762b8cd58da592bf645cc4e2ada738bb79ec`；当前准备提交送审，尚未合并或发布。原整树迁移 PR #8 将由此增量交付替代，不覆盖主线已有功能。

详细结果以[B5 整合报告](../design/auth-privacy-b5-main-integration-report.md)、[机器记录](../design/auth-privacy-b5-main-integration-verification.json)、[独立审查](../design/auth-privacy-b5-integration-review-20261016.md)和[模块台账](../design/module-acceptance-ledger.json)为准。历史 B5 的 24/24 属于固定原认证版本，不是当前候选的设备验收。
