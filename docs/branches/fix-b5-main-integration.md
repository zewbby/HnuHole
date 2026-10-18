# codex/fix/b5-main-integration

基于最新主线接入 B5 验收增量，修复闭号清理失败时的页面状态与关闭图片 API 后的生命周期擦除权限。

核对日期：2026-10-17。基线 `b164762b8cd58da592bf645cc4e2ada738bb79ec`；[PR #9](https://github.com/zewbby/HnuHole/pull/9) 已于 2026-10-17 Squash Merge，提交 [`eff7461`](https://github.com/zewbby/HnuHole/commit/eff746154a23a48896b420fa358ae481d595a7d8)；受影响回归、最终 head CI 与独立审查通过，未部署或发布。原整树迁移 PR #8 已关闭，由此增量交付替代，不覆盖主线已有功能。

详细结果以[B5 整合报告](../design/auth-privacy-b5-main-integration-report.md)、[机器记录](../design/auth-privacy-b5-main-integration-verification.json)、[独立审查](../design/auth-privacy-b5-integration-review-20261016.md)和[模块台账](../design/module-acceptance-ledger.json)为准。历史 B5 的 24/24 属于固定原认证版本，不是当前候选的设备验收。

## 交付核对

最终送审 head：`58e2669a8bf0387815472d75d9c78369064a2759`。实现提交 `c6ab509`，CI 环境修复 `c59d97f`；最终提交补录验证证据。GitHub 返回 merged=true，拉取的 origin/main 与上述合并提交一致。最终检查详见机器记录 `ciAtFinalHead`。
