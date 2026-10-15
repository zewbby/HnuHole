# 2026-10-15 第三项实际执行源码归档

这些文件与 `E:/HnuHole-community-f4-20261012/stage3-execution-20261015` 中实际执行源码逐字节一致，摘要在 `docs/design/community-android-stage3-device-validation-20261015.json` 的 `executedSourceArchive`。它们记录一次隔离实验，不是可对任意环境运行的通用初始化器；保留硬编码的本轮路径、owner、固定SHA和一次性started/journal守卫。无秘密值、账号fixture或设备原始截图。

- `lab.py`：本轮新建 C/V、正式迁移/授权、Gate/watch、TLS代理。`prepare`拒绝已有lab；不可对现有环境重放。proxy只转发真实响应，已批准的一次204丢弃及原锚点hash核对用于未知结果测试。
- `observe-lab.py` / `final-owned-sql.py`：本轮私有材料下的owner校验、受控代理/SQL脱敏观察；后者只观察不更新数据库。不能接其他DSN。
- 两份Dart测试：真实AuthFlows创建两个合成夹具，以及真实恢复后原密码/恢复码/旧注册token拒绝。文件vault只用于主机夹具，不代证原生。旧注册token在重设前已被替换，该断言不独立证明reset撤销活跃会话。
- 三份shell wrapper：一次性夹具、重设后检查及最终七阶段；固定本轮owner/路径。依赖已审查的社区专用env和SDK锁。将Dart测试复制到独立镜像 `apps/mobile/integration/` 才能解析既有相对helper/import，不直接从此目录执行。

当前lab、账号和started标记均存在，**不得删除标记后重跑**。复验需先核对最新交接，准备新的明确归属根/一次性库/日志与相应fixture，审查路径改动后运行；涉及RP/关联/签名/安全配置或手机均按用户授权另核。此归档不含ADB/手机操作入口。

已执行命令、结果、失败和设备窗口结束情况见[实测报告](../../../docs/design/community-android-stage3-device-validation-20261015.md)。手机部分为PARTIAL，不将主机夹具或代理计数包装为系统provider拒绝。
