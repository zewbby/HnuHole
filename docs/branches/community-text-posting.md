# 文字帖 T1–T3（历史工作与退役交接）

2026-10-18 用户要求补齐维护资料、归档原始证据、适配检查工具，经 PR 检查和审查后合并，
再退役 `codex/community-text-posting`，保留归档标签。交付分支：`codex/chore/archive-community-text`。
本 PR 合并后执行旧开发引用删除；实际合并／删除以 GitHub 为准，不为记录本 PR 自身递归建立文档 PR。

## 原分支成果与主线核对

旧分支固定头为 `514a944560988e3d8d599e6f9fe9d5d99fe07f88`，文字帖起点为 `0eff47a`。
以主线 `65a8dbf0e17a07edd42503620365e18241c92a76` 核对 T1–T3 的 101 个交付路径：
29 个字节完全一致，53 个已有后续演进，19 个路径在主线缺失。
缺失项全部是维护／历史资料及一个静态 checker，没有独有的 App／Go 实现或迁移文件。
这不是功能等价的动态验收，也不以“文件存在”代替当前产品检查。

文字帖 14 操作、任务恢复、草稿、列表／详情与作者删除已经由社区／图片集成继续发展。
`0013_community_text_posts.sql`、14 操作 HTTP 测试、文字摘要共享向量等与旧分支一致；
当前主线还包含图片及后续生命周期修复。原始提交不必是 squash 主线的祖先，不能按独有提交数重复合并旧源码。

## 本次交付

- 补入[领域术语](../../GLOSSARY.md)、[API 说明](../design/community-text-posting-api.md)、
  [事务设计](../design/community-text-posting-backend-design.md)和
  [ADR 0006](../adr/0006-text-post-command-publication-boundary.md)，修复 OpenAPI 的设计文档缺失入口。
- [归档目录](../archive/community-text-posting-20261008/README.md)原样保存全部 19 个缺失文件，
  包括历史设计、计划、T1–T3 报告／JSON、3 张截图及旧 checker。
  manifest 固定源路径、字节数、SHA-256 和 Git blob ID，检出不转换原件行尾。
- 适配 [checker](../../tools/check-community-text-contract.py)：保留14操作、公开字段、UNKNOWN／seal、
  Unicode16 和9份文字摘要向量约束，新增可选九图、固定重试归属及2份媒体摘要向量检查。
  [回归](../../tools/tests/test_community_text_contract.py)覆盖隐私泄露、越界字段／数量、错误摘要及归档完整性。
- 增加 [CI](../../.github/workflows/community-text-contract.yml)，执行全部 OpenAPI、静态契约和聚焦回归；
  README 将旧分支移入历史入口，最近五项只列已实际合并的 PR。

## 完整历史保留与退役范围

归档标签 [`archive/community-text-posting-20261018`](https://github.com/zewbby/HnuHole/tree/archive/community-text-posting-20261018)
固定指向 `514a944`，保留全部可达提交、旧源码、测试和当时的完整仓库。
后续开发从最新 main 新开需求分支；不得用旧整棵目录覆盖当前图片／认证实现。
原[固定交接](https://github.com/zewbby/HnuHole/blob/514a944560988e3d8d599e6f9fe9d5d99fe07f88/docs/design/HANDOFF.md)仍可追溯。

本次不运行设备测试、不改变数据库／SDK／账号／产品协议，不修改其他会话的工作区或验收结论。
原 T4 待验只属于旧交付版本，当前社区、Android、Passkey、iOS及生产状态继续跟随各自最新报告。

## 本次验证

本地使用任务专用 Python 3.12 环境和仓库固定 PyYAML 6.0.1／openapi-spec-validator 0.9.0：

- 全部 6 份 OpenAPI 完整校验通过，未修改契约文件。
- 当前 checker 通过14操作、9份文字及2份图片摘要向量。
- 聚焦回归 9 项通过，含隐私／归属／错误摘要负向注入及19份原件的 SHA-256／Git blob 核验。
- 协作工具回归 19 项通过；95个维护文档本地链接存在；差异空白检查通过。

首个全规范命令在 Windows 默认编码读取既有 YAML 时停止，显式 `-X utf8` 后全部通过；
Python 3.9 无法安装既定 validator，改用独立 Python 3.12 环境，未改固定依赖或共享环境。
独立 agent 已只读审查31份暂存变更，并独立复跑全部规范、checker、9项聚焦回归及19项协作回归，未发现阻断问题。
审查另要求在删除旧分支前确认归档标签的 peeled commit 精确为 `514a944`；执行结果以实际远端引用为准。
该审查不等于 GitHub 成员批准；实际远端检查以本 PR 最终 head 的 Actions 为准。
工具与文档检查不构成新一次产品、SQL、设备或上线验收。
