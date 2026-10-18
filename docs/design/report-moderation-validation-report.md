# 举报、审核与最小系统通知阶段1验证

2026-10-18，Asia/Shanghai。仓库 `zewbby/HnuHole`，分支 `codex/feat/report-moderation`；本阶段尚未合并或发布。

## 实现与交付边界

已有帖子从 App 菜单举报，使用原键核对与迟到尝试围栏；相同帖子及证据快照跨原因合案，各份原因独立保留。电脑同源 HTTPS `/admin` 使用既有账号会话完成领取、下架、禁言、违规资料重置，管理员另可封禁及管理角色。最终事务同时写处罚、审计及通知；并发版本竞争不能重复处罚。账号级通知与原身份通知隔离，列表不标已读，详情显式读单条。

处罚独立计时并保留迁移前限制基线；误判撤销按剩余有效事实汇总，作者已删内容不能复活。每项处罚最多三轮且同时一轮待复核，原处理人回避；首报与追加材料逐批分页。被封禁账号可独立复验既有私有密码，获取24小时本人处理能力，不接替社区登录、不取消注销。管理 DTO 不下发邮箱、内部映射、其他面具或举报人身份。

契约最先正常推送为 `60e5df4`；评论任务可先对接 [report-notification-contract.md](report-notification-contract.md)。本阶段不依赖评论表。阶段2在评论合入 main 后接评论举报和真实失败 provider；完整私信、聊天证据、互动收件箱及系统推送不在本轮。

## 被测版本与环境

创建基线 `8fa9cbc`；共享接线前正常整合 main `986477b4cbdaeb3fef7749961f6ee9b60d5d1ffb`（含PR #13）。正式迁移原至0014，本任务0015；没有覆盖既有迁移或复制其他 session 未提交成果。

产品核心提交 `6e0b406`；其后仅测试、工作流及交接收口时分别记录。最终输入集合、实际运行与 PR/head 回执见[机器记录](report-moderation-verification.json)。本文件不把未执行或SKIP结果记为PASS。

本任务只使用 `E:/HnuHole-report-moderation-20261018` 及其独立 Linux runtime；Go1.22、PostgreSQL16私有无TCP socket、Goose v3.22.1、Flutter3.47.5、独立 Pub/Go/Python 缓存与合成账号。实际探针只信任一次性P-256测试CA；浏览器自签例外仅属于合成loopback context，没有修改系统信任或产品HTTPS边界。测试结束关闭浏览器、服务与临时数据库。

## 当前已执行证据

| 检查 | 结果与证明范围 |
| --- | --- |
| 新治理真实SQL/race与HTTPS | `sql-6.log` PASS；举报原结果、合案、角色越权、两人并发一次处罚、身份通知隔离、单条读、作者删除与独立处罚恢复、受限能力、审计及Goose14→15/Down拒绝 |
| 实际Dart→Go C／SQL→Edge | `sql-live-7.log` PASS：Dart原举报核对及旧尝试409→Edge真实登录/领取/MUTE3天/审计/退出→Dart通知读及申诉3批分页→另一管理员复核→Dart结果→另案BAN后独立本人通知/申诉；不是网页API替身 |
| Flutter宿主 | 主集成目录 analyze0、完整439项PASS、debug bundle PASS；不代表原生/手机存储验收 |
| Go宿主 | Linux全包 test/build/vet PASS（`go-host-1.log`）；无DSN项不计SQL证明 |
| 正式契约 | 9份固定版本OpenAPI validator PASS；材料分页与只读字段正反形状另外核对 |
| 管理页面 | Node12项PASS、合成HTTPS浏览器与实际Go页分别记录；实际截图只含随机平台编号及合成证据 |
| 全部继承SQL/race | 正在固定候选执行；最终结果由机器记录补齐，不沿用历史通过数量 |

## 独立审查与修复

独立agent审查发现并推动修复：会话快照初验失败时可能跳过管理角色准备；合案后丢失后续举报唯一原因；跨账号外键锁顺序；通知详情身份过滤；旧配置迁移后的必需生命周期权限；不可逆Down不能静默倒退Goose账本。针对前三类含控制时序及真实SQL回归，静态复核与动态结果分开记录。Agent审查不是GitHub成员批准，不伪造独立成员审批。

## 重跑入口

依 [services/api/README.md](../../services/api/README.md) 准备原C/V开发环境、owner顺序迁移与最小grant，设置 `moderation:true`、已有posts及可选postImages，`adminDirectory` 指向本分支 `apps/admin`。owner用 `bootstrap-moderation-admin.sql` 为已有ACTIVE合成账号创建首位管理员；以后通过管理界面分配角色。

从 `services/api` 执行 `sh authlab/run-moderation-isolated.sh`，runner只建立自己的私有socket临时库。使用独立 `PGPORT/GOCACHE/GOMODCACHE`，固定验证器的 `POST_MEDIA_PYTHON/POST_MEDIA_FIXTURES`，并设置 `MODERATION_GOOSE`。从 `apps/mobile` 先锁定依赖再 `dart compile exe integration/governance_live_probe.dart -o <本任务路径>`，设 `MODERATION_PROBE`；真实浏览器配置见[工作台说明](../../apps/admin/README.md)。`MODERATION_TEST_PATTERN=.` 可运行全部继承SQL套件。CI工作流显式安装和执行探针、Goose及私有浏览器，不用SKIP冒充链路通过。

## 剩余边界

评论举报及真实评论失败任务尚未集成，按阶段2推进；B08/B11保持部分实现，不宣告完整模块PASS。当前候选手机/原生插件验收未做，跨设备Passkey NI-X02及iOS按用户要求延期。生产独立安全运营及证据保留/清理政策尚未验收，本轮无自动销毁任务；不把缺少清理政策当作永久留存批准。未合并、未部署或发布。
