# 列表性能与评论 worker 重试补验支持

> **2026-10-21 已确认合并：**PR #35经授权Squash合入main `3611925c67137cfe43dedfdd6876a6c652f84231`（09:39+08），树与最终已审查`2eef264`相同，适用CI通过，无未解决审查线程。原共享后端／工具实例／数据与双可信URL保留，没有部署或发布；下方Draft／未合并文字保留为历史。#36本轮另获整合送合及主线日常包授权，实际结果看其PR／回执。

工作项 FEED-SUPPLEMENT-SUPPORT-01；2026-10-20，Asia/Shanghai。独立分支
`codex/test/feed-supplement-support`，基线 main `30401b8034b9ffdb2df07debf4b174adb04a138c`。
状态 WORKER_RECOVERY_AND_PROFILE2012_SINGLE_DEVICE_SCOPED_PASS_UNMERGED；[Draft PR #35](https://github.com/zewbby/HnuHole/pull/35) 未合并、未正式部署。

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
首轮Quick URL可申请，但当时网络到edge的TCP7844出现TLS EOF/超时；进程内使用官方
DoH真实IP及宿主既有proxy CONNECT仍失败。QUIC尝试在Quick API即超时，未到
QUIC传输，不能声称UDP已验。外侧TLS亦超时，未交付任何APK defines，性能
曾为BLOCKED。换网络后第二轮仍受电脑TUN路由影响，实际QUIC到edge超时；两轮
失败进程均按身份核对收回。第三轮人类关闭电脑TUN后，虚拟网卡/default route已消失，
WSL原生DNS恢复真实地址，HTTP2两隧道实际registered。外侧系统根证书/OpenSSL
chain+hostname及TLS1.3通过（Google Trust Services WE1），两侧health200与原
CA/hostname严格source200响应相同。未用noTLSVerify或修改全局DNS/产品配置/Gate。

23:03+08已交两个独立公开origins和仅C/V两键defines（SHA0338aa3b...），没有
AUTH_DEV_CA_BASE64/AUTH_DEV_PASSKEY_RP_ID。未登录feed仍401。前端从精确已验
PR36源31bc061构建同签profile2012（APK72a3f251...），stock=merged/AGP stripped=APK
链、debug kernel缺席/profile VM service存在、两origin AOT/旧CA字面缺席均核验。
5个PNG旧清单摘要曾做文本归一化，原记录保留，补充110项raw-byte摘要及等Git二进制
blob证明；未改源码/包或重建。Android独立安装回读SHA匹配、正常B登录成功，已
按预先判据完成真实帧/内存限定PASS；入口/构建/登录证明单独记录。

采样图片授权保持原<=60秒并受session expiry收紧；源码返回相对original路径，
客户端固定在新C origin resolve。到期窗口不充当正常图文样本，各20秒窗口前正常UI
重取lease并确认实图。没有扩大时限、缓存权限或改正式安全机制。隧道固定原进程/
URL保持运行，网络额外延迟与帧阶段分别报告。

一次真实原FA20：2010/B正常UI提交指定正文和PNG，真实CREATE202正常转发，
task `7202fe80-9809-483a-9720-d700ce49153e`／comment
`519c59ca-fa59-45cd-94fd-3de137b5236c`，原身份/对象不变。原worker在受理后
902.335425秒写 FAILED/PUBLICATION_FAILED（22:24:44.447348+08），原图未上传，
失败时正常清理。没有改SQL、时钟或Gate。只读SQL确认CREATE1/task1/公开评论0。
环境精确release后，2010原失败页直接点击重试一次，实际出现“请核对任务结果后再
操作。”；SQL仍只有v1 FAILED、RETRY0，登记FA-D08，不能把旧2010记重试成功。
前端基于最新main独立 `codex/fix/comment-failure-reconcile`／[PR #36](https://github.com/zewbby/HnuHole/pull/36)
修复源 `57dfe5f`，76影响回归／分析0／301原生构建任务通过，独立Max无阻断。
原CA/origins/同签debug2011保数据升级后，原B无需重登；同一原FAILED任务正常UI
只点一次RETRY，v2在22:40:28.743782+08正常PUBLISHED（受理后0.616413秒）。
只读SQL确认CREATE1/RETRY1/task1/唯一公开评论1，v1失败历史保留；完整image
manifest含mediaId、原文/身份/对象均未变，原PNG1840bytes／SHA一致。Android
实际关联读列表1/详情1/唯一正文+蓝色原图并目视四张PNG通过，未新建CREATE或再
造失败。旧2010失败及countsAfterOriginalRetry=RETRY0冻结，修复后计数另记postFix。

修复候选覆盖安装必然重启App，旧core状态可能因此自愈。该设备复验只能证明同一
原FAILED任务/原图/身份的expected1→version2正常恢复，不能声称重新复现并消除
同进程40次轮询耗尽的stale路径；该根因须由确定性宿主回归证明。保留旧2010失败
计数和回执，修复后的结果另记，不覆写为PASS。

Android已恢复C51245直连，环境核uid/startTicks/cmdline后仅停自有53381，原C/V
严格TLS健康200，原33923不动。原任务和全部证据保留，无须再开夹具或重复15分钟。
原任务恢复及实际profile2012单机预算限定通过；不升级完整模块或
生产结论。工具14ee26c
及事实提交f409399的适用CI均成功22项；本次最终文档HEAD和PR36的最终适用CI
须以对应PR实时checks与独立冻结回执为准，不用旧HEAD冒充通过。无新增合并授权。

操作及证明范围见[补验协议](../release/feed-supplement-support-20261020.md)，记录见
[机器状态](../design/feed-supplement-support-verification-20261020.json)。两项支持结果已集中同步；遇新阻断只修复及复验影响范围。

## 最终限定结果与保留状态

Android冻结 summary `afa174d5fdd2b1176f70b86969cd9056171dd4f06a9330f90899221877a5c942`，
环境逐项校验39份原引用并另冻结清理回执，位置为 runtime/supplement-perf-worker/
profile2012-final-device-evidence/；机器记录保留全部40项实际SHA。profile2012源码
31bc061、APK72a3f251、后端c923fa5/C21V4均未改变。

| 场景 | 三个有效20秒窗帧数 | build p95/p99 ms | raster p95/p99 ms |
| --- | ---: | ---: | ---: |
| S1 列表滚动 | 3121 | 1.872 / 3.001 | 4.245 / 5.025 |
| S2 图文列表往返滚动 | 3024 | 1.475 / 1.883 | 3.967 / 4.707 |
| S3 三图横滑 | 2198 | 2.637 / 3.166 | 4.140 / 4.760 |
| S4 查看器缩放/拖动/返回 | 1040 | 1.547 / 1.908 | 3.179 / 3.714 |

实际vsync60.000004Hz，预算16.6666656ms；build/raster独立判断，不能相加。
各场景两阶段超预算率0%，p95<=1预算/p99<=2预算且最慢阶段<250ms，符合测前
计划c075cb68的限定判据。S4原三窗的翻页缺口另用20秒628帧及2/3、3/3实际页码/
绿棕实图确认，不混入原1040帧；该补窗build p95/p99为5.067/8.875ms，raster
3.791/4.356ms。过期S1、误入详情S1、SystemUI中断S2、过期S4探针和第一内存
样本保留排除，只补受影响项。原保护媒体的加载/离屏重取属于实际网络场景，未
把占位图当HTTP200、未放宽原60秒lease，也不声称纯GPU或所有内容压力测试。

有效memory2同暖图10次开关+同列表静置30秒，PSS暖基线230196KiB、末三次中位
230275KiB，增量79KiB，小于原max(30MiB,20%)预算46039.2KiB；末尾实图仍可用，
未强制GC。Dart/Java/native/PSS记录分列；符合本样本预算不等于证明任意长期无泄漏。
当前PID11691从profile启动不变，当前PID log fatal/ANR0，动作可响应；该观察不等于
整机tombstone保证。总体thermal status0、USB100%，OEM soc mStatus6原值保留，
不声称每个传感器均无节流。最终只记单台RMX3366 Android14/当前60Hz设置的限定PASS。

设备自有VM forward53492/gesture JAR/UI XML已清理；profile2012/B和数据、原C/V
reverse保留。断连旧vivo的历史工具/设置清理仍待，未冒充完成。环境最终保留回执
`trusted-network3-final-retention.json` SHA915b6b8a563cff43704d887aa836a62d6739096ff8bd3384d5e5178f6942e524，
只核UID/startTicks/完整cmdline和本地侦听：network3同进程、51245/49747/33923仍在，
53381未侦听；没有新增API/SQL请求、迁移、权限、数据恢复或服务更新。继续保持
原双URL供用户测试，进程停止/换网会影响可用性；恢复按此前精确身份收回自有隧道，
重启后新URL须重建测试defines，绝不回灌旧库或弱化TLS/Gate。

PR36的31bc061七类workflow/14job SUCCESS已独立冻结；PR35本次事实文档仅要求
最终精确HEAD适用CI及独立同事复核，不重复设备/数据库场景。README既有分支入口
仍准确，本次只是该工作项结果，毋须重复修改。#35/#36均仍Draft未合并，无新合并
授权；main304仍含D08，尚无修复后最终main包，因此不是正式可发布结论。正式
发布/恢复仍沿用[原方案](../release/feed-staging-20261020.md)，正式部署等待授权。
