# 评论业务的数据库与运行方式（0017）

规范 SQL 为 `../migrations/0016_comments.sql` 及 `../migrations/0017_comment_business.sql`，运行时授权为 `../../../infra/postgres/grant-comments.sql`。0016 紧随已经合入 main `1b78f42`（PR #18）的真实 `0015_reports_moderation.sql`。本分支已正常整合该 main，不允许缺号、乱序或伪造迁移。

SQL 沿用 `c_posts` 的永久帖内身份绑定、公开身份标签和账号 stop generation。首次参与者绑定与评论任务/回执在同一事务提交；Go 的 Accept/Retry/Abandon/Publish/Fail 仍是业务规则来源。已有绑定不可变，重试不接受替换身份或目标。DDL 约束归属、同帖同楼回复、任务版本、唯一发表和永久回执；Down 明确拒绝静默丢失事实，修复使用前向迁移。

运行 PostgreSQL 16、Go 1.22.2、Goose v3.22.1 的非 root Linux 环境：

```sh
export PATH="$(pg_config --bindir):$PATH"
bash services/api/authlab/run-comment-text-isolated.sh
```

runner 创建本次独立 C/V 业务库、空库安装库、升级库和非超级用户角色，拒绝外部 DSN。PG 无 TCP，仅使用私有 Unix socket，默认端口 55463；退出只清理本次 mktemp 目录。socket 使用短路径以符合 Unix 路径长度限制；Go/Gate 临时文件使用 Linux 文件系统。真实 Goose 验证空库 0001–0017、0014→真实0015→0016→0017，以及拒绝 Down 后版本仍17。SQL/HTTP fixture 另验证所有实际迁移与真实 C Gate/会话/受限角色，不以 raw fixture 代替 Goose 证据。

开发 runtime 的 schema 安装与授权顺序为 Goose up → grant-community.sql → grant-comments.sql。前者包含评论功能关闭时仍需要的身份/账号生命周期最小清理授权；后者才授予评论命令/快照写入。独立 recovery、business、V 角色没有评论正文或任务读取权。

显式启用 `posts` 后，配置：

```json
{"comments":{"commandKeyFile":"comment-command.key","fingerprintKeyFile":"comment-fingerprint.key"}}
```

两份独立 32 字节用途密钥受现有权限和全用途查重约束。缺省关闭；缺表、hook、最小授权或历史密钥不匹配会拒绝启动/冻结。worker 使用已有有界调度器，重新运行不会重复发表。真实接口与 JSON 形状见 `packages/openapi/comment-business-component.yaml`（完整业务接通补充）；`comment-text-component.yaml` 仅保留此前文字阶段的历史范围。单图同时需要现有 postImages 校验器配置，使用受信任、不可由运行角色修改的 Pillow helper；不跳过原格式/容器/动画预算。

已受理文字只存服务任务，没有评论长期草稿。放弃、删身份和正式关闭账号擦除未发布文字；已发布文字保留公开事实及安全作者投影。审核下架/删除帖子不能读评论或继续发送。5 分钟读取快照只存顺序 ID，不存正文，过期后在下一次建立快照时清理。每账号最多128活跃任务/读取快照，每分钟120新命令；单个快照最多10000条，超限明确拒绝，不静默截断。

0017 已接通 null/一张原图、账号幂等点赞、本人删除（主评论整楼/回复本条）、定位与真实失败通知。图片先校验会话、归属/尝试与清单 hash，再进入解码器，最终事务重新核对；上传完整验证后才能公开。删除/放弃/失败及相关生命周期擦除对应原图，读取仍要求当前 C 会话/Gate 和至多60秒租约。分页游标以独立用途 MAC 保护，数据库继续绑定账号/帖子/楼及有效期。

Flutter 已装配评论页面、独立原生加密已提交任务 journal、未知核对与显式重试/放弃。失败事件复用治理0015通知，原文/原图仅从本人任务接口读取，按原发送身份展示。未提交编辑仍只存当前帖子内存，不提供长期评论草稿。当前验收版本、设备和未验边界见 `docs/design/comments-connected-report-20261019.md`；开发验收不代表合并或发布授权。
