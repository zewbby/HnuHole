# DM-P3-GOVERNANCE：私信治理、通知与正式装配

2026-10-23 合并回执：[PR #52](https://github.com/zewbby/HnuHole/pull/52) 已正常 merge 到 main `665291cdf312dec94fb11a75527524a821c5f008`，被核对 head `483fe9a237c38f03768f859935b9020b9520267a` 的 20 条适用检查全部成功；另有正文编辑取消的旧 policy，后继 policy 已成功。主整合会话独立只读审查 PASS。原生人工项仍 SKIP、厂商远程推送仍未实现、iOS／生产仍未验，不提升 B08/B09 整模块结论；未部署／发布。下方 Draft／未合并状态为历史快照。

2026-10-23 主线整合更新：用户已明确授权将 P2 #51 → P3 #52 → 设备补验 #55 依次合并 main 并构建，覆盖此前“保持 Draft／无合并授权”的阶段约束；原生 SKIP、远程推送未实现及 iOS／生产未验结论不变。P2 已以 `988bb42045f4140c46cf9e890d985a774d033e16` 合并，P3 改以 main 为 base 并整合该提交；仅四份文档顶部插入冲突，完整保留双方记录。DM／P3 产品与测试树仍与 `07923b0` 相同，auth 运行代码／测试等于 main。受影响真实根通知／登录导航由新 head 的产品 CI 覆盖，不重复本地已通过的 75 项或旧设备验收；须通过精确 head 全部适用检查后再合并。下方为历史阶段记录。

2026-10-23，分支实现及宿主增量验收通过，人工原生项跳过，Draft 送审，未合并／未发布。分支 `feat/direct-message-governance`。

送审：[Draft PR #52](https://github.com/zewbby/HnuHole/pull/52)。应用验证源码 `cd6049e`，预发布审计修复 `96611a5`、V边界测试清单修复 `f2e9c8a`；最终精确 head 的远端 CI 以 PR Checks 为准。

依赖 [P2 PR #51](https://github.com/zewbby/HnuHole/pull/51) `d864d03`；开始时最新 main 为 `e8ff488`，P2 尚未合并，因此本 PR 以 P2 分支为 base，须按 P2→P3 顺序整合，不代替用户合并授权。

范围：账号级拉黑与解除；连续区间私信举报、固定证据快照与真实性校验；身份删除和正式注销清理；Android 隐私本地通知、同账号点击恢复；正式 Flutter 装配。保留现有面具、C 最终 Gate、先落地后 ACK 及普通历史仅本地的规则。

验收仅新增及受影响部分。P1/P2 未变化的字体、布局、IME、九图可靠存储沿原版本证据复用。用户本轮明确不在，需要人工解锁、安装确认、系统权限确认或外部凭据的项目直接 SKIP，不等待人工。

厂商远程推送尚无渠道配置；本地系统通知不等于杀进程后远程唤醒。iOS、生产运营保留策略、正式部署发布另列未验／待授权，不因代码接入提升为全部完成。

后端复杂授权／证据及客户端生命周期竞态按用户此前指令由 Astra High 承担；[生命周期实现与限定测试](fix-direct-message-lifecycle.md)。应用源码 `cd6049e931f99f32004abd83f48b1518fd1b03e5` 经独立 Astra High 只读精确复核，无剩余可操作阻断；此为 agent 审查，不是 GitHub 成员批准。随后预发布审计修复另经主 agent 独立只读审查，范围与结果如下，远端 CI 以 PR 精确 head Checks 为准。

## 本轮交付

实现账号级阻止发送与显式面具黑名单、授权的连续区间举报／固定快照／真实性校验、管理员结构化证据及现有处罚申诉复用、身份删除和正式注销清理、Android 默认隐藏内容的本地通知及同账号点击恢复、正式 Flutter 入口。契约及预算见[第三阶段规则](../design/direct-message-governance-contract.md)；SQL／迁移／后台交付见[后端记录](../../services/api/authlab/dm-governance-handoff.md)。服务端开关仍默认关闭，没有部署。

只验新增及受影响部分。真实SQL／race／HTTPS、5份受影响OpenAPI、13项后台Node、Go build/vet、生命周期46项及举报／通知／导航和材料存储定点验证均保留具体版本和范围。最终新增客户端TLS串联、APK、源文件hash及独立审查绑定见[机器记录](../design/direct-message-governance-verification-20261023.json)。没有将旧阶段验证全部重跑或扩大结论。

审查及联调修复：旧图片没有新版证据字段仍可通过原图摘要举证；ABSENT与文字目录兼容新增字段；通知空闲帧调度、未登录冷启清旧通知、聊天未退出时第二次通知跳转；黑名单时间统一UTC。此前失败及修复回归保留在机器记录，不改写为一次通过。

首轮远端 head `fc4f986546085e4706255f430055ab8fea18a060` 的19项检查为18项成功、rehearsal失败：0024清理授权已生效，旧共享审计没有对应c_dm矩阵。Astra High补齐精确表／列权限审计，未扩大正式授权；两个新建自有C/V PostgreSQL、真实Goose迁移和原Lab.audit正例及8项越权反例通过，CI显式启用该回归。补丁 `3e6009b` 集成为 `96611a5f7ce8b06eed57d12eef17b65d9c95e7cf`，主agent独立只读审查无剩余可操作问题。与`cd6049e`比较，Flutter／Android、后台、服务运行源码、迁移、OpenAPI和正式授权文件树均相同，原应用／APK证据沿原版本保留；本地未重复构建。完整远端rehearsal仍待新head CI，不将增量SQL回归等同整套预发布通过。

第二轮 head `73892f3e1c0f5d1b2a1dc1b8f3b4ea17e7b5ae9a` 的20项检查为19项成功、gate-postgres失败；新增权限正反例、完整rehearsal、候选包及Android均成功。唯一失败是既有0005／0006邮箱登录表`v_auth.email_login_confirmations`漏列于精确V关系清单。Astra High核对该表不含C账号／身份／会话字段后只补准确表名，保留精确匹配、禁止列及跨库桥接检查；自有SQL／race的community和verifier两子例PASS3.93s，fixture已停止。补丁`fa9c4a4`集成为`f2e9c8a5e75ef6423bf949b674408e9b447891a4`，主agent独立只读审查无阻断；只改测试及交接，应用运行输入仍与`cd6049e`相同。最终head的完整CI待远端结果。

## 未验与接续

用户明确不在，RMX3366处于锁屏息屏，未申请设备租约、安装或解锁；系统权限、真实通知冷启／切换、原生注销清理和最终包冒烟 SKIP。可继续自动化工作已完成后提交 Draft，必要原生验证缺失期间不得合并。厂商远程推送 NOT_IMPLEMENTED，iOS和生产 NOT_RUN；B08/B09整体验收结论不提升。

接续时先核对 PR head 与机器记录，再只补上述跳过项。P2 #51 尚未合并，本分支以 `feat/direct-message-chat-completion` 为PR base，按 P2→P3 顺序整合。没有第三阶段合并或发布授权。
