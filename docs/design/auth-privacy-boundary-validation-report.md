# AC03 隐私边界验证报告

记录日期：2026-10-05（Asia/Shanghai），任务开始于 2026-10-04。分支 `codex/auth-privacy-handoff`，基线 `faf557db4d74ecb2c202fd1349f1bf8fa64e6133`；被测版本为包含 AC01／AC02 的未提交工作区，最终源码摘要和命令退出码以 [机器记录](../../services/api/authlab/privacy-boundary-verification.json) 为准。

AC03 对当前匿名基础完成有范围的数据、权限、HTTP、客户端状态和诊断核对；修复三个诊断差异并固定 [后续业务契约](auth-privacy-business-contract.md)。本轮未发现 C 保存验证邮箱／其摘要、V 接收社区账号资料或本人身份接口跨账号返回资料的现有实现。这个结论由下面列出的源文件与负向测试限定，不能外推为全产品或生产独立安全审计。任务范围见 [三步任务单](auth-privacy-boundary-plan.md)。

## 当前边界核对

| 边界 | 当前源码事实与证据入口 | 结论／限制 |
| --- | --- | --- |
| C 数据 | `services/api/migrations/0003_authprivacy.sql` 及正式迁移至 0012；账号、凭据、槽位、会话、请求墓碑；public 身份、计数、永久回执 | 当前表／字段清单和合成已注册行检查无验证邮箱、OTP、邮件材料或邮箱 SHA256。C 私有用户名与头像昵称属于社区数据，不是验证邮箱。`TestPrivacySchemaPartyBoundaryPostgres`／`TestPrivacySeededPartyRowsPostgres`。 |
| V 数据 | `services/api/verifier-migrations/0001_authprivacy.sql` 至 0004；精确邮箱、槽位、公钥、OTP/HMAC/预算、短期加密投递、确认／退役／收据及独立 Gate | 当前表／字段与合成持久行无社区 accountId、用户名、密码验证值、身份、C 安装标识或社区会话。测试只查自身一次性库，不接触真实用户。共同 slot 如既定方案仍可由串通或双侧访问连接。 |
| 实际权限 | `infra/postgres/init-auth.sh`、`grant-community.sql`、`grant-verifier.sql`、runtime `CheckDatabase`、`authlab/privacy-role-audit.sql` | R03 分别在真实 C/V 非 owner LOGIN 角色检查普通表／列／序列权限、恢复角色与业务角色及主体分离。owner 测试库不代证此项；同机分库亦不代证真实生产运营分权。C 业务角色目前只能读通道，不读取账号／身份认证资料。 |
| HTTP | `internal/authprivacyhttp/endpoints.go`／strict／peer／session／recovery／credential／identity endpoints，`cmd/api`／`cmd/verifier` 实际 runtime | 本方新 requestId、no-store，剥离来路 trace／关联头；peer 固定 HTTPS／TLS1.3／预期 SPIFFE mTLS，仅固定资格／槽位帧，不转发 Bearer／安装ID／原请求编号。`privacy_boundary_test.go` 覆盖两方向实际 TLS／mTLS，但替代业务 handler，不宣称完整业务闭环。 |
| 本人身份 | `community_identities.go`、`identity_endpoints.go`、`apps/mobile/lib/src/identity` | 会话定位账号、最终 Gate／代次／资源归属复核；不存在任意 account selector／按 UUID GET 公开身份资料入口。两账号真实 HTTPS／SQL 测试验证外来 UUID／回执键与不存在资源同形、未知字段／查询参数拒绝、对方资料及额度不变。isOriginal 和创建限制只在本人管理 DTO；公共消费者未实现。 |
| 客户端持久状态 | `main.dart`、`auth_flows.dart`、`auth_store.dart`、`auth_state_codec.dart`、`http_auth_api.dart`、`packages/auth_vault`／`auth_passkey` | 固定独立 origins、两侧随机16字节安装 ID且拒相等、本方幂等键；必要注册待办邮箱／seed／ticket／能力和 Bearer 仅安全 vault，严格 codec与写后读取确认；密码／OTP／恢复码／PoP不持久；会话持久后清注册待办。身份目录在内存，持久待办按本人隔离。新检查不代证iOS Keychain或物理设备。 |
| 恢复及管理 | 当前 C 密码／恢复码／Passkey API、账号／身份产品规则 | 邮箱 OTP 仅准入；当前没有邮箱查回／管理员强制接管旧号 API。全部独立恢复凭据丢失时不可找回旧号。未来社区管理端不能读取完整验证邮箱、普通审核员不能查其他身份；管理模块未集成。 |

## 已修复的差异

1. **应用进程错误和默认 HTTP 日志可能反射秘密。** C/V 的原始 `slog.Error(...err)` 已改为 `authprivacyruntime.LogFailure` 固定事件、service、stage、reason；不记录 driver 字符串、SQL详情、URL／路径或 panic 值。实际 HTTP server 使用 `HTTPErrorLogger`，把默认包含对端地址／异常栈的日志变为固定 transport event。测试注入带邮箱／密码／能力材料的原始错误和真实 HTTP panic，证明不回显且事件仍保留。有界 worker 只记录工作类别／计数／失败布尔／时长，未增加请求日志。
2. **数据库普通错误日志可能包含约束详情、失败 SQL 或错误主消息输入。** 两侧 compose 和 R01／R05 隔离 PG 使用固定10项私密诊断设置：statement=none、min_messages/min_error_statement=panic、verbosity=terse、两个 parameter length=0、两个 duration threshold=-1、transaction sample=0、duration=off。runtime 在当前池有效 pg_settings 不满足时拒绝启动，不替运维修改配置。普通 SQL 错误正文因此不进入服务日志；应用仍提供固定错误类别／HTTP状态及 Gate 审计。R01 使用实际 pgx 绑定的唯一键、CHECK、PL/pgSQL DETAIL/HINT 和非法 UUID 错误核对；R03在两侧实际 PG16 和 C/V 日志中加入无秘密正向控制、参数失败、非法HTTP字段和私有生命周期材料探针，并检查不安全角色设置启动拒绝。配置依据 [PostgreSQL 16 官方日志参数](https://www.postgresql.org/docs/16/runtime-config-logging.html)。PANIC／扩展、外部代理与生产日志的所有可能输出尚无独立证明。
3. **移动端已装配通道客户端反射网络异常及不受约束诊断字段。** `http_channel_repository.dart` 隐藏 Socket／TLS／HTTP异常、限制安全错误码、仅接受规范base64url16字节且body/header一致的requestId；`ChannelRepositoryException.toString` 只输出状态码，`navigation/channel_directory_controller.dart` 使用固定格式错误。保留401／429／503与安全错误码，新增4项真实TLS／IO／认证错误负向测试。未增加遥测或正文日志。

## 执行记录

| 检查 | 本轮实际结果 | 证明边界 |
| --- | --- | --- |
| Go 最终编译 | PASS，exit 0 | 编译不能代证 SQL／平台 |
| R01 全量 Go／SQL／race | PASS，exit 0 | 生成的私有socket C/V数据库；包含新增存储与HTTP归属测试 |
| R02 vet | PASS，exit 0 | R01 runner末尾既有命令 |
| R03 实际 C/V | PASS，exit 0 | 正式迁移C12/V4、真实非owner HTTPS／mTLS、角色矩阵／日志探针、AC01／AC02冻结／恢复／升级／关闭回归 |
| Flutter analyze | PASS，exit 0，无问题 | Windows Flutter3.47.5／Dart3.13.4当前完整mobile静态分析 |
| Flutter tests | PASS，exit 0，179项 | 当前完整mobile单元／widget／TLS测试；不代证原生存储系统行为 |
| R05 真实 Dart→HTTPS→SQL | PASS，exit 0 | 现有fixture handler＋真实协议／数据库，不与R03合并称物理App→实际cmd闭环 |
| 交接检查／JSON／补丁 | PASS，exit 0，当前219文件摘要／台账／链接和补丁 | 台账及源码摘要、历史证明边界、文档链接 |

首次Windows pub get未设置仓库镜像，锁定检查拒绝（exit65）；按既有锁文件的 `pub.flutter-io.cn` 重试PASS，未改依赖版本或锁文件。首轮analyze发现两项新增代码lint并已修复，最终analyze和179项测试PASS。初次WSL启动脚本发生参数／末行CR解析问题，诊断测试本体已PASS但命令退出失败；最终均通过保存LF脚本重新执行，以最终runner退出码为准。新增日志测试首轮race存在缓冲读取同步问题，已等待HTTP服务结束；数据库探针首轮标记过长，被约束DETAIL截断造成正向预期失败，已使用短标记，当前聚焦与完整SQL/race/vet均PASS。R05 Linux在线解析未推进，按归属停止pub进程并复用本轮Windows缓存离线解析，R05最终PASS。交接脚本首次遇到历史摘要的嵌套格式，修正读取后checker PASS。以上失败／修复保留在机器记录，不隐藏为首次即通过。

## 后续契约与未执行项

[匿名业务接入契约](auth-privacy-business-contract.md) 固定公共DTO不得含共同账号／本体／其他身份、每身份独立占位、最终任务受理事务的账号＋帖子绑定（含首条来源帖私信）、异步失败保留绑定和按身份对隔离会话；禁止邮箱客服恢复旧号。当前仅有B02本人管理、AC02数据库正式关闭和纯占位函数，B05–B11公共消费者、聊天本地清理／私人备注／搜索历史及媒体仍未实现，明确NOT_RUN，不仅是缺验收。

Android原生vault／系统Passkey／物理设备未在本轮重跑；iOS构建／Keychain／系统绑定恢复仍缺完整证据。入口保持 [分模块交接 R07/R09/R10](module-acceptance-handoff.md) 和 [平台历史报告](auth-privacy-device-credentials-passkey-validation-report.md)。R03、R05和原生探针验证不同边界，不合并宣称完整物理App→实际C/V全流程PASS。

P02真实主体及权限域、P03生产备份／WAL／日志留存和灾备、P04侧信道／多副本容量、P05真实域名／邮件／原生关联／签名发布、P06人类独立审计仍BLOCKED或NOT_RUN，具体见 [收口清单](auth-privacy-closure-checklist.md)。本次源码与探针审核不能批准生产。

## 交接及清理

影响A00/A01/A02/A03/A04/A05/A06/A08/A09/A10/A11/A12/A13、B01/B02与P01，以及后续X02/X06/X07。本轮通过证据只映射实际覆盖的测试，不把这些模块整体标PASS。历史AC01／AC02／平台原版本及摘要保留；最新工作区结果由currentAC03单独承载，currentFeature的旧SQL/Flutter字段保持历史快照并指向新证据。

本次临时WSL源码／模块／构建／pub缓存、Windows专用缓存及本轮Flutter生成物已清理；一次性数据库／进程／日志由runner清理，本轮Docker项目容器／卷／网络和归属进程已核验不存在。Go模块只读目录导致清理首次局部失败，按已验证归属调整本次目录权限后完成；精确结果见机器记录。保留D盘SDK／AVD／工具及已有镜像，不做全局prune。所有源码、测试与小型脱敏记录留在工作区；未提交、推送或部署。
