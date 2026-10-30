# AUTH-SESSION-RESUME-01：普通重启保留会话

2026-10-22；分支 `fix/session-restore`，初始基线main `90ba0c4`，已整合最新main `002b789`（私信原有改动保留，本轮不改其功能）；本轮继续处理邮箱认证联调中反复出现的会话失效。用户授权排查、修复、提交交付，沿用此前PR检查通过后合并的授权；分支不带codex。

## 原因与边界

只读核对发现上次开发环境恢复执行了 `authdev recover`，C授权代次8推进9，原会话被标记RECOVERY且当时未到期。这是恢复操作主动废止会话，并非APK覆盖安装丢失数据。账号仍ACTIVE，新登录会话在代次9。不会通过放宽授权校验或提升旧会话代次掩盖问题。

新增 `authdev resume` 同代次更新证据并执行Gate.Snapshot，失败不转recover；watch启动即同步resume。预发布/集成工具增加显式resume入口，在API接流量前同步检查两方；旧start/显式recover语义保留。安全冻结、外部锚不一致、回退等仍拒绝，明确安全恢复仍废止旧会话。App运行源码和2143包不变，本轮交付工具修复。

## 验证与进度

隔离环境及vivo限定验收已通过，独立agent代码复核无阻断（非GitHub成员批准）；最终head七类远端workflow已通过，PR #48已合入main `d450cde`，未正式发布。Go authdev配置/签名用途测试与受影响宿主包PASS（不代证SQL）。初次尝试旧Docker runtime runner在旧权限清单拒绝现有schema，未进入本轮用例；原runner已不改动，改由维护中的预发布Lab做真实迁移/HTTPS/过期证据/原令牌保留及冻结负例回归。

入口：`services/api/cmd/authdev/`、`tools/prerelease/environment.py`、`tools/android_integration/lab.py`、[重启说明](../../tools/smtp/README.md)。涉及A02/A03/A06/A12，重启限定验收不能提升整个模块/生产结论。最终原修复回执见下；隔夜追加验收见本页2026-10-30更新。

## 本轮验收结果

产品工具源码 fbf10ac（后继仅文档/主线文档整合），Go受影响包PASS、Python9项PASS。维护中的 `tools/prerelease/environment.py --root <本任务全新Linux私有目录> init --rollback-sha 002b78933e3ddc888eab02514ba3e94b3e62036a` 后执行rehearse，真实C/V HTTPS、正式C22/V6迁移、受限角色、离线证据过期后原Bearer恢复且代次/RECOVER审计不变、直接独立锚不匹配拒绝、冻结拒绝、双新实例备份恢复、旧会话安全失效与回滚/再部署全部PASS，创建的五个PG实例和进程均已停止。初次负例尝试回退证据版本被DB单调约束提前拒绝；改为前进版本制造与独立锚差异后完整重跑PASS，旧失败保留。

vivo V2323A Android15，主体2143：App强停、原C/V与watch在Gate行锁内平稳停机、用1秒短证据模拟离线过期、同代次resume后启动原API/新watch；SQL核对授权代次及全部会话摘要/撤销/截止记录逐项未变，未调用recover。手机重新启动后直接进入已登录界面，无欢迎/登录或会话失效提示，原生本机会话恢复PASS；未获取密码/OTP/恢复码，不重建账号或更改令牌。真实整机电脑/WSL关机数小时尚未做，不把2秒受控过期模拟写成整机长时间停机。

本机已加载新版开发authdev及其watch，C/V仍原邮箱测试二进制，TLS ready200，2143无需重打。临时重连脚本已改普通resume，不再固定recover。安全冻结仍需检查后显式恢复，旧安全失效会话不复活。PR #48最终head已通过远端检查和独立审查，已合并；验收记录见[机器摘要](../design/validation/session-resume-20261022.json)。

## 主线合并回执

2026-10-22：PR #48 Squash合并 `d450cdeb2375a0f3bcb885c45e2cc04f338c713a`，与最终受审head `6716ce85752f4e167bd2d58085c6ca5bad186b1e` 文件树相同。七类适用远端workflow成功（同head旧协作run被后继协作run替代），独立agent只读审查无阻断，非GitHub成员批准。本机工具已加载并通过原生会话恢复，2143无需更新；未测试整机长时间关机，未正式发布。本次合并事实由docs/session-resume-delivery补入，不递归记录其自身PR。

## 2026-10-30 隔夜追加验收（本项限定PASS）

已补齐先确认登录再关机的vivo2702隔夜恢复；约9.6小时后端无活动后原会话恢复，无重新登录，代次和RECOVER计数不变。早期“整机长关机未验”仅保留为10月22日历史时点，当前追加范围见[本次交接](docs-session-overnight-acceptance.md)／[机器证据](../design/validation/session-overnight-20261030.json)。原2143/2秒模拟结论不重写。恢复现已涉及C28/V7与第三个快照Redis，应使用[当前恢复说明](../design/session-runtime-recovery.md)，不能盲用旧本机脚本；生产/iOS/任意时长仍未验。
