# 隔离补验协议：可信 HTTPS 与原评论 worker 失败重试

FEED-SUPPLEMENT-SUPPORT-01，仅2026-10-20本轮合成隔离环境。任务及状态见
[分支记录](../branches/test-feed-supplement-support.md)。产品和现有恢复方案不变；正式
环境没有访问、部署或恢复授权。下述协议与实际结果分别记录；一次真实worker失败
及2011候选同一原任务恢复限定PASS，旧2010 FA-D08失败保留，真实性能BLOCKED。

## 可信入口

profile/release必须省略 AUTH_DEV_CA_BASE64 和 AUTH_DEV_PASSKEY_RP_ID，保留现有
debug-only guard；只提供独立 AUTH_COMMUNITY_BASE_URL/AUTH_VERIFIER_BASE_URL。
用户已选择临时Cloudflare Quick Tunnels，流量经过第三方公网测试入口，停止隧道即
撤销地址。须先核外侧标准链/SAN/有效期和健康响应，以及内侧原CA/hostname验证，
不得使用 noTLSVerify 或全局信任修改。C/V内部通信、配置和Gate不变；只转发至本轮
已确认的C/V公共端口，不转发PG、内部mTLS或管理控制端口。隧道网络开销单独记录，
不能把帧耗时与网络响应时间混称生产性能。

当前尝试为BLOCKED：Quick API申请URL成功，但TCP7844 edge TLS EOF/超时，
外侧TLS不可达；官方DoH真IP和宿主既有proxy CONNECT亦未恢复。QUIC两次在API
阶段超时，未检验实际QUIC传输。原C/V严格TLS健康200，未放宽noTLSVerify或修改
全局DNS/产品配置，未交付不可用defines。失败自有隧道已精确停止；集中等待可用
网络，保留官方程序供之后重试。不能据此声称可信证书链或profile性能已验。

## 一组评论夹具

目标为正常App账号B，在自有三图帖 `0d733843-f3d4-49ed-b009-4b140b36f2c7` 下发一条
主评论，body `FA2010WorkerRetry1020`，正常Picker选自有横图640×360／1840bytes，
SHA256 `1fe401f1342a36ea348b936e4a5551533ed4aad59226d5459b065d0ff8d6eb71`。
正常CREATE生成的taskId和身份由App/C决定，环境不登录设备账号或另建任务。

1. 环境先确认归属/无同marker任务/唯一有效B会话的只读基线，启动另一个loopback
   HTTPS入口。独立审查与适用CI通过后，交精确源码/工具哈希、端口与一次组窗口。
2. Android只将自有C映射切至夹具入口；正常原UI提交一次。工具精确匹配B会话摘要、
   postId/body/图片SHA，真实C返回 CREATE ACCEPTED/202且task/version一致后才绑定。
   原202正常转发；记录真实requestId、响应SHA和任务ID，不落bearer或command原值。
3. 仅该task/version1/image的原图PUT不转发。其他任务/账号/方法、task读回与
   attempt2上传不阻断；不能暂停全局worker、改accepted_at、改可信时钟或SQL写FAILED。
4. 保持原15分钟时限，Android保留原任务/同机原图与草稿；只读SQL以该task验证
   ACCEPTED→FAILED/PUBLICATION_FAILED和terminal_at。该码由真实worker产生；历史
   SERVER_FAILED标签不替代实际线码。不把客户端transport提示当worker失败。
5. 环境以精确规则IDrelease。Android从原failed任务正常“按原身份和对象重试”，
   同一task/binding、expectedAttemptVersion1、新RETRY command，原图正常上传到2。
   以实际UI和只读SQL验证version2 PUBLISHED、归属不变、仅一条公开评论/一个task，
   CREATE/RETRY回执各一、旧attempt1失败保留，无重复发表。
6. 完成后Android恢复原C直连映射，环境再停止自有夹具进程；保留失败和成功事实及
   清理记录，不自动删除帖子/评论/任务。不增加另一种PostTask失败或整套故障回归。

工具通过私有文件控制：`worker_failure_proxy.py --config <owned-private-config>
serve|arm|status|release`。配置沿用原fault purpose/已部署source字段，并显式加
`fixturePurpose=hnuhole-comment-worker-upload-v1`；独立控制目录必须是归属lab下
`worker-failure-proxy/`、0700。规则文件0600且非symlink，只允许account/sessionDigest/
postId/bodyMarker/imageSha256；不接收任意URL/SQL/任务状态或第三方账号。
armed10分钟未命中自动失效，绑定后20分钟停止阻断；boot改变失效。终止异常时先由
Android恢复直连，环境才停代理。真实失败未发生或已过期即如实记录NOT_RUN/未命中，
不能改判据造失败。

## 实际执行与恢复

工具14ee26c已独立review无阻断，两项适用CI成功且实跑22项。已仅在隔离环境以
该未合并候选开53381，真实C仍c923fa5/C0021、V0004。2026-10-20正常2010/B一次
CREATE后，task7202fe80-9809-483a-9720-d700ce49153e在22:24:44.447348+08由原
worker自然写FAILED/PUBLICATION_FAILED，距受理902.335425秒。精确规则release
后原失败页一次重试提示“请核对任务结果后再操作。”；只读SQL仍FAILEDv1、CREATE1、
RETRY0、公开评论0，登记FA-D08交前端独立修复，不能冒充完整闭环通过。

随后前端PR36修复源57dfe5f通过76影响回归／分析0／301原生任务及独立Max审查。
原CA/origins/同签debug2011保数据覆盖安装后，Android用原B/同一原任务/原图和
身份正常点一次RETRY。v1失败历史保留，v2于22:40:28.743782+08 PUBLISHED；
真实持久回执CREATE ACCEPTED×1（attemptVersion1）／RETRY ACCEPTED×1（attemptVersion2），
RETRY committed_at为22:40:28.127369+08，
task1/公开评论1/原完整图文manifest及SHA一致。原HTTP响应未抓包，不编造requestId；
回执以只读SQL为准。Android关联读列表1/详情1/唯一图文并目视四张PNG，限定通过。
旧2010 FAIL与修复后结果分别冻结；最终精确PR HEAD CI另查live checks和冻结回执，
不因候选设备恢复提前宣告合并或正式发布。

Android已恢复手机C51245直连并保留原数据；环境验证自有进程身份后只停53381，
C/V原入口严格TLS各200，原33923不动。保留原失败历史及随后同一任务正常RETRY2
成功记录，不新建任务、不重复15分钟夹具。覆盖安装必然重启，设备只能证明该原
任务正常恢复，不能单独证明同进程
40次轮询耗尽的stale已修；根因修复另由确定性宿主回归证明。旧2010失败与修复后
结果分开记录，保留各自被测版本。全部证据见
[机器记录](../design/feed-supplement-support-verification-20261020.json)。本轮没有
数据库迁移/权限/材料/Gate变更，不执行数据库恢复；已有正式发布与恢复方案仍为
[原方案](feed-staging-20261020.md)，历史备份不包含之后的设备数据，不盲目回灌。
