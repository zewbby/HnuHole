# 举报、审核与最小系统通知阶段1验证

2026-10-18，Asia/Shanghai。仓库 `zewbby/HnuHole`，分支 `codex/feat/report-moderation`；交付 [PR #18](https://github.com/zewbby/HnuHole/pull/18)，未合并、部署或发布。

## 实现与交付边界

已有帖子从 App 菜单举报，使用原键核对与迟到尝试围栏；相同帖子及证据快照跨原因合案，各份原因独立保留。电脑同源 HTTPS `/admin` 使用既有账号会话完成领取、下架、禁言、违规资料重置，管理员另可封禁及管理角色。最终事务同时写处罚、审计及通知；并发版本竞争不能重复处罚。账号级通知与原身份通知隔离，列表不标已读，详情显式读单条。

处罚独立计时并保留迁移前限制基线；误判撤销按剩余有效事实汇总，作者已删内容不能复活。每项处罚最多三轮且同时一轮待复核，原处理人回避；首报与追加材料逐批分页。被封禁账号可独立复验既有私有密码，获取24小时本人处理能力，不接替社区登录、不取消注销。管理 DTO 不下发邮箱、内部映射、其他面具或举报人身份。

契约最先正常推送为 `60e5df4`；评论任务可先对接 [report-notification-contract.md](report-notification-contract.md)。本阶段不依赖评论表。阶段2在评论合入 main 后接评论举报和真实失败 provider；完整私信、聊天证据、互动收件箱及系统推送不在本轮。

## 被测版本与环境

创建基线 `8fa9cbc`；共享接线前正常整合 main `986477b4cbdaeb3fef7749961f6ee9b60d5d1ffb`（含PR #13）。正式迁移原至0014，本任务0015；没有覆盖既有迁移或复制其他 session 未提交成果。

最终产品与测试候选 `aab9a647d9c8310e344bbc767abb5cbdc1045f73`。632个源码、测试、配置与工作流blob排序清单的SHA-256为 `93116225c497d2c2b3be3388ccf327a817207d318314fce228db3972aab32646`；算法、输入范围及CI链接见[机器记录](report-moderation-verification.json)。后续收口只改Markdown与验收JSON，交付head另核对输入指纹不变。早期 `6e0b406` 后还有实际授权、旧处罚兼容及生命周期修复，不能用早期结果冒充最终候选。本文件不把未执行或SKIP记为PASS。

本任务只使用 `E:/HnuHole-report-moderation-20261018` 及其独立 Linux runtime；Go1.22、PostgreSQL16私有无TCP socket、Goose v3.22.1、Flutter3.47.5、独立 Pub/Go/Python 缓存与合成账号。实际探针只信任一次性P-256测试CA；浏览器自签例外仅属于合成loopback context，没有修改系统信任或产品HTTPS边界。测试结束关闭浏览器、服务与临时数据库。

## 当前已执行证据

| 检查 | 结果与证明范围 |
| --- | --- |
| 新治理及隐私、帖子schema真实SQL/race | 最终 `sql-release.log`：47个顶层PASS、零FAIL/SKIP，三个包通过；含原结果、合案、越权、并发、通知隔离、单条读、独立处罚、生命周期、审计及Goose14→15/Down拒绝 |
| 实际Dart→Go C／SQL→Edge | 最终本地及CI均PASS：原举报核对及旧尝试409→实际Go `/admin` 登录/领取/MUTE3天/审计/退出→通知读及申诉3批分页→另一管理员复核→结果→另案BAN后独立本人通知/申诉；没有网页API替身 |
| Flutter宿主 | 最终候选Linux CI及Windows本地均analyze0、完整439项PASS、debug bundle通过；不代表原生/手机存储验收 |
| Go宿主 | 最终候选CI全包test/build/vet通过；无DSN项不计SQL证明 |
| 正式契约 | 最终候选CI对9份固定版本OpenAPI validator全部通过；本地材料分页与只读字段正反形状另外核对 |
| 管理页面 | Node12项PASS，实际Go页由浏览器直接验证；截图只含随机平台编号及合成证据 |
| 全部继承SQL/race | 最终 `sql-all-release.log`：321个顶层PASS、零FAIL；两个既有F4/mobile独立Flutter入口因未配置runner明确SKIP，不计通过。三个包通过，治理链零SKIP |
| GitHub Actions | 产品候选4工作流、7任务全部通过，治理SQL工作显式执行Goose、Dart、Chromium，无治理链SKIP；链接见机器记录 |

## 独立审查与修复

独立agent审查推动修复：快照初验失败时可能跳过管理角色准备、合案丢失后续原因、跨账号外键锁序、通知详情身份过滤、旧配置生命周期权限、旧处罚汇总及不可逆Down。最终 `aab9a64` 的授权修复经独立只读复核，无阻断问题。Agent审查不等于GitHub成员批准。

关键负向证明包括 `TestModerationStaleSessionCannotSkipManagementAuthorizationPostgres`（普通账号读取案件、材料及自提角色均403）和 `TestModerationConcurrentSessionRenewalAndFinalClockPostgres`（正常续期排队成功，真实未来时间拒绝且action不执行）。仅初验副本延后lastActivity检查，prepare必经，最终仍以原会话严格校验。独立处罚、三轮且唯一待审、原处理人回避、撤销和作者删除不复活分别由appeal/reversal、overlap及concurrent用例覆盖。受限本人能力另覆盖过期、凭据接替、Gate代次、用户名复用、注销不取消和锁序。

新旧处罚先后顺序及永久限制通过 `TestModerationLegacyRestrictionInteroperabilityPostgres` 和最小权限/0015前兼容回归；已迁移库即使关闭posts/moderation开关也执行必要清理，缺少权限、hook或旧基线列时启动拒绝。

保留失败历史：早期全量发现夹具残留Goose表及缺少PG日志导出，UTC序列化和网页smoke操作重载前旧表单，均已修复。随后全量暴露真实并发续期503，最终修复保留prepare及最终可信时间边界，并经SQL、实际网页和CI复验。旧 `sql-verified.log` 曾被Go默认十分钟中断，余下121项另行补跑通过；最终全量以25分钟上限重跑，旧超时不计PASS。

## 重跑入口

依 [services/api/README.md](../../services/api/README.md) 准备原C/V开发环境、owner顺序迁移与最小grant，设置 `moderation:true`、已有posts及可选postImages，`adminDirectory` 指向本分支 `apps/admin`。owner用 `bootstrap-moderation-admin.sql` 为已有ACTIVE合成账号创建首位管理员；以后通过管理界面分配角色。

从 `services/api` 执行 `sh authlab/run-moderation-isolated.sh`，runner拒绝root及外部DSN，只建立自己的私有socket临时库。使用独立 `PGPORT/GOCACHE/GOMODCACHE`、固定 `POST_MEDIA_PYTHON/POST_MEDIA_FIXTURES` 及 `MODERATION_GOOSE`。从 `apps/mobile` 锁定依赖后 `dart compile exe integration/governance_live_probe.dart -o <本任务路径>`，设 `MODERATION_PROBE`；真实浏览器配置见[工作台说明](../../apps/admin/README.md)。`MODERATION_TEST_PATTERN=.` 与 `GOFLAGS=-timeout=25m` 运行全部继承SQL套件。CI显式执行探针、Goose及私有浏览器，不用SKIP冒充链路通过。

## 剩余边界

评论举报及真实评论失败任务尚未集成，按阶段2推进；B08/B11保持部分实现，不宣告完整模块PASS。当前候选手机/原生插件验收未做，跨设备Passkey NI-X02及iOS按用户要求延期。生产独立安全运营及证据保留/清理政策尚未验收，本轮无自动销毁任务；不把缺少清理政策当作永久留存批准。未合并、未部署或发布。
