# FEED-INTERACTIONS-UI-01

- 更新：2026-10-20（Asia/Shanghai）。用户指定分支 `feat/feed-interactions-ui`，独立 worktree `E:/Hnuhole-env/source/HnuHole-feed-interactions-ui`；基线最新远端 main `444d25862a83d3a8d40168ef660e50da0712b71e`，旧工作区保留。
- [Draft PR #31](https://github.com/zewbby/HnuHole/pull/31)，候选源码 `f8133cf819e655a98d5d53d234a26e4a705c2d10`。实现/宿主/真实接口/构建限定通过，2004两缺陷真机复验PASS，2004评论/SQL对照已收口并交接独立报告；未合并或发布。
- 依赖独立后端 [#30](https://github.com/zewbby/HnuHole/pull/30) 的条件版本契约与0021；本PR不夹带后端提交。依赖获授权合入后须重新整合main/核对CI。0020不支持条件写，客户端不会回退到无条件写。

## 实现

每页feed成功后以postId批量读取赞/藏/评论摘要，空页不发空数组，严格FeedPost不改。批量404刷新feed一次；读取失败保留未知计数及重新读取入口。列表与详情共享账号内存状态，401/503沿原认证边界；相同有效token的活动续期保留互动锁。切账号时清视图，迟到响应及旧页面回调不能操作新账号。

同帖赞/藏共用同步锁，连点不排队产生相反请求。新意图先GET取 `Interaction-Version`，PUT发期望bool及 `If-Interaction-Version`。超时重试复用原条件；同版本即使bool相同仍不能解锁。版本永久旋转后才终结未知，412后同步当前状态，未达到期望时明确失败，用户重试才取新条件。读写重试分开，重新读取不会暗中重发旧赞/藏。

读取ticket阻止旧摘要覆盖新结果；写忙、写前失败和刷新打断的读取保留dirty需求，收尾重新查询。评论发布/删主楼及回复仍走原接口，重新读取服务端数量，不猜整楼删除量。保留原认证、发帖、身份、存储、图片及评论链路，不扩展私信、收藏列表、通知或热榜。保持确认的X布局/Telegram字体配色，收藏数在详情及列表无障碍标签使用真实数据。普通360dp保持单行，大字体合理换行。

## 验证与渲染

完整命令/输入/失败历史/摘要见[机器记录](../design/feed-interactions-ui-verification-20261020.json)。Flutter分析0、全量565项、生产bundle及全插件arm64 Android构建/验签PASS；26项互动状态/渲染及5项新增媒体回归覆盖连点、超时、412、迟到读、续期、切账号旧回调、重建Controller后旧CAS最后恢复、读写重试分离、评论刷新及360dp几何。真实TLS HTTP检查包括精确header、缺失/非法/重复版本、输入/响应绑定与412分类。

生产Dart客户端对共享444d258/C0020/V0004完成A/B登录、游标分页、commentCount与原context一致、单图/三图manifest及保护字节（CAS NOT_RUN）；对独立未合并aab1061/C0021/V0004完成前述检查、条件赞藏、账号旗标、取消后旧条件412及最终状态（6检查PASS）。另编译原生Linux探针，由环境负责人在aab1061的一次性PG55443运行 `TestRealHTTPSFeedDartPostgres`，实际10.02s PASS、零FAIL/SKIP。环境、CA、账号及结果分开；前端未更新服务/数据库。

七张实际宿主Flutter图使用合成内容、Roboto400/500/700、Noto Sans CJK SC及MaterialIcons：[浅色](../design/feed-interactions-ui/assets/interactions-light.png)、[选中](../design/feed-interactions-ui/assets/interactions-selected.png)、[深色](../design/feed-interactions-ui/assets/interactions-dark.png)、[未知重试](../design/feed-interactions-ui/assets/interactions-retry.png)、[原详情](../design/feed-interactions-ui/assets/interactions-detail.png)、[200%文字](../design/feed-interactions-ui/assets/interactions-large-text.png)、[360dp](../design/feed-interactions-ui/assets/interactions-360dp.png)。宿主图不代证设备触控。

## 候选与设备缺陷

APK不进仓库。包 `org.hnuhole.hnuhole_mobile`，main.dart/debug/arm64，min29/target36，原测试签名SHA256 `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。同签升级保留数据，环境namespace隔离会话。配方/公开defines摘要在机器记录，私钥和密码不外发。

| 候选 | 源码/环境 | APK SHA256 | 结论 |
| --- | --- | --- | --- |
| 2026102001 | abd9f35/共享0020 | `2c80ed9d6da047a3ff1afc781838389adf160aa6b645c740bb705ef247a505fb` | 历史包，FA-D01，不代证最终包 |
| 2026102002 | c3cc3bb/共享0020 | `56dca4a763c5fca8f1b8ee15b26316d1b56418e3fec8b7e1a6a2497332bb9884` | 360dp修复/原业务限定PASS，CAS NOT_RUN |
| 2026102003 | 5b5cad5/独立未合并0021 | `8b1736e6cb875586ccffc67b94b15532b8cd5776e81e8972e2f42bb3a49b3416` | 历史包，FA-D02/FA-O02，不代证最终包 |
| 2026102004 | f8133cf/独立未合并0021 | `d661bc58414a2789a0c383dc854366b135f7b5a65b50f0bdd89853ecf76be55b` | FA-D02/FA-O02真机复验限定PASS |

当前APK：`E:/Hnuhole-env/source/HnuHole-feed-interactions-ui/apps/mobile/build/feed-candidates/feed-ui-cas-2026102004.apk`，119,545,527字节。绑定独立C50649/V41979、新CA与aab1061；不是共享环境更新或正式发布。

FA-D01由设备唯一操作人在vivo S18/Android15、360dp/font_scale1.0复现互动三行/浮钮靠近分享。阈值308→260，并补360dp单行及大字体换行回归；2002真机已复验PASS，[实际修复截图](../design/feed-interactions-ui/assets/android-360dp-fixed.png)。旧图保留验收目录。该会话另报告2002原文字发布、原生三PNG选择/上传/列表与第2张查看器/原字节保存、主评及回复2→4/删主楼4→2限定PASS。准确版本分别保留，不能提升完整App/iOS/TalkBack/生产结论。前端未操作设备，详见“新版列表 Android 验收与交付”会话的独立报告（原始私有材料不复制到本PR）。2003设备另完成A→B UI登录/新身份、SQL偏好与旗标隔离、20/20/3分页及原离线评论核对封口，按原版本限定记录。

FA-D02为2003忙态按钮失去tap recognizer，外层卡片收下连点误进详情；FA-O02为图片60秒授权到期替换短占位导致操作栏移位。f8133cf以稳定no-op手势层、仅尺寸缓存及立即移除图片子树修复，覆盖按钮/媒体down-up中途状态切换、重读pending/error、迟到图片、账号失效，以及180宽2x/3x文字重读可达。Max最终静态复核无阻断；局部占位滚动设primary:false。2004已由Android唯一操作人实际同签升级、设备pull字节校验一致，B会话保留；FA-D02/FA-O02复验PASS。

有图42与无图36各10次赞+10次藏（约0.35–0.6秒），始终在列表、结束无处理中；忙态忽略点击，不声称全部点击均提交。禁用分享未导航。[有图连点](../design/feed-interactions-ui/assets/android-2004-rapid-both.png)／[无图连点](../design/feed-interactions-ui/assets/android-2004-plain-rapid-both.png)。自然83.84秒到期ImageView=0，卡片/操作栏坐标保持，赞按钮始终[400,1533][584,1677]；断C映射重读失败与恢复成功也保持同Y。[失权占位实际图](../design/feed-interactions-ui/assets/android-2004-media-expired.png)。三张图由设备负责人确认可公开的合成内容，前端再目视核对，普通状态栏图标/时间保留。

2004另用原UI完成主评+回复：详情0→1→2，回列表2；主评赞0→1→0；删除自己的主评后详情/列表均0。环境负责人对同一操作做7项只读SQL核对PASS：各marker唯一发布/受理、deleted=true/bodyPresent=true、可见0及本人评论赞false/0；仅可见删除，不称物理擦除。独立Android报告位于 `E:/Hnuhole-env/source/HnuHole-feed-android-acceptance/docs/design/feed-android-acceptance-20261020.md` 与同名JSON，保留其版本和验收边界。

FA15设备强制“请求已受理、响应丢失”暂缺可控故障入口，明确BLOCKED；普通断网、宿主交错、真实CAS及后端SQL证据分别保留，不互相代证。

## 审查及剩余

用户指定Max独立只读竞态复核，发现并修复未知写解锁、续期清锁、忙时刷新丢失、读重试误发旧写及旧账号回调等问题；最新复核未再发现阻断竞态，前提为后端版本永不复活。审查者未运行测试，不冒充GitHub成员批准。

保持draft，等待后端#30合并授权、main整合/适用CI；2004设备缺陷已限定复验PASS，FA15保留BLOCKED；缺陷继续修复补回归。不自动合并或发布，不更新共享环境、不操作设备。B03/B06增加本范围证据，B04/B07/B12/A03仅回归受影响项，完整模块结论不升级。

5b5cad5的GitHub Feed UI已实际读取job118437037626日志：宿主分析/回归/bundle通过，真实C探针conditional_like因PostFailure失败；该main0020不具条件契约。其它六workflow通过。f8133cf亦已实际读取run39366060156/job118443062283：宿主PASS、conditional_like PostFailure FAIL，其它六workflow已实际确认PASS，不从旧结果推断；#30候选上的真实Linux探针通过单独保留。
