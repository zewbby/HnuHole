# 工程基线（历史工作）

确定 Flutter、Go、通信与持久化的工程基线。

状态：2026-10-17 按用户指令退役，停止在 `feature/engineering-baseline` 上继续开发，并从 README 活跃分支一览移至历史入口。后续开发从最新 `main` 新建需求分支。

退役交付分支：`codex/docs/retire-engineering-baseline`。本次仅调整索引和历史记录，归档原分支并删除其开发引用，不合并旧产品树、不修改功能或验收结论。交付 PR 的实际合并状态与分支删除结果以 GitHub 为准；不为记录本次 PR 自身递归建立文档 PR。

核对日期：2026-10-17。

## 进度

历史固定提交 `9d69213cefc322d752726cd12e860946ed87de5b`，工程决策由后续实现分支沿用。主线 [PR #2](https://github.com/zewbby/HnuHole/pull/2) 已导入后续认证、社区及图片实现；退役不移除这些源码、ADR 或验收证据。

原分支与 main 的提交历史并未全部直接合并：退役前相对 `af272dc6d3a43d82cadb95d26f36f081d2fbfa67` 有 7 个独有提交，不将历史分叉误记为整分支已合并。已建立并核对远端归档标签 [`archive/engineering-baseline-20261017`](https://github.com/zewbby/HnuHole/tree/archive/engineering-baseline-20261017)，精确指向上述原分支头，保留全部可达提交和原始文件，删除开发分支后仍可追溯。

## 剩余事项

早期交接的未完成事项须结合当前任务记录读取，不把旧设计阶段当成当前产品验收。

本次退役不推进 iOS、完整产品或生产验收，不清理 SDK、缓存、数据库、设备或其他会话目录。实际云服务、外部主体与部署等后续决策仍按[主线进度](../design/progress.md)和[最新接续说明](../design/HANDOFF.md)推进；旧交接中的“认证尚未实现”等描述仅属于原历史版本。

核对提交：[`9d69213`](https://github.com/zewbby/HnuHole/commit/9d69213cefc322d752726cd12e860946ed87de5b)。

## 详细记录

- [工程基线 ADR](../adr/0001-engineering-baseline.md)
- [通信与持久化 ADR](../adr/0002-communication-and-persistence-baseline.md)
