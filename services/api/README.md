# Hnuhole API

认证隐私的实验实现与真实数据库测试位于 [authlab](authlab/README.md)。实验 SQL 不进入下方生产迁移目录，Go 包未接入现有 HTTP 路由。

首条开发切片的 Go API。当前实现先提供认证保护的通道目录接口：

- `GET /api/v1/channels`
- `200`：完整七项通道目录
- `401`：缺少、过期或撤销的服务端会话
- `503`：目录读取或完整性校验失败

## 本地运行

先启动仓库根目录 `infra/docker-compose.yml` 中的 PostgreSQL，再使用 goose 执行 `migrations/`。设置 `DATABASE_URL` 后运行：

```powershell
$env:DATABASE_URL = 'postgres://hnuhole:hnuhole_dev_only@localhost:5432/hnuhole?sslmode=disable'
go run ./cmd/api
```

OpenAPI 源文件在 `packages/openapi/channel-api.yaml`。数据库迁移只写表结构和七个通道种子；测试账号由后续开发夹具创建，不进入生产迁移。
