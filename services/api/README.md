# Hnuhole C/V 开发服务

本分支新增的举报／审核／通知运行说明见下节；下文其余认证历史报告仍保持各自原版本的证明范围。

## 帖子举报、审核和最小系统通知

`codex/feat/report-moderation` 阶段1提供已有帖子举报、原提交核对、同事实合案、审核、处罚、必要申诉与 App 内通知。评论举报和真实评论失败 provider 等 `comments-replies` 合入后接入；不依赖评论表。本地真实 HTTPS／SQL／Dart／网页链路与权限证据见[阶段1报告](../../docs/design/report-moderation-validation-report.md)。

已有 C/V 开发环境继续使用原认证和 Gate 初始化／恢复流程。在 **C owner 连接**上按实际 main 的顺序执行迁移；本分支基于0014新增0015，不能跨号或覆盖已合入迁移。迁移后执行 `infra/postgres/grant-community.sql`，图片功能启用时执行 `grant-post-images.sql`，启用审核再执行 `grant-moderation.sql`。0015 的删除／注销清理钩子在关闭审核时仍必需，故必须重跑新版 `grant-community.sql`；启动会核查缺失权限。Down 明确拒绝，采用冻结和前向修复。

在已有 C 配置加入 `"moderation": true`，并保持已验证的 `posts` 配置。若提供网页，再设置 `"adminDirectory": "/absolute/path/to/repo/apps/admin"`；该值也可相对配置文件目录，最终解析为绝对路径。启动后同源 HTTPS `/admin` 只提供四个静态文件。管理端无需构建，不另设登录服务。补充图片需要已有 `postImages` 的固定 Python／验证器路径及 SHA256；未启用图片时纯文字举报仍可用，补图失败关闭，不信任 MIME 声明。

首次管理员由受控 owner 对已经注册的专用账号执行一次，六位平台号保留前导零：

```sh
psql -X -v ON_ERROR_STOP=1 -v platform_number=001527 "$C_MIGRATION_DSN" -f ../../infra/postgres/bootstrap-moderation-admin.sql
```

脚本只允许表 owner、ACTIVE 账号且系统尚无管理员；创建角色并留审计，不产生初始密码。后续使用网页按六位编号分配审核员或管理员，禁止移除最后管理员。管理员注销前应先移交权限；若已无管理员，由 owner 按同一脚本恢复并留审计，运行服务无此引导权限。管理登录沿用现有单设备规则，建议使用专用合成账号演练。页面不会展示邮箱、内部映射、其他面具或举报人身份。

移动端使用原 C HTTPS origin，从帖子菜单举报、从系统消息查看进度及结果；处罚归账号，举报可绑定原身份。普通会话因封禁失效时，可在本人处理通知入口独立复验现有用户名密码，得到24小时、不可访问社区或管理接口的 `MODERATION_SELF` 能力。该能力不接替普通登录、不取消注销，不改变现有 Passkey 或 iOS 边界。

Linux／WSL 使用本任务专属缓存、日志及私有数据库 socket，执行 `authlab/run-moderation-isolated.sh`。它拒绝 root 和外部 DSN，结束即清理所建库。设置 `PGPORT` 为本任务端口；`POST_MEDIA_PYTHON`／`POST_MEDIA_FIXTURES` 使用已准备的固定验证器；`MODERATION_GOOSE` 指向 Goose v3.22.1；用 `dart compile exe apps/mobile/integration/governance_live_probe.dart` 生成探针后设置 `MODERATION_PROBE`。再设置 `MODERATION_NODE`、`MODERATION_PLAYWRIGHT_MODULE`、`MODERATION_BROWSER_OUTPUT`（可选 `MODERATION_BROWSER`）即可同时执行真实网页审核。未提供探针只会明确 SKIP 该项，不能记录为整链 PASS。完整继承 SQL 回归可显式设 `MODERATION_TEST_PATTERN=.`；所有夹具仅使用合成账号。

本轮设备／凭据／原生Passkey接入见[实施报告](../../docs/design/auth-privacy-device-credentials-passkey-validation-report.md)。C可选 `webAuthn:{rpId,origins,androidOrigins}` 固定策略；省略／null保持Passkey禁用，CORS不选择RP或Android签名白名单。`authdev init` 可显式传 `-webauthn-rp-id`、`-webauthn-https-origins`、`-webauthn-android-origins`，不生成虚构部署值。平台关联步骤见[原生包](../../packages/auth_passkey/README.md)，loopback TLS材料不代证手机关联／信任。

`GET /api/v1/auth/credential-change-result` 使用当前Bearer、原 `Credential-Change-ID`／`Idempotency-Key` 核对轮换、绑定、移除，三态均200。缺记录不推断失败，已知意图的不可逆终止和所有成功结论均经最终Gate；过期结果410。返回权威 `Session-Expires-At`，不重放新码或证明，结构复用既有迁移。本轮SQL／HTTP／origin／配置测试缺Go未执行。

`cmd/api` 是社区 C：新注册、密码／恢复／会话、目录与后台注销／收据。`cmd/verifier` 是 V：校邮 OTP、资格、退役续办与收据处理。两方各有独立数据库、运行角色、公开 HTTPS 和内部 mTLS 监听。C 的全部认证与目录授权使用 Safety Gate；新库从 FROZEN 建立，API 启动不解冻。开发配置样例为 `community.config.example.json`、`verifier.config.example.json`；样例中仅有路径与无密码 DSN。

本轮只供开发。本机 Go／PostgreSQL／Docker／Flutter 已清理，新增进程、Go 测试、正式迁移及 PG16/Go1.22 兼容尚未执行。历史 Go1.27.1／PG18.6 回归仅对应历史代码。实际证据与未执行项见 [本轮报告](../../docs/design/auth-privacy-runtime-business-integration-validation-report.md)。

## 工具与边界

模块保留 Go1.22；固定开发数据库 `postgres:16.6-alpine`、Mailpit `v1.21.8`。迁移锁 Goose **v3.22.1**，sqlc **v1.27.0**，oapi-codegen **v2.4.1**。版本依据为各自官方 [Goose go.mod](https://github.com/pressly/goose/blob/v3.22.1/go.mod)、[sqlc go.mod](https://github.com/sqlc-dev/sqlc/blob/v1.27.0/go.mod)、[oapi-codegen go.mod](https://github.com/oapi-codegen/oapi-codegen/blob/v2.4.1/go.mod)；源码最低版本不是实际兼容证据。Goose v3.24.3 需要Go1.23，故没有用于Go1.22基线。生成方式见 [OpenAPI README](../../packages/openapi/README.md)。不在此电脑安装工具链、下载 Docker images 或恢复大型缓存。

macOS/Linux 使用现成 Go、Goose、Docker Compose v2、psql、Python3、curl。race 要求可用 C 编译器和 CGO；先记录 `go version`、`go env CGO_ENABLED CC`、`cc --version`、`docker compose version`、`psql --version`、`goose -version`。Windows 的 Go／Goose／文件锚点与 POSIX runner 在 **WSL2 Linux 文件系统**（例如 `~/src/Hnuhole`）执行；使用已启用 WSL 集成的 Docker Desktop 或 WSL 内 Docker。不要在 `/mnt/c` 中代验文件锁／持久落盘；本片未实现原生 Windows Go 锁。Windows 宿主机 Flutter／Android 可单独构建，Go fixture 直接 exec Flutter 时需同一 WSL 内 Linux Flutter。

## 首次初始化（macOS/Linux 与 WSL2）

以下从 `services/api` 执行，依赖已经在验证电脑具备。目录可保留作重启验证；`authdev init` 必须使用一个尚不存在的 material 子目录。shell 不开启 `set -x`，私钥／密码／OTP 不写日志。

```sh
DEV_AUTH_PARENT=$(mktemp -d "${TMPDIR:-/tmp}/hnuhole-dev.XXXXXX")
chmod 700 "$DEV_AUTH_PARENT"
DEV_AUTH_PROJECT="hnuhole-dev-$(basename "$DEV_AUTH_PARENT" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
GOTOOLCHAIN=local GOPROXY=off go build -o "$DEV_AUTH_PARENT/authdev" ./cmd/authdev
GOTOOLCHAIN=local GOPROXY=off go build -o "$DEV_AUTH_PARENT/community" ./cmd/api
GOTOOLCHAIN=local GOPROXY=off go build -o "$DEV_AUTH_PARENT/verifier" ./cmd/verifier
"$DEV_AUTH_PARENT/authdev" init -dir "$DEV_AUTH_PARENT/material"
DEV_AUTH_DIR="$DEV_AUTH_PARENT/material"
export C_ADMIN_PASSWORD="$(cat "$DEV_AUTH_DIR/operator/db-c-admin.password")"
export C_MIGRATOR_PASSWORD="$(cat "$DEV_AUTH_DIR/operator/db-c-migrator.password")"
export C_RUNTIME_PASSWORD="$(cat "$DEV_AUTH_DIR/db-c-runtime.password")"
export C_RECOVERY_PASSWORD="$(cat "$DEV_AUTH_DIR/operator/db-c-recovery.password")"
export V_ADMIN_PASSWORD="$(cat "$DEV_AUTH_DIR/operator/db-v-admin.password")"
export V_MIGRATOR_PASSWORD="$(cat "$DEV_AUTH_DIR/operator/db-v-migrator.password")"
export V_RUNTIME_PASSWORD="$(cat "$DEV_AUTH_DIR/db-v-runtime.password")"
docker compose -p "$DEV_AUTH_PROJECT" -f ../../infra/docker-compose.yml up -d --pull never --wait
```

该 Compose project 名随本次私有目录唯一分配，只用于此次全新开发环境。保存自己的 `DEV_AUTH_PROJECT` 与 `DEV_AUTH_PARENT`，重启时复用；不要重新生成名字接到未知项目。现有卷中的初始化角色不会被新环境变量重建。普通配置、Git 与服务日志都不保存密码或私钥字节。API 只加载证据／恢复／break-glass 公钥和自身锚点签钥；`operator/` 的恢复与证据签钥由独立开发命令加载。ECDSA P-256 TLS 兼容已沿用 Dart 路径，协议签名仍为 Ed25519。开发根与测试 SAN 固定为 localhost／literal loopback，不关闭证书验证。

## 正式迁移与最小权限

C 的唯一 SQL 源为 `migrations/`（保留原已发布0001／0002，新增0003–0011）；V 的唯一源为 `verifier-migrations/`。Goose 单文件事务；新增认证迁移的 Down 主动拒绝，以免倒退永久槽位、消费事实、撤销或代次。故障采取冻结与前向修复。运行服务不做 DDL。

Compose 首次初始化创建各侧 NOLOGIN owner、只持本侧 owner membership 的 LOGIN migrator、无 owner membership 的 LOGIN runtime。C 另有单个 `hnuhole_c_recovery` 和只读目录 `hnuhole_business`；恢复连接只获 Gate row、audit INSERT 与 identity sequence 权限。普通 runtime 对永久事实无 DELETE、无 Gate INSERT／audit UPDATE／DELETE；C 对 `public.channels` SELECT；B02本人身份与累计状态表仅SELECT/INSERT/UPDATE，结果锚点仅SELECT/INSERT、禁止UPDATE/DELETE，旧 `public.sessions` 撤销并撤权但保留表。V 没有 C 用户／schema／权限。数据库 PUBLIC CONNECT／TEMP、schema CREATE、认证表与函数的 PUBLIC 权限撤销。初始化使用 admin；服务拒绝 owner／超级用户／DDL／旧认证读权、错误库／缺结构或迁移版本。

```sh
C_MIGRATION_DSN='postgres://hnuhole_c_migrator@127.0.0.1:55432/hnuhole_c?sslmode=disable&options=-c%20role%3Dhnuhole_c_owner'
V_MIGRATION_DSN='postgres://hnuhole_v_migrator@127.0.0.1:55433/hnuhole_v?sslmode=disable&options=-c%20role%3Dhnuhole_v_owner'
PGPASSWORD="$C_MIGRATOR_PASSWORD" goose -dir migrations postgres "$C_MIGRATION_DSN" up
PGPASSWORD="$V_MIGRATOR_PASSWORD" goose -dir verifier-migrations postgres "$V_MIGRATION_DSN" up
PGPASSWORD="$C_MIGRATOR_PASSWORD" psql -X -v ON_ERROR_STOP=1 "$C_MIGRATION_DSN" -f ../../infra/postgres/grant-community.sql
PGPASSWORD="$V_MIGRATOR_PASSWORD" psql -X -v ON_ERROR_STOP=1 "$V_MIGRATION_DSN" -f ../../infra/postgres/grant-verifier.sql
```

每次追加迁移后按 owner 连接重跑权限脚本；不以默认全 schema 权限自动放行未来表。`authlab` 的历史 schema-reset fixture 仅在带 marker、匹配库／角色、私有 Unix socket 的一次性库中使用正式 SQL 的 Up；它仍是 fault-injection owner，最小权限由新实际进程 runner 验证。旧通道升级只在 runner 明确创建的 `hnuhole_upgrade` 临时库，比较七条记录所有字段／UUID；不连接未知旧库，不复制资格或账号。

## 启动、证据与停机

```sh
"$DEV_AUTH_PARENT/community" -config "$DEV_AUTH_DIR/c.json" &
C_DEV_PID=$!
"$DEV_AUTH_PARENT/verifier" -config "$DEV_AUTH_DIR/v.json" &
V_DEV_PID=$!
# 单独、显式受限签名恢复。generation 推进使旧会话失效。
"$DEV_AUTH_PARENT/authdev" recover -operator "$DEV_AUTH_DIR/operator/operator.json"
# 开发证据源每分钟签发一次，TTL始终最多五分钟；服务没有该签名权。
"$DEV_AUTH_PARENT/authdev" watch -operator "$DEV_AUTH_DIR/operator/operator.json" &
EVIDENCE_DEV_PID=$!
curl --cacert "$DEV_AUTH_DIR/dev-ca.pem" https://127.0.0.1:8443/health/ready
```

公开 C8443／V8444；内部 C9443／V9444。`/health/live` 区分存活，`/health/ready` 查数据库，C 还复核 Gate；FROZEN 时可诊断但ready503、受保护操作503。证据源停机／过期、锚点不匹配或时钟回退均fail closed，不用数据库时间代替。手动 `authdev issue` 续发同一代次证据（仅开发故障演练可 `-valid-for 1s`，最大仍五分钟）；`freeze` 冻结；恢复总要显式 `recover` 新代次。watch 是同机开发信任，不能作为独立授时、生产运营或灾备证据。

配置严格拒绝未知字段、遗漏／错用途钥、错证书／peer、错误固定 HTTPS origin、私钥权限、无界参数与错误 runtime 库。请求默认30s、SQL statement10s（与现有事务固定配置一致；事务lock5s）、worker每2s、批16、并发1、任务15s，签名／网络在SQL锁之外。网络默认每分钟mutation120、query240、最多4096桶；密码同时最多2个Argon2id。开发阻止名单很小，生产覆盖与多副本限流另验。

SIGINT/SIGTERM 先停止监听，取消 worker，再等有界请求／最终提交、Shutdown和pool关闭。重启复用同一DB卷与私有material；不要重跑init、删除锚点或认为启动会解冻。停机示例：

```sh
kill "$C_DEV_PID" "$V_DEV_PID" "$EVIDENCE_DEV_PID"
wait "$C_DEV_PID" "$V_DEV_PID" "$EVIDENCE_DEV_PID"
docker compose -p "$DEV_AUTH_PROJECT" -f ../../infra/docker-compose.yml stop
```

Mailpit SMTP为literal `127.0.0.1:1025`，仅此地址允许无STARTTLS；邮箱UI `http://127.0.0.1:8025`。OTP生成、加密排队与真实SMTP使用已有状态机；未知DATA结果不会自动重投。仅开发操作员在Mailpit UI读取合成测试邮件；C／公共API无取码接口，`cmd/runtimeprobe` 内只读Mailpit latest/raw并验证唯一合成收件人，且要求隔离marker和私有目录，永不打印码。

AC01 已为 V 装配独立 `v_auth` Gate：`eligibility_otp.go` 的发码／等待／预算／锁／验证／投递claim与清理、`eligibility_confirmation.go` 的资格时窗／签名落库／原确认／退役续办与清理，以及 `verifier.go` 的配额／收据裁决均使用可信时间与最终事务授权。V 证据、库外锚点、代次、受限恢复角色和连接池独立于 C；恢复使旧 pending 作业失效。实施与证明边界见 [AC01方案](../../docs/design/auth-verifier-safety-gate-plan.md)和[验证报告](../../docs/design/auth-verifier-safety-gate-validation-report.md)。开发文件锚点不代证生产独立授时／库外存储／灾备运营。

WSL2的服务与文件保持WSL所属；Docker published ports必须能从WSL literal loopback连接，先用psql和curl核对当前Docker集成。Android模拟器的10.0.2.2或真实设备LAN访问需要单独显式的HTTPS开发入口、匹配SAN／origin与平台信任步骤；当前生成的loopback证书不代表设备已验收。不要为此开放整个PG／SMTP／Mailpit／内部mTLS。

## 验证与清理

```sh
GOTOOLCHAIN=local GOPROXY=off go test ./cmd/authdev
sh authlab/run-runtime-isolated.sh
sh authlab/run-isolated.sh
GOTOOLCHAIN=local GOPROXY=off go test -race -count=1 -p 1 ./...
GOTOOLCHAIN=local GOPROXY=off go vet ./...
```

新runtime runner分配独立项目、随机loopback端口与0700目录：实际cmd＋正式迁移／受限runtime＋Mailpit OTP注册＋七目录／阈值续期／重启／换机／定向退出／恢复／Gate冻结恢复／到期注销与持久ACK。命令不下载依赖。Shell检查和代码审阅不能代替执行；缺工具、Go1.22／PG16、race、Flutter、设备／Xcode证据单列。日志只留小型脱敏摘要；临时key／DB／进程归该次runner并由trap清除。

手工环境数据用于重启；只有确认是自己保存的 `DEV_AUTH_PROJECT` 后才可 `docker compose -p "$DEV_AUTH_PROJECT" -f ../../infra/docker-compose.yml down -v` 并删除自己创建的私有目录。不得对未知项目down-v、全局prune、删除现成SDK／AVD／用户数据。


## B02身份管理基础

本人身份 API 接入相同 C runtime 和最终 Safety Gate：`GET/POST /api/v1/identities`、`PATCH/DELETE /api/v1/identities/{id}`，原结果 `GET /api/v1/identity-change-result`。变更及核对使用独立16字节规范base64url `Idempotency-Key`（与32字节认证操作键不同）；全部成功响应携带同Bearer权威 `Session-Expires-At`。仅本人列表；默认头像 `default-v1`，自定义上传后续媒体实现。

正式迁移11保留累计创建、稳定删除墓碑以及账号归属成功／拒绝终态回执；迁移12接入身份整账号正式关闭。runtime最小版本12并检查表／非owner／必要DML及关闭shape触发器。每个新意图用新键；超时、丢响应、`NOT_FOUND`只重试原键和原参数；`COMMITTED`与`REJECTED`为永久终态，拒绝不消耗创建或改名机会。详见[契约](../../packages/openapi/identity-api.yaml)、[身份报告](../../docs/design/identity-management-validation-report.md)和[AC02本轮报告](../../docs/design/auth-identity-account-closure-validation-report.md)。当前服务端SQL／race／vet与实际C/V R03通过；客户端／设备历史结果保留原版本，帖内绑定和帖子／聊天投影调用仍未实现。

七天缓冲和取消保留身份资料；最终C Gate关闭事务同时擦除全部活动身份的昵称、头像及改名时间，用最终可信时间建立墓碑，不等待V释放ACK。原累计创建状态、已有删除墓碑和成功／拒绝回执保持不变；零身份关闭不自动创建身份，CLOSED不得恢复活动身份。身份生命周期DML只支持现有显式READ COMMITTED事务，其他隔离级别由延迟约束拒绝。旧CLOSED遗留资料升级修复只使用已持久Gate高水位的维护marker，证据不足则迁移失败，不冒称原关闭时间。纯注销投影仅含身份级opaque token、统一头像键和状态；没有新增任意身份查询接口，编号界面格式与真实内容／聊天调用留对应业务片。
