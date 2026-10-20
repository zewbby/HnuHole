# 列表性能与评论 worker 重试补验支持

工作项 FEED-SUPPLEMENT-SUPPORT-01；2026-10-20，Asia/Shanghai。独立分支
`codex/test/feed-supplement-support`，基线 main `30401b8034b9ffdb2df07debf4b174adb04a138c`。
状态 TOOLS_LOCAL_PASS_REVIEW_AND_CI_PENDING；未合并、未正式部署。

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

这只证明工具，不代证真实SQL、15分钟worker或设备。既有
`.github/workflows/feed-staging-tools.yml` 自动发现全部测试；最终精确HEAD必要CI、
独立审查和一次设备闭环尚待，保持未完成结论，不省略仓库门槛。

用户已选择免费临时HTTPS隧道：准备两个独立公开测试origin，外侧系统信任链、内侧
原私有CA和hostname均严格验证；只连接本次合成隔离服务，保留App/Gate校验，不触及
正式资源。可信入口的实际连通、证书链、版本和公开defines待就绪后一次交接。

操作及证明范围见[补验协议](../release/feed-supplement-support-20261020.md)，记录见
[机器状态](../design/feed-supplement-support-verification-20261020.json)。完成两项支持后
集中更新最终结果；遇新阻断只修复及复验影响范围。
