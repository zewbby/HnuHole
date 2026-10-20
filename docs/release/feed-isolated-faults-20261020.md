# 新版列表隔离故障测试条件

工作项 FEED-STAGING-01，2026-10-20；对应 PR #32。仅供本机隔离测试，不进入产品服务、APK、正式部署配置或正式网络。

共享后端是已合并 `c923fa5a14919034272abd406cfaf9392bc094d8`，C0021/V0004。专用 TLS 入口 `127.0.0.1:33923` 转发到原 C51245，V49747 不变。独立旧 CAS 入口43979→C50649、V41979固定aab1061（与合并树一致），其2004设备结果保留原版本，不与2005共享结果拼接。两个入口的私有控制、证书、CA、会话、PG socket完全分开。

## 隔离与实现

源码为 `tools/feed_staging/fault_proxy.py` 和 `fault_control.py`。启动必须是非root Linux、私有属主0700根/0600配置，核实既有 integration marker、独立CAS或已部署shared-main21标识、精确源码SHA、dev模式、loopback HTTPS与对应私有PG socket/端口。共享目标仅restore-c；CAS仅source-c。没有正式模式、公网入口、HTTP管理接口、SQL写入或通用远端代理。

入口复用各自原测试TLS叶证书，严格验证上游CA；不修改系统信任、客户端guard、C/V配置、Safety Gate、授权事务或产品二进制。重复条件头保留给产品严格拒绝，重复Bearer和歧义body framing主动拒绝，正确重组有界chunked body。只转发公开API及ready路径。

每条规则绑定合成账号的当前session摘要、方法、精确路径，首次匹配后即消耗；其他账号、GET和后续请求继续透传。允许账号仅 `cas_*`、`fault_*`、明确的 `feed_front_a/b`／`feed_device_a/b`。操作者只读当前会话摘要，不登录消费者账号，不发送密钥/原Bearer。评论CREATE还须精确合成正文marker；日志只记哈希、规则ID、时间、方法/路径模板、真实上游requestId/status和白名单摘要，不记Bearer、会话摘要、密码或正文。

## 可控场景与事实边界

| 模式 | 行为及证明范围 |
| --- | --- |
| `commit_drop_response` | 完整收到真实上游200/202后hold20秒（评论35秒）并丢下行响应。非成功响应正常透传。真实上游receipt及SQL另证明提交/受理；客户端未知不能自行等于失败。hold可设0..90秒。 |
| `hold_before` | 请求只停在测试入口，尚未发送服务。操作者可先正常GET核对/重试/反向操作，再释放旧请求，观察服务端412；换会话后可观察真实401。最大120秒到期/abort不转发，不自动放行。 |
| `hold_response` | 真实上游响应停在入口，其他请求不受阻；用于账号切换后旧响应隔离。手动释放，最大120秒后丢弃。写到旧socket不等于App实际接纳；UI epoch结果由设备会话确认。 |
| `inject_401`／`inject_503` | 仅合成账号的一次GET，在入口生成状态码，不发送上游。用于UI错误处理；明确不是实际服务端会话撤销或Gate冻结证明。 |

真实服务端session replacement也已自测：旧Bearer请求在入口hold，正常新登录替代后释放，真实C返回401；没有改授权表。

评论测试已有真实202→响应丢失→原command核对/恢复→SQL一条published的宿主证据。它与“已受理后worker失败、再重试”是两个场景，后者设备 **NOT_RUN**。原worker会对缺图超过15分钟的已受理合成任务给出真实失败；若后续利用该路径，须正常受理、只阻断该任务图片上传并保留15分钟原时限，不能改可信时钟、直接写FAILED、停全局worker或以未受理seal代证。当前工具不声称提供此上传故障控制。

## 本机操作与恢复

私有config在各自 `lab/fault-proxy/`／`cas-lab/fault-proxy/`。本机封装 `E:/HnuHole-feed-staging-20261020/runtime/faultctl.py --shared` 仅使用当前共享归属；不带`--shared`指独立CAS。通过专属WSL非root Python调用 `status`、`snapshot --account ... --post ...`、`arm --mode ... --account ... --path ... --hold-seconds ...`、`release --id ...`／`abort --id ...`、`events`。每次先核对只读SQL基线、设备版本/账号/路径，再arm并交精确ruleID；禁止同时武装多个场景。规则终止前不能换规则，未命中规则由操作者abort。

只有Android验收会话操作其自有手机reverse：共享手机C51245→host33923；V保持49747。测试后精确恢复C51245→51245；CAS恢复C50649→50649。环境负责人不操作设备，不删除其他映射。紧急停止只abort规则并halt记录PID/start token的fault-proxy，原C/V保持运行；直接原端口和CA仍可用。

## 已执行验证与交接

命令 `python3 -m unittest discover -s tools/feed_staging -p 'test_*.py' -v`：真实loopback TLS与私有控制/范围/帧检查自动回归，由 `.github/workflows/feed-staging-tools.yml` 配套产品工具CI。替身TLS测试只证明入口机制，不代证业务SQL。

自有fault_*账号分别在CAS和共享c923上执行7项真实C HTTPS/SQL：真实200后drop与事实/旧412、超时旧请求释放412、合成GET401/503一次性、真实GET hold与另一账号透传、真实会话替代后旧401、真实评论202丢响应后原command恢复且单个published。消费者账号未由宿主登录，设备通过结论由Android维护。[部署证据](feed-staging-verification-20261020.json)记录具体版本/receipt/源码哈希。

两环境各以正常API、上传grant/bytes、原worker发表5种有网格/中心/边界的单图：640×360、360×640、640×640、4096×128、256×4096；严格protected manifest与原bytes逐字节一致，SHA/帖子ID在 `cas-grid-fixtures.json`／`shared-grid-fixtures.json` 本机及脱敏汇总中。夹具不代证手机正常发帖、精确4x或所有设备比例通过。

当前只有private CA隔离入口；debug功能验收可使用原pinned CA。release/profile真实设备链路及性能缺公信CA隔离入口，保持NOT_RUN；不降低正式guard或申请公网资源来绕过。正式环境未部署。

## GET注入严格契约增量

#32旧注入缺body.requestId，生产Dart会按401/503进入格式错误回退；原宿主状态码自测不能代证规范错误解析。独立 `codex/fix/feed-fault-error-contract` 补同一canonical requestId用于正文和header、无续期/不去上游的TLS断言，旧实现实际FAIL后修复12项PASS；本段为分支范围，未合并/部署前设备GET注入保持NOT_RUN。真实上游200/202 drop及旧请求412不受影响。见[任务及验证](../branches/fix-feed-fault-error-contract.md)。
