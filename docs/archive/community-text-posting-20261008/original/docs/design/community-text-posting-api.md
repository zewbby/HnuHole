# 文字发布 API 与前端对齐清单（T1契约／T2服务端／T3客户端）

日期：2026-10-08，契约版 `0.1.0`。14个操作已在T2接入C服务端，T3本会话已实现Flutter严格DTO／HTTP适配、业务持久和页面接入；唯一机器契约仍为 [post-api.yaml](../../packages/openapi/post-api.yaml)，状态、数据约束、锁顺序和清理见[后端设计](community-text-posting-backend-design.md)。实际版本、分层命令与结果见[T2报告](community-text-posting-t2-report.md)和[T3报告](community-text-posting-t3-report.md)。T3最终Flutter分析与279项mobile测试PASS，实际C/V→SQL→Dart／完整App／设备验收待T4，T1静态及T2服务端证据按原版本保留。产品图审核独立，客户端已有实现不表示视觉获最终批准。

## 1. 路由与职责

全部位于实际C HTTPS origin，全部要求当前Bearer，全部在最终 C Gate／会话事务内读写。V不接收帖子、账号、文字或身份资料；禁止客户端选origin/accountId/ownerId。C公众内容DTO与本人任务/权能DTO分开。

| 方法／路径 | 输入 | 成功／用途 |
|---|---|---|
| PUT `/api/v1/post-commands/{commandId}` | channelId、identityId、title、body | 202原CREATE受理回执；同ID同意图重送不新增任务 |
| GET `/api/v1/post-commands/{commandId}` | 无body/query | 200原命令事实；查无UNKNOWN_NOT_OBSERVED不表示没提交 |
| POST `/api/v1/post-commands/{commandId}/seal` | 原operation及requestDigest | 200原事实或NOT_ACCEPTED封印；不是取消已受理任务 |
| GET `/api/v1/me/post-composer-context` | 无body/query | 200权威默认发言身份及是否需选择/初次设置 |
| GET `/api/v1/me/post-tasks` | cursor、limit | 200本人ACCEPTED/FAILED且visible的任务；不含其他账号/已隐藏入口 |
| GET `/api/v1/me/post-tasks/{taskId}` | 无body/query | 200本人latest版本、终态/权限和可用文字 |
| POST `/api/v1/me/post-tasks/{taskId}/cancel` | Idempotency-Key、expectedAttemptVersion | 200取消裁决回执；公开先赢返回PUBLISHED，不能把公开当失败 |
| POST `/api/v1/me/post-tasks/{taskId}/retry` | 新Idempotency-Key、expectedAttemptVersion、title、body | 202新attempt回执；同post/identity/channel，不能由UNKNOWN进入 |
| POST `/api/v1/me/post-tasks/{taskId}/hide` | Idempotency-Key、expectedAttemptVersion | 200只删除明确FAILED的本人入口，原compact事实保留 |
| GET `/api/v1/channels/{channelId}/posts` | cursor、limit | 200当前合法可见的最新卡片，无正文摘要 |
| GET `/api/v1/posts/{postId}` | 无body/query | 200正文详情；删除／不存在统一404，绝不包含viewer权能 |
| GET `/api/v1/me/posts` | cursor、limit | 200本人仍活动身份的已公开帖子列表 |
| GET `/api/v1/me/posts/{postId}/capabilities` | 无body/query | 200仅本人已公开帖的canDelete=true/canEdit=false；非本人/不存在统一404 |
| POST `/api/v1/posts/{postId}/delete` | Idempotency-Key，无body | 200删除命令回执，最后权限和owner复核；旧失效身份的本人帖仍可删 |

各mutation不接受多余query或字段；仅规定的body，重复JSON键、非法编码、重复敏感header、非规范ID／日期拒绝。canonical ID是非零UUID/16byte base64url，不能凭UUID碰巧匹配当归属证明。Idempotency-Key与CREATE path commandId采用同一个账号key域，跨操作复用相同ID而意图不同恒定冲突。

## 2. 状态与响应

| 层 | 状态 | 含义 |
|---|---|---|
| 命令 | UNKNOWN_NOT_OBSERVED | 本次读没有观察到，迟到原请求仍可能受理 |
| 命令 | ACCEPTED | CREATE/RETRY已受理，返回taskId/postId/attemptVersion |
| 命令 | COMMITTED | CANCEL/DELETE_POST/HIDE_TASK产生权威裁决 |
| 命令 | REJECTED | 持久业务拒绝，无新效果；相同命令不因后续状态变化再执行 |
| 命令 | NOT_ACCEPTED | 原ID经seal封印，迟到原请求不能受理 |
| 命令 | RESULT_EXPIRED | 防重执行墓碑仍在，但私人结果已收缩；不能推断失败或另发 |
| attempt | ACCEPTED | 已受理且未公开/未终止 |
| attempt | PUBLISHED / FAILED / CANCELLED | 不可倒退终态；DELETE帖子不改历史PUBLISHED为失败 |
| 客户端 | UNKNOWN | 丢响应／崩溃的不确定展示；没有服务端UNKNOWN任务 |

accepted命令回执是固定历史，不自动跟随task更新；客户端拿到回执后GET task。相同CREATE响应丢失不创建新command，先query；同ID同payload严格重送也安全，不能盲重放认证一次性证明，本片业务payload没有这类证明。

业务拒绝可能原mutation返回409，但其compact REJECTED可由GET command读取；失败session/503/解析错误不等于持久业务拒绝。已有invalid Bearer先401，即使key存在也不返回私人结果。超时/commit错误保留原意图，不宣称失败。

取消输入必须是实际观察的latest attemptVersion。相同取消command返回原裁决；新取消遇原attempt已PUBLISHED返回COMMITTED＋PUBLISHED，遇FAILED返回原FAILED事实。旧version不能取消新retry attempt。hide只允许FAILED，不可删除ACCEPTED/UNKNOWN卡来逃避核对。

seal只关闭“未观察到的原命令ID”。已有回执时摘要必须匹配并返回原事实；若ACCEPTED，前端让用户明确cancel该任务；若PUBLISHED，在公开帖子作者删除入口处理，不在取消里偷偷删帖。

所有成功（200/202）包含 `Session-Expires-At`、`Server-Time`、`X-Request-ID` 和 `Cache-Control: no-store`。Server-Time来自同一最终TrustedAt；deadline按当前Bearer且只在成功commit后发送。持久业务拒绝不续期；其错误响应无新deadline。所有错误含有界固定ErrorBody（error.code/message、requestId），没有原文字/数据库错误/secret；429另有1–300秒Retry-After。

## 3. 意图摘要规范 v1

不对JSON序列化字节算摘要。客户端和服务端从严格解码的字段生成下列framing：

`ASCII("HNUHOLE/POST-COMMAND/V1") || 00 || operationByte || operationFields`

UUID用RFC4122原始16字节，version用unsigned64 big-endian（但API限1..2147483647）；文本用严格UTF-8 `uint32BE(byteLength) || originalBytes`。结果为SHA256的64字符小写hex。JSON字段顺序/空白/等价escape不影响结果，文字的CR/LF、前后空格、不同Unicode正规形会影响结果。

| operationByte | operation | operationFields顺序 |
|---|---|---|
| 01 | CREATE | channelUUID16、identityUUID16、title长度帧、body长度帧 |
| 02 | RETRY | taskUUID16、expectedAttemptVersion64BE、title长度帧、body长度帧 |
| 03 | CANCEL | taskUUID16、expectedAttemptVersion64BE |
| 04 | DELETE_POST | postUUID16 |
| 05 | HIDE_TASK | taskUUID16、expectedAttemptVersion64BE |

operation目标的路径ID包含在framing；commandId属于回执定位，不进digest，Bearer/account不进公开digest。服务器key digest另用账号域HMAC，数据库fingerprint=`HMAC-SHA256(K_posts_fingerprint_v1, ASCII("HNUHOLE/POST-INTENT/V1") || 00 || digest32)`。独立keys有版本，不能用客户端提供的digest代替服务器重算。seal只能声明原operation/digest以关闭无记录key；其本身没有新commandId，重复相同seal无新业务效果。

共享设计向量在[post-command-v1.json](../../packages/post-protocol-vectors/post-command-v1.json)。它们只验证framing/hash规范，T2/T3还必须各自用真实Go/Dart库对向量执行，不能将Python算对摘要泛化为端到端一致性。

## 4. 严格DTO与前端接入

公开card仅 `postId/channelId/title/author/publishedAt`；detail额外body。作者ACTIVE仅当前nickname/avatar/state；inactive仅shortCode/avatar/state。public作者不返回identityId/accountId/slot/isOriginal、共同事件/时间、其他身份或管理权限。本人task允许最小identityId、task/post/版本及可重试维护字段，因为它只面向该账号；绝不把本人task对象混入公开列表。

ComposerContext：`defaultIdentityId`可null，`selectionState`为INITIAL_SETUP_REQUIRED/DEFAULT_AVAILABLE/SELECTION_REQUIRED。前端结合现 `/identities` 数据显示；default来源仅最近一次成功公开、无历史时原始身份及已定失效fallback，选择和受理不算公开。请求发帖仍带用户明确看到的identityId，不能凭context自动发送。

OwnTask包含serverSortAt、terminalAt、canCancel/canHide/canRetry、visible、contentAvailable；这些是展示建议不是能力令牌，每次command再授权。状态FAILED理由可为PUBLISHING_STOPPED/IDENTITY_INACTIVE/PUBLICATION_FAILED，当前禁言/关闭造成的派生停止即使worker尚未物化也必须显示不可公开。

本人列表使用已定stable排序：公开按publishedAt，未公开任务按latest acceptedAt（即serverSortAt），本机草稿按editedAt。同一logical item受理后关联task/post并移除草稿重复项，任务PUBLISHED后从pending列表移除转本人post；hidden失败GET结果不能重建入口。serverSortAt不赋予跨账号全局事件顺序。

正文清理后 `contentAvailable=false/content=null`，不从旧本机缓存恢复被明确hide/删除/关闭的内容。当前身份删除后草稿原文字保留可重选，已受理task不能变普通草稿，已公开旧帖从me列表移除但在channel有独立占位。

前端SQLite／UI图由独立Flutter任务负责，后端需要其完成环境＋账号隔离、加密payload/独立vault key、noBackup、提交上下文先持久、authority callback围栏及真实跨进程验证。T1不新增Drift依赖、不改auth vault、不生成页面或宣称客户端通过。

## 5. 分页、生命周期及停止围栏

keyset页默认20/最高50，cursor加密认证、channel/me/task作用域与当前账号绑定、30分钟trusted截止，ceiling锁定本次已公开序号上界；每页仍读当前可见性/身份资料，不恢复删除正文。详细frame和内部cursor字段见后端设计，cursor不提供公共账号/排序metadata。

publicationStopGeneration在申请注销/生效处罚同事务递增，使原ACCEPTED attempt永久逻辑FAILED；取消注销/处罚到期不自动复活。后续明确retry可在当前许可下创建新attempt、同固定identity/channel、capturing新stop代次。退出、接替、重设不会递增stop代次；worker不依赖旧Bearer，Gate暂不可用仍保留任务。

后端必须给出申请关闭/禁言/封禁/删身份联动hook及当前读取mute的实际实现；现session wrapper只有ban检查，不能只说“已有session验证”。公共feed/详情在最终Gate callback内普通JOIN读当前资料，禁止Gate前缓存或在Gate后锁其他作者行。

## 6. 待执行与交接

这份契约新增的路径尚无handler。最终认证候选、正式迁移、数据库权限/guard、worker、Go/Dart vector实现、SQLite/Flutter、实际Android以及故障runner均待后续。CP01–CP15业务验收初始NOT_RUN，独立生产安全评审未执行。

本轮规范检查／结构检查结果见[T1交接记录](community-text-posting-t1-report.md)，不可代证模块或生产PASS。契约改变时应同步后端设计和Flutter契约清单；提交号尚未固定时不能要求前端从远端取不存在的最新版本。
