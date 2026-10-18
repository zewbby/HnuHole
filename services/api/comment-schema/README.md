# 评论文字后端的数据库与运行方式

本轮规范 SQL 为 `../migrations/0016_comments.sql`，运行时授权为 `../../../infra/postgres/grant-comments.sql`。0016 紧随已经合入 main `1b78f42`（PR #18）的真实 `0015_reports_moderation.sql`。本分支已正常整合该 main，不允许缺号、乱序或伪造迁移。

SQL 沿用 `c_posts` 的永久帖内身份绑定、公开身份标签和账号 stop generation。首次参与者绑定与评论任务/回执在同一事务提交；Go 的 Accept/Retry/Abandon/Publish/Fail 仍是业务规则来源。已有绑定不可变，重试不接受替换身份或目标。DDL 约束归属、同帖同楼回复、任务版本、唯一发表和永久回执；Down 明确拒绝静默丢失事实，修复使用前向迁移。

运行 PostgreSQL 16、Go 1.22.2、Goose v3.22.1 的非 root Linux 环境：

```sh
export PATH="$(pg_config --bindir):$PATH"
bash services/api/authlab/run-comment-text-isolated.sh
```

runner 创建本次独立 C/V 业务库、空库安装库、升级库和非超级用户角色，拒绝外部 DSN。PG 无 TCP，仅使用私有 Unix socket，默认端口 55463；退出只清理本次 mktemp 目录。socket 使用短路径以符合 Unix 路径长度限制；Go/Gate 临时文件使用 Linux 文件系统。真实 Goose 验证空库 0001–0016、0014→真实0015→0016，以及拒绝 Down 后版本仍16。SQL/HTTP fixture 另验证所有实际迁移与真实 C Gate/会话/受限角色，不以 raw fixture 代替 Goose 证据。

开发 runtime 的 schema 安装与授权顺序为 Goose up → grant-community.sql → grant-comments.sql。前者包含评论功能关闭时仍需要的身份/账号生命周期最小清理授权；后者才授予评论命令/快照写入。独立 recovery、business、V 角色没有评论正文或任务读取权。

显式启用 `posts` 后，配置：

```json
{"comments":{"commandKeyFile":"comment-command.key","fingerprintKeyFile":"comment-fingerprint.key"}}
```

两份独立 32 字节用途密钥受现有权限和全用途查重约束。缺省关闭；缺表、hook、最小授权或历史密钥不匹配会拒绝启动/冻结。worker 使用已有有界调度器，重新运行不会重复发表。真实接口与 JSON 形状见 `packages/openapi/comment-text-component.yaml`，原完整评论契约仍为设计快照。

已受理文字只存服务任务，没有评论长期草稿。放弃、删身份和正式关闭账号擦除未发布文字；已发布文字保留公开事实及安全作者投影。审核下架/删除帖子不能读评论或继续发送。5 分钟读取快照只存顺序 ID，不存正文，过期后在下一次建立快照时清理。每账号最多128活跃任务/读取快照，每分钟120新命令；单个快照最多10000条，超限明确拒绝，不静默截断。

本轮 `image` 必须为 null；点赞数固定0，likedByMe为false，排序调用既有核心。图片、点赞/本人删除/定位接口、原生 journal、页面、通知 provider 均待后续，本后端交付不构成完整 B07 通过或部署授权。
