# 同机开发环境的普通关机恢复

2026-10-30；AUTH-SESSION-RESUME-01。此说明基于已实测的 C28/V7 日常开发环境，不能直接套用正式环境或之后未经核对的部署。PR #48 的 resume 与安全恢复区别继续有效；[隔夜证据](validation/session-overnight-20261030.json)记录了本次验证边界。

## 当前已核实版本与依赖

| 部件 | 本轮实际配置 |
| --- | --- |
| C/V/API 与 authdev 二进制 | 日常部署 `a2e98eb6a1b749adf6a4e003ab1aa11c378e8947`，按该部署 receipt 的 SHA256 核验；不是最新 main 重新部署 |
| PostgreSQL | 原 `restore-c/data` 的 C28 与 `source-v/data` 的 V7，沿用原 socket/端口和角色；不初始化新库 |
| 共享限流 | 原 C、V 两个独立 Redis 实例及各自原 AOF、ACL、密码文件、命名空间 |
| 评论快照 | 专用第三个 Redis，128MiB/noeviction/AOF，原端口32895；不能复用限流实例，不能重新初始化 namespace |
| 运行配置 | C：`comment-snapshot-daily-20261027-a2e98eb/candidate-c.json`；V：`shared-rate-limit-deployment-20261025/v.json`（均位于部署用户私有 home 下） |
| 运维配置 | 已核验的 `shared-rate-limit-deployment-20261025/operator/` 原 C/V operator 文件；证据签名目的和服务绑定仍须校验 |
| 手机连接 | App内开发CA与原TLS端点不变；USB reverse C51245→主机51245、V49747→主机54948，后者透明中继至WSL49747 |

私有目录、完整配置、密码、授权码、私钥和会话材料不得提交Git。部署 receipt、state、数据库 postmaster.opts 是本机核对依据；文件名或旧PID本身不证明归属。ADB仅操作本次指定序列，不使用默认设备选择。

## 普通启动顺序

1. 先确认实际部署 receipt 的版本、C/V配置、二进制摘要及数据库迁移版本匹配；确认无重复API/watch/Redis。原PID可能因重启复用，应复核用户、start tick、可执行文件摘要和参数。发现新部署或漂移时停止，不按本页历史路径覆盖它。
2. 用原 `postmaster.opts` 和原 data 目录启动两方PostgreSQL；保留原库/外部锚/密钥。读取启动前Gate状态、代次、RECOVER审计计数，以及会话记录的本地指纹。已冻结、时钟回退或锚不匹配时停止普通启动，不能自动转安全恢复。
3. 使用原配置加载 C/V 限流Redis和评论快照Redis，保留AOF/ACL与namespace。检查原端口、PID归属和数据目录，不删除Redis键、不清AOF、不运行初始化或重配置工具。Redis未就绪时不通过关闭限流/快照或隐式退回PG来启动。
4. API接流量前，用本次核验的同一authdev对C/V分别同步运行 `authdev resume -operator <该服务原私有operator.json>`；成功后启动对应watch及原API。watch自身也会立即resume，但不能把后台watch启动当作API可提前接流量的证明。普通resume不增加代次，不调用recover。
5. 用App原CA/hostname验证两方 `/health/ready` 均200，再恢复指定手机USB映射和透明V中继；不关闭TLS验证、不安装替代系统CA。证书过期时另行按批准流程处理，不能用recover或跳过证书检查掩盖。
6. 复核授权代次/RECOVER计数、原会话指纹；再冷启动已登录的同一包，确认受保护首页/账号页，且无登录、失效或不可用提示。本次未重新登录、重装、登出或清数据。若会话已自然到期、被替代/撤销或发生明确安全恢复，不应复活原令牌。

## 已发现的旧脚本问题

10月29日先前 `shared-rate-limit-deployment-20261025/safe-resume.py` 入口仍指向C27二进制，数据库实际已为C28，C启动被拒绝。本轮随即核对最新评论快照部署receipt，使用其C28/V7二进制和专用Redis恢复；无降级、迁移、清库或recover。旧 `email-auth-20261021/reconnect.py` 等也不是当前部署的权威入口。

10月30日复用了已检查的本轮恢复步骤，保留全部Redis/数据库持久数据后恢复成功。**本PR只归档说明与证据，没有修补这些机器私有旧启动脚本，也没有部署一个新的自动恢复服务。** 后续不得盲目执行旧safe-resume/reconnect；应按上述顺序结合最新部署receipt核对。私有验证脚本仅为本次人工受控验收，不作为跨版本通用launcher。

## 安全恢复仍是独立操作

`authdev recover` 会推进授权代次并废止旧会话，只能在检查冻结原因后明确执行。本次普通恢复未调用它。API、watch或Redis失败时保留日志并停在失败状态，不自动recover，不更新旧会话的授权代次。历史备份恢复/回滚证据与本次隔夜证据分开记录，不能用本次单机结果提升生产、iOS、其他设备或任意长停机保证。
