# 帖子图片后端（历史工作）

实现帖子九图原字节存储、补传和受保护读取后端。

原开发分支：`codex/post-image-media`（本地和远端均已删除）。后续开发以 `main` 为基线；本文保留历史交付与验收入口，不依赖原分支继续存在。

核对日期：2026-10-16。

## 进度

固定交付 d893378（实现 efccade）：原字节 SQL 存储、完整校验后公开及撤销读取已实现；已由后续联合任务通过 [PR #2](https://github.com/zewbby/HnuHole/pull/2) 合入 `main`，合并提交为 [`4fc19ba`](https://github.com/zewbby/HnuHole/commit/4fc19baf8655da4b012a0a6dd2c8c9a7b2bab398)。原分支清理不移除主线实现、历史交付记录或验收证据。

## 剩余事项

生产存储/配额/备份与升级策略独立待定；真实联调证据由后续联合报告提供。

核对提交：[`d893378`](https://github.com/zewbby/HnuHole/commit/d893378a8224b9c7a3b9d2bc9681a6ea508d5587)。

## 详细记录

- [后端契约](../design/post-image-media-contract.md)
- [后端验证](../design/post-image-media-verification-20261015.json)
