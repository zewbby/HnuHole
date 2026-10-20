# 隔离补验协议：可信 HTTPS 与原评论 worker 失败重试

FEED-SUPPLEMENT-SUPPORT-01，仅2026-10-20本轮合成隔离环境。任务及状态见
[分支记录](../branches/test-feed-supplement-support.md)。产品和现有恢复方案不变；正式
环境没有访问、部署或恢复授权。当前工具尚未武装，不能将下述协议当实际设备PASS。

## 可信入口

profile/release必须省略 AUTH_DEV_CA_BASE64 和 AUTH_DEV_PASSKEY_RP_ID，保留现有
debug-only guard；只提供独立 AUTH_COMMUNITY_BASE_URL/AUTH_VERIFIER_BASE_URL。
用户已选择临时Cloudflare Quick Tunnels，流量经过第三方公网测试入口，停止隧道即
撤销地址。须先核外侧标准链/SAN/有效期和健康响应，以及内侧原CA/hostname验证，
不得使用 noTLSVerify 或全局信任修改。C/V内部通信、配置和Gate不变；只转发至本轮
已确认的C/V公共端口，不转发PG、内部mTLS或管理控制端口。隧道网络开销单独记录，
不能把帧耗时与网络响应时间混称生产性能。

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
