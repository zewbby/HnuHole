# 文字社区 T2 服务端交付与验证

日期：2026-10-08（Asia/Shanghai）。工作树 `C:/Users/Administrator/.codex/worktrees/community-text-posting/HnuHole`，分支 `codex/community-text-posting`，测试快照的Git基线为 `1b7fe2e7214c460ab023cffb9c6d7f875607ff2a`，认证源码基线 `0eff47a21cd4f4ab1636b4468f7d5df9769a264f`。用户授权后，T2源码、测试及验收交接已推送为[提交0644f5a](https://github.com/zewbby/HnuHole/commit/0644f5ae5ef0c92ae99ed81fd40dac97ed447bc3)，新增说明性注释和提交说明使用中文。旧测试基线及源码指纹保持原证明范围；本轮未部署。

T2已实现文字闭环的服务端：当前Bearer访问，受理时固定帖内身份，后台最终公开，原命令核对与封印，任务取消／失败重试／隐藏，通道最新列表、正文详情、本人列表与作者删除。客户端页面、本机草稿和业务存储由独立Flutter任务负责；本报告不能作为完整手机闭环或上线批准。机器结果与当前源码指纹见[总记录](community-text-posting-t2-verification.json)，schema／受限角色专项见[记录](../../services/api/authlab/community-text-post-schema-verification.json)，最终HTTP整包见[记录](../../services/api/authlab/community-text-post-http-verification.json)，实际C/V进程见[记录](../../services/api/authlab/community-text-posting-t2-runtime-verification.json)。

## 1. 真实实现位置

| 范围 | 源码与测试 |
|---|---|
| 内容／摘要／严格DTO／游标 | `services/api/internal/posts/`；同目录测试、共享9组摘要及7组字素向量、Unicode16官方1093案例 |
| 同一最终C Gate事务的受理与永久回执 | `services/api/internal/authprivacy/community_posts.go`、`community_posts_test.go` |
| 停止代次、身份删除、关闭／处罚联动与worker | `community_posts_lifecycle.go`、`community_closure.go`、`community_identities.go`、`workers.go`；`community_posts_test.go`及原认证回归 |
| 最新feed／本人列表／详情及当前身份投影 | `community_posts_read.go`；`community_posts_test.go` |
| 正式SQL／完整性约束／最小权限 | `services/api/migrations/0013_community_text_posts.sql`、`infra/postgres/grant-community.sql`、`community_posts_schema.go`／测试、`authlab/run-post-schema-isolated.sh` |
| 14操作HTTP／公开字段边界 | `services/api/internal/authprivacyhttp/posts_endpoints.go`／测试、`posts_postgres_test.go`、`endpoints.go` |
| 可选C配置／实际入口／后台装配 | `services/api/internal/authprivacyruntime/config.go`、`server.go`、`posts_config_test.go`、`cmd/authdev/main.go` |
| 实际C/V进程和升级／重启验证 | `services/api/cmd/runtimeprobe/posts.go`、`main.go`／`identity_closure.go`、`authlab/run-runtime-isolated.sh`、`privacy-role-audit.sql` |

SQL共12张 `c_posts` 表。永久回执、帖内身份绑定、独立身份短编号及协议密钥承诺受不可变约束；正文只有完整不可逆擦除能力。运行角色没有DELETE、TRUNCATE、DDL或修改不可变输入的权限。新建身份和历史身份都会取得独立12位base32短编号；公共DTO不返回账号ID、身份ID、任务ID、原文摘要或本人权能。

## 2. 已验证的行为与范围

| 检查 | 当前结果 | 精确证明范围 |
|---|---|---|
| 完整Go／真实SQL／race与vet | PASS（保留原被测快照） | `authlab/run-isolated.sh`退出0：`go test -race -count=1 -p 1 ./...`和`go vet ./...`；authprivacy包408.149秒、HTTP包49.728秒。此全量快照先于最后HTTP 404修复；未变的auth／SQL／worker逐文件一致，HTTP整包及R03按最终版本复验，当前全服务端另执行`go vet -mod=readonly ./...`通过。专项受限DSN和mobile runner未提供的两项SKIP在下文明确列出 |
| 帖子SQL功能回归 | PASS | 15个主测试；受理唯一绑定、原结果稳定、跨号拒绝、12并发重放、8次create/seal竞争、12次cancel/publication竞争、接替后worker继续、mute／ban到期不复活、注销撤销不复活、显式retry、hide、删除／正式关闭投影、游标ceiling与跨scope／账号拒绝、密钥恢复及120／128预算 |
| 正式schema／受限runtime | PASS | 9个主测试＋4个生命周期子场景，PG16，race，23.296秒；精确必需DML、过量不可变UPDATE、缺hook、旧writer、标签回填、12表隐私边界及密钥承诺不可变 |
| HTTP单元＋真实HTTPS handler→SQL | PASS（最终版本） | HTTP整包真实SQL／race为39.349秒，69个主测试／371个含子测试的通过事件；posts包含12个单元主测试＋2个真实HTTPS／PG主场景，覆盖全部14操作及不存在通道GET 404／CREATE 409。数据库fixture为非superuser owner，角色证据另外提供 |
| 实际C/V cmd、后台worker、重启、受限角色 | PASS（最终版本） | 完整R03共15阶段／151次HTTPS；文字phase42次，posts-restart5次，冻结4次／恢复13次中含帖子校验，关闭33次中含旧帖占位与新账号隔离；实际文字操作12/14，RETRY/HIDE由上述SQL／HTTPS handler场景证明。旧142次记录保留其源码版本；本次请求数差异包含新增404断言及后台完成轮询 |
| OpenAPI完整规范＋专项静态契约 | PASS | 五份OpenAPI、14操作严格DTO／封印／重试及9组摘要向量；不代证动态链路 |
| Go内容计数 | PASS | Unicode16官方1093字素案例及共享向量；保留原文本，emoji／组合字符及CRLF按固定规则计数；不代证Dart端一致性 |

原认证回归由本轮完整Go／SQL及R03列明场景重新执行，历史AC01–AC06原记录不改成新版本PASS。R03包含C/V冻结、恢复、旧快照、证据过期、原OTP围栏及会话／身份／关闭回归，但不包括手机App、原生Passkey和生产授时。错误状态与成功截止头使用最终权威结果；旧拒绝回执查询返回原事实，原mutation仍返回固定拒绝且不续期。

两次调试问题已修正并纳入复验：回执初返与读取的内部TaskState一致；feed与task游标分别只填自己的定位字段。测试夹具曾尝试删除最后身份、使用恢复前旧会话及把CREATE误期待为200；改为遵循既有身份／授权代次／202契约，未放宽业务规则。schema检查补了SQL NULL三值逻辑下的终态必需字段及旧身份writer完整性防护。

最终审查补修了一处HTTP状态投影：合法格式但不存在的通道，GET应返回404 `POST_CHANNEL_UNAVAILABLE`，CREATE的同码持久拒绝仍为409；原投影误将读取404转成503。新增单元、真实HTTPS→SQL和实际C进程断言均通过，公共错误字段及失败不续期也有执行证据。总记录保留全量测试前后四份文件的摘要差异及各复验来源，不用旧全量SHA代证最终HTTP修复。

防重密钥补充：启动核对已有永久承诺；全新空库允许FROZEN启动。首次合法帖子访问在最终Gate事务内固定两份HMAC用途密钥承诺。之后前台、公开worker及正文清理均在最终事务核对；换错密钥或历史承诺丢失会冻结并拒绝，不能另起命令域重发。正确密钥能启动冻结进程，恢复后必须以当前授权代次重登录；worker不依赖旧Bearer。

## 3. 复验入口和环境

仅使用明确归属的一次性fixture，不接入真实用户库。WSL2 Linux文件系统中复制本片仓库，再使用现成Go1.22、PG16、Goose3.22.1；Go缓存和运行材料需独立。R03使用已有Docker镜像 `postgres:16.6-alpine`／`axllent/mailpit:v1.21.8`，没有下载工具或使用认证验收会话的环境。

```sh
# 终端：WSL。先设置本片独立GOCACHE/GOMODCACHE和工具PATH，进入Linux副本services/api。
GOWORK=off sh authlab/run-isolated.sh
GOWORK=off sh authlab/run-post-schema-isolated.sh
# 现成Goose由GOBIN/PATH提供；此脚本管理其独立Docker项目、证书与临时库。
GOWORK=off sh authlab/run-runtime-isolated.sh
```

本轮各入口退出0。普通无DSN `go test` 会跳过真实SQL；全量runner的 `TestPostSchemaRestrictedRuntimePrivilegesPostgres` 因未提供专项受限DSN为SKIP，由独立schema runner实际PASS补证；`TestMobileClientHTTPSPostgres` 因未启动mobile runner为SKIP，本片真实Dart链仍NOT_RUN。没有 `--module posts` 参数。完整规范使用现成PyYAML6.0.1、openapi-spec-validator0.9.0：`python -B packages/openapi/check-specs.py`及`python -B tools/check-community-text-contract.py`。

## 4. 尚未验收／后续工作

| 项目 | 状态与原因 | 下一步 |
|---|---|---|
| T3 Flutter页面、Drift/SQLite、多草稿、提交上下文持久、原生业务密钥／noBackup | NOT_RUN；属于独立Flutter任务，本工作树未实现 | 对齐post-api0.1.0与共享向量，再交付该任务的真实状态和证据 |
| T4认证最终候选＋Dart→实际C/V→SQL＋完整App／跨进程故障 | NOT_RUN；本片基于0eff47a，当前认证验收增量未合入，不能占用另一任务设备／环境 | 取得固定候选后独立整合、重跑共享边界，补丢响应／杀进程／存储失败／注销清理链 |
| Android真机／原生业务存储、系统备份排除、iOS | NOT_RUN；本轮仅服务端，没有本片设备证据 | 独立设备窗口与平台环境；旧认证APK／vault结果不代证posts |
| 历史容量、清理七天上限、监控告警、生产备份／WAL／灾备、分权及独立审计 | NOT_RUN；实验fixture无这些运营证据 | P03/P04及生产清单验收；不得用128当前任务上限代证历史账号全量生命周期事务容量 |
| 完整B03搜索、B05图片／标签、B06赞藏／分享、B10其他内容模块及治理界面 | 待开发，未包含本片 | 按后续明确任务实施；内部mute入口不等于治理系统 |

CP01／CP02／CP05–CP13／CP15取得的是本报告列明服务端证据；涉及页面、草稿、存储、导航锚点及设备的部分仍NOT_RUN。CP03、CP04、CP14客户端场景未执行。全体CP、完整B02/B03/B05/B06/B10及生产均不能据此标为PASS。

申请注销／处罚的停止代次永久生效；历史数据仍会累计。已避免对owner_visible=false历史任务重复UPDATE，但身份删除、正式关闭的历史回执收缩和清理安排仍需真实历史容量验证。未改为“只差测试”的未开发模块。未来密钥轮换需要有版本安全迁移；本轮只实现固定v1承诺及错误材料拒绝。

## 5. 交接与清理

[模块交接](module-acceptance-handoff.md)、[台账](module-acceptance-ledger.json)的 `currentCommunityTextT2`、[HANDOFF](HANDOFF.md)、[progress](progress.md)登记本轮实现与受影响A/B/X范围，保留旧认证和T1版本的证明边界。只保留源码、测试源码及小型脱敏JSON；一次性数据库／C/V进程／私钥由runner清理，其他本轮专用副本／Go缓存／原始大日志在最终源码检查后已清理并核对路径不存在。用户数据、现成SDK／AVD、认证验收材料及原工作树未动。

Windows临时辅助脚本清理为PASS：用户手动删除7个本轮helper后，本会话逐项核对`C:/Users/Administrator/AppData/Local/Temp`中的原路径均不存在。先前自动审批拒绝删除的BLOCKED记录作为历史保留，文件名及复核结果见总记录`cleanup.windowsTemporaryHelperCleanup`；这项不含数据库、私钥、APK、大日志或构建缓存。
