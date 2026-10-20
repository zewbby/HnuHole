# 列表性能与评论 worker 重试补验支持

工作项 FEED-SUPPLEMENT-SUPPORT-01；2026-10-20，Asia/Shanghai。独立分支
`codex/test/feed-supplement-support`，基线 main `30401b8034b9ffdb2df07debf4b174adb04a138c`。
状态 TOOLS_REVIEW_CI_PASS_WORKER_FAILED_RETRY_FA_D08_BLOCKED；[Draft PR #35](https://github.com/zewbby/HnuHole/pull/35) 未合并、未正式部署。

只补 profile/release 真机性能所需的标准可信 HTTPS，以及原 FA20 评论的真实
worker 失败→正常用户重试→成功。共享后端仍为 c923fa5／C0021/V0004，原隔离代理
938f7e7；不改产品、SQL、迁移、权限、时钟、Gate 或客户端开发 CA guard。
环境由本任务唯一更新，手机由 Android 会话唯一操作。旧2010 APK、ZIP、2008冻结
索引和覆盖链不覆盖、不重标；无新增合并授权。

工具新增 `tools/feed_staging/worker_failure_proxy.py`，仅在显式归属的非root Linux
dev隔离环境启动；继承已有 marker/source/socket/TLS 校验，另用私有控制目录和独立
loopback端口。用合成账号会话摘要、指定postId/body/原图SHA精确匹配一条 CREATE，
先核真实202受理回执，再正常转发；仅阻断该task/version1的image PUT。原comment
worker保留真实15分钟时限，缺图时由正常最终Gate事务写 FAILED/PUBLICATION_FAILED。
不伪造 SERVER_FAILED、不用响应丢失或政策取消替代。attempt2及其他任务正常透传。
私有release需精确规则ID；armed最多10分钟、已绑定上传阻断最多20分钟，重启机器
或到期失效。不改原33923故障入口，不提供HTTP控制接口，不记录bearer原值。

新增10项规则/lease/脱敏和真实loopback TLS回归全部通过；初版工具曾连同原12项边界实跑20项通过，原12项未变复用，最终CI自动发现22项：

```text
wsl -d HnuHole-Ubuntu-24.04 -u hnuhole -- python3 -m unittest discover -s /mnt/e/Hnuhole-env/source/HnuHole-feed-supplement-support/tools/feed_staging -p test_*.py -v
```

工具提交 `14ee26c7381aad31b30472d786d2d81a54ed4400` 的独立同事审查无阻断，
GitHub 以 COMMENT 记录，不冒充第二成员批准。适用 CI Collaboration 39435468570、
Feed staging tools 39435468400 均 SUCCESS；后者实际22项／0失败／0跳过。
这些检查只证明工具，不能代证设备闭环。后续文档提交仍须精确HEAD适用CI及审查。

用户选择免费 Cloudflare 临时隧道；官方2026.10.2 Linux程序经官方SHA256核对。
Quick URL可申请，但当前网络到edge的TCP7844出现TLS EOF/超时；进程内使用官方
DoH真实IP及宿主既有proxy CONNECT仍失败。QUIC尝试在Quick API即超时，未到
QUIC传输，不能声称UDP已验。外侧TLS亦超时，未交付任何APK defines，性能
BLOCKED；已集中询问能否换网络。内侧C/V严格原CA健康各200，未放宽验证或改全局
DNS。失败隧道进程均按身份核对收回，记录见机器证据。

一次真实原FA20：2010/B正常UI提交指定正文和PNG，真实CREATE202正常转发，
task `7202fe80-9809-483a-9720-d700ce49153e`／comment
`519c59ca-fa59-45cd-94fd-3de137b5236c`，原身份/对象不变。原worker在受理后
902.335425秒写 FAILED/PUBLICATION_FAILED（22:24:44.447348+08），原图未上传，
失败时正常清理。没有改SQL、时钟或Gate。只读SQL确认CREATE1/task1/公开评论0。
环境精确release后，2010原失败页直接点击重试一次，实际出现“请核对任务结果后再
操作。”；SQL仍只有v1 FAILED、RETRY0，登记FA-D08，不能记重试成功。前端在最新
main独立 `codex/fix/comment-failure-reconcile` 修复；保留原B/同机journal/原图/任务，
旧2010失败前未用重启/重新核对绕过；待同签候选后复验同一任务，不新建CREATE。

修复候选覆盖安装必然重启App，旧core状态可能因此自愈。该设备复验只能证明同一
原FAILED任务/原图/身份的expected1→version2正常恢复，不能声称重新复现并消除
同进程40次轮询耗尽的stale路径；该根因须由确定性宿主回归证明。保留旧2010失败
计数和回执，修复后的结果另记，不覆写为PASS。

Android已恢复C51245直连，环境核uid/startTicks/cmdline后仅停自有53381，原C/V
严格TLS健康200，原33923不动。原任务和全部证据保留，无须再开夹具或重复15分钟。
当前重试闭环和真实性能均未完成；不升级完整模块或生产结论。

操作及证明范围见[补验协议](../release/feed-supplement-support-20261020.md)，记录见
[机器状态](../design/feed-supplement-support-verification-20261020.json)。完成两项支持后
集中更新最终结果；遇新阻断只修复及复验影响范围。
