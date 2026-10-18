# 评论文字组件 SQL（尚非部署迁移）

`text-v1.sql` 是本轮可独立审查的规范 SQL 本体，`runtime-grants.sql` 是对应的 C runtime 最小授权。本体沿用 `c_posts` 的永久帖内身份绑定、公开身份标签、账号 stop generation；Go 的 Accept/Retry/Abandon/Publish/Fail 仍是业务规则来源。

2026-10-18 核对的 main 为 `986477b`，正式迁移仅到 0014。治理基础 0015 未进入 main，评论编号暂定 0016；本目录没有 Goose 编号、版本记录或部署入口。禁止用缺号、伪造 0015 或 `allow-missing` 应用本目录来部署。正式迁移链、安装/升级/回退和最终授权审计均为 **BLOCKED**。治理基础真实合入后，正常整合 main，检查其迁移内容和实时编号，再将本体纳入连续编号迁移并补正式证据。

组件实验使用真实 main 0001–0014 的 raw fixture，随后在一次性私有数据库显式应用本体；没有写入 Goose 0015/0016。这证明本体和真实 HTTP/授权的行为，不证明有序迁移链。

运行已有 PostgreSQL 16、Go 1.22.2 的非 root Linux 环境：

```sh
export PATH="$(pg_config --bindir):$PATH"
bash services/api/authlab/run-comment-text-isolated.sh
```

runner 固定创建自己的 C/V 开发库、非超级用户 owner 和 `hnuhole_c_runtime`，拒绝通过外部 DSN 接入未知数据库。PG 使用无 TCP 的私有 Unix socket，默认端口 55463，退出时仅清理本次 mktemp 目录。socket 单独放短路径以符合 Unix 路径长度限制；Go/Gate 临时文件应位于 Linux 文件系统。TLS HTTP 测试使用自签实验 CA 的真实客户端/服务端连接，保留现有最终 Gate 和会话检查。

开发 runtime 显式配置 `posts` 后，可增加：

```json
{"comments":{"commandKeyFile":"comment-command.key","fingerprintKeyFile":"comment-fingerprint.key"}}
```

两份独立 32 字节用途密钥受现有密钥文件权限和全用途查重规则约束。缺省关闭；缺表、hook、最小授权或历史密钥不匹配会拒绝启动/冻结。worker 复用已有有界调度器。本轮不提供可部署的 schema 安装捷径。

已受理文字只存服务任务；没有评论长期草稿。放弃、删身份和正式关闭账号擦除未发布文字；已发布文字保留公开事实及安全作者投影。5 分钟读取快照只存顺序 ID，不存正文，过期后在下一次建立快照时清理。每账号最多 128 活跃任务/读取快照、每分钟 120 新命令；单个读取快照最多 10000 条，超限明确拒绝，不静默截断。图片、点赞/删除/定位接口、原生 journal、页面和通知均未接入本组件。
