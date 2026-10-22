# AUTH-SESSION-RESUME-01：普通重启保留会话

2026-10-22；分支 `fix/session-restore`，基线main `90ba0c4`；本轮继续处理邮箱认证联调中反复出现的会话失效。用户授权排查、修复、提交交付，沿用此前PR检查通过后合并的授权；分支不带codex。

## 原因与边界

只读核对发现上次开发环境恢复执行了 `authdev recover`，C授权代次8推进9，原会话被标记RECOVERY且当时未到期。这是恢复操作主动废止会话，并非APK覆盖安装丢失数据。账号仍ACTIVE，新登录会话在代次9。不会通过放宽授权校验或提升旧会话代次掩盖问题。

新增 `authdev resume` 同代次更新证据并执行Gate.Snapshot，失败不转recover；watch启动即同步resume。预发布/集成工具增加显式resume入口，在API接流量前同步检查两方；旧start/显式recover语义保留。安全冻结、外部锚不一致、回退等仍拒绝，明确安全恢复仍废止旧会话。App运行源码和2143包不变，本轮交付工具修复。

## 验证与进度

当前实现待独立最终复核及真实隔离环境验收，尚未合并、未正式发布。Go authdev配置/签名用途测试与受影响宿主包PASS（不代证SQL）。初次尝试旧Docker runtime runner在旧权限清单拒绝现有schema，未进入本轮用例；原runner已不改动，改由维护中的预发布Lab做真实迁移/HTTPS/过期证据/原令牌保留及冻结负例回归。

入口：`services/api/cmd/authdev/`、`tools/prerelease/environment.py`、`tools/android_integration/lab.py`、[重启说明](../../tools/smtp/README.md)。涉及A02/A03/A06/A12，重启限定验收不能提升整个模块/生产结论。后续补最终命令、版本、结果及本机vivo重启记录。
