# 主线默认启用评论快照 Redis

2026-10-27，COMMENT-SNAPSHOT-REDIS-01 的追加要求。分支 `codex/fix/comment-snapshot-redis-default`，基线 main `b1c00bb11115958f60d04a5e70ec46e0bb6701d9`。用户已授权本次提交、PR 和合并；本记录初次提交时为待合并，最终 PR、head、CI 和合并 SHA 见 PR Checks 与 D 盘交付回执。

## 行为与配置

- `commentsnapshot.DefaultConfig()` 改为 `createBackend=redis/readRedis=true/readPostgres=true`，TTL1800秒与原配额、预算和清理界限不变。
- `infra/commentsnapshot/snapshots.example.json` 同步上述默认，命名空间对齐标准环境 `dev`；标准 `services/api/community.config.example.json` 包含 posts、comments 及完整 Redis 快照配置。密码文件和 epoch 仍须环境所有者提供，模板不自动初始化 Redis。
- `cmd/api` 的 LoadConfig 与 Run 都经过配置验证。启用 comments 却省略 snapshots、缺地址/epoch/密码、命名空间不匹配或复用 C 限流实例时启动失败；日志输出固定 `reason=comment_snapshot_configuration`，不输出私有错误内容。Run 验证后才装配 Store，移除 nil 时走旧 PG 的入口。comments 整体关闭的认证专用配置仍保持关闭。
- Redis 不可用/未初始化时保留既有 Check 拒绝启动和请求错误语义，不自动退 PG。显式运维回退仍支持 `createBackend=postgres`，旧 Redis 游标未到期时必须保留 `readRedis=true` 和原实例；只有确定无 Redis 旧游标时才可显式关闭 Redis 读取。
- 旧 Android 一次性夹具明确设置 PG/readRedis=false，避免依赖原缺省行为。本轮未启动该夹具。

## 针对性检查

WSL `HnuHole-Ubuntu-24.04`、现有 Go1.22.2 和缓存，在本分支源码执行：

```sh
go test -mod=readonly -count=1 -v ./internal/authprivacyruntime -run 'TestCommentSnapshot|TestCommentTextExplicitRuntimeConfiguration|TestProcessDiagnosticsExcludeUntrustedErrors'
go build -mod=readonly ./...
go vet -mod=readonly ./...
```

5个顶层配置/安全日志测试 PASS，含4个 default/example/standard/omitted 子项；build、vet PASS。Python fixture AST、JSON模板解析及 diff whitespace PASS。测试覆盖默认 Redis 和 PG 兼容读、缺配置在 Run 打开数据库/监听前失败、安全原因码、专用实例/命名空间限制及显式 PG 回退。适用产品 CI 自动运行，不手动触发 actual-process-acceptance。

使用候选 Go LoadConfig 只读校验真实开发 C/V 文件 PASS，无数据库连接或监听；临时检查源码已移除。既有四个归属明确进程和 C/V HTTPS ready PASS，当前实际配置为 Redis 新建/双读，专用 Redis 与 C/V 限流两实例地址不同，128MiB/noeviction/AOF写状态ok，Redis配置与ACL摘要不变。未重建或重启服务，运行二进制仍来自已测 a2e98eb；本次只核对接线一致，不声称已部署新默认值二进制。

本地检查及脱敏证据位于 `D:/HnuHole-task-storage/comment-snapshot-redis-20261024/main-redis-default-sol-20261027/`。最初 WSL 正则命令被 shell 拒绝，改用 --exec 后执行成功；首次只读检查脚本换行转义语法错误在执行前失败，修正后检查通过，没有改运行配置。

## 范围

本次只改默认、runtime装配检查、标准模板、相关夹具和交接。没有新建环境、设备操作、性能采样、30分钟验收或生产发布。PR80的单指定场景性能PASS、旧+7.5716285574% FAIL及既有设备/iOS/全阶段未验项按原版本保留，不改判。生产发布仍需独立授权。
