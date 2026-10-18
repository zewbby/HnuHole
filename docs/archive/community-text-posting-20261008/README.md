# 文字帖 T1–T3 历史归档

归档日期：2026-10-18。固定来源为
[`514a944560988e3d8d599e6f9fe9d5d99fe07f88`](https://github.com/zewbby/HnuHole/tree/514a944560988e3d8d599e6f9fe9d5d99fe07f88)，
原开发分支 `codex/community-text-posting`。完整提交历史由
[`archive/community-text-posting-20261018`](https://github.com/zewbby/HnuHole/tree/archive/community-text-posting-20261018)保留。

本目录保存旧分支相对主线 `65a8dbf` 缺失的 19 个文件，全部使用 Git blob 原始字节，
不改写旧 PASS／未验、版本、摘要、日期、链接和“未提交”等当时描述。
它们不是当前产品验收，也不作为新的测试输入自动执行。

## 当前维护入口

- [术语](../../../GLOSSARY.md)
- [当前 API 说明](../../design/community-text-posting-api.md)
- [当前事务设计](../../design/community-text-posting-backend-design.md)
- [ADR 0006 维护说明](../../adr/0006-text-post-command-publication-boundary.md)
- [分支退役与验证记录](../../branches/community-text-posting.md)

## 原始资料与证据

`original/` 下保留旧仓库相对路径。原文内的相对链接属于旧仓库，阅读完整关联内容时使用上面的固定提交链接；
不要把旧文档的相对链接解析到当前主线，再将缺失或不同内容当作原验收事实。

| 类别 | 本地原件 |
| --- | --- |
| 领域术语 | [GLOSSARY](original/GLOSSARY.md) |
| 决策 | [ADR 0006](original/docs/adr/0006-text-post-command-publication-boundary.md) |
| 设计与范围 | [API](original/docs/design/community-text-posting-api.md)、[后端](original/docs/design/community-text-posting-backend-design.md)、[计划](original/docs/design/community-text-posting-plan.md) |
| T1 | [报告](original/docs/design/community-text-posting-t1-report.md)、[机器记录](original/docs/design/community-text-posting-t1-verification.json) |
| T2 | [报告](original/docs/design/community-text-posting-t2-report.md)、[机器记录](original/docs/design/community-text-posting-t2-verification.json) |
| T3 | [报告](original/docs/design/community-text-posting-t3-report.md)、[测试摘要](original/docs/design/community-text-posting-t3-test-summary.json)、[机器记录](original/docs/design/community-text-posting-t3-verification.json) |
| T3 截图 | [通道列表](original/docs/design/evidence/community-text-posting-t3/channel-list.png)、[我的帖子](original/docs/design/evidence/community-text-posting-t3/personal-posts.png)、[编辑页](original/docs/design/evidence/community-text-posting-t3/text-editor.png) |
| 服务端专项 | [HTTP](original/services/api/authlab/community-text-post-http-verification.json)、[schema／权限](original/services/api/authlab/community-text-post-schema-verification.json)、[runtime](original/services/api/authlab/community-text-posting-t2-runtime-verification.json) |
| 旧静态工具 | [原始 checker](original/tools/check-community-text-contract.py)，仅归档；当前版本位于仓库 tools/ |

[manifest.json](manifest.json)逐项记录来源路径、字节数、SHA-256 和 Git blob ID。
当前契约回归会校验这 19 份原件的完整性；原始 `.py` 不作为当前检查入口。

为使跨平台检出保留精确字节，本目录 original/ 由 `.gitattributes` 禁用文本转换。
