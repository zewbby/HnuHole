# FEED-BACKEND-01 新版帖子列表后端

- 更新：2026-10-19。
- 分支：`codex/feat/feed-backend`，独立 worktree；基线为最新远端 main `fc2348f`。
- 状态：`BACKEND_SCOPED_PASS`，实现与本地验证完成，PR／远端 CI 待登记；未合并、未部署。
- 范围：HEAT-07 真实浏览及账号每日去重、按时间排序的跨通道稳定游标、账号级通道屏蔽偏好与分页前过滤。
- 边界：沿用现有会话、最终 C Gate 和匿名投影；兼容旧接口；不扩展热度算法、搜索、通知、私信或客户端页面。
- 完成标准：迁移空库／升级与受限权限、真实 PostgreSQL／HTTP 回归、Go build/test/vet、完整 OpenAPI 校验和适用 CI；接口接线说明与模块交接一起送审。
- 交付：新增0019、真实浏览总量／账号上海日去重、新时间列表和账号屏蔽；旧公开 DTO 与接口保持原样。精确字段与前端接入顺序见[接线契约](../design/feed-backend-contract.md)及 [OpenAPI](../../packages/openapi/feed-api.yaml)。
- 验证：Go1.22.2 全量宿主 test/build/vet PASS；真实 PG16.15／Goose3.22.1／race／TLS 29个顶层、61项含子项 PASS，零跳过；11份 OpenAPI 与旧文字帖契约 PASS。版本、命令、源码指纹与保留失败历史见[机器记录](../design/feed-backend-verification-20261019.json)。
- 存储回归：空库与带已有已发布帖子的0018升级均通过，旧内容／任务／通道不变，Down拒绝；受限角色、最终会话／Gate、原注销路径和缺权限启动拒绝已复验。测试库及进程由脚本收回。
- 下一步：提交本需求 PR，核对最终 head CI；独立同事／成员 review 待完成，不伪造批准。本次不自动合并或部署。
- 前端待办：新 main 上接 `/feed` 和偏好，正文显示后显式登记浏览；切通道／修改偏好后重载首屏，账号切换丢弃迟到结果。完整流程见上方契约；正式接线、设备和生产 NOT_RUN，不提升 B03／B04／B12 完整模块结果。
