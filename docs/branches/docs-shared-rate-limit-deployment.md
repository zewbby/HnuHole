# 共享限流日常开发环境部署交接

2026-10-25，分支 `docs/shared-rate-limit-deployment` 从origin/main `856313ccb800f6786502d4ddfb13678b0bfe9b2e` 开始；建分支前工作区clean，旧HEAD992126f与856313c完整树相等。本阶段沿用GPT-6.1 Sol/medium整理文档，root执行部署与手机操作；本页部署证据在提交与创建PR前形成；文档交付及CI以远端对应分支为准，手机安装后只读验收限定通过。

## 已完成的日常开发部署

目标是同机WSL既有日常开发后端，不是生产或云。root已备份并将主线856313c部署，C迁移25→27、V6→7；85旧表字段投影及序列在迁移/启动后完全一致。C/V Gate代次10/8、RECOVER事件10/8保持，正常resume未recover，不靠推进代次使旧会话失效。

C/V独立Redis56380/56381，noeviction、AOF everysec、各256MiB；新namespace generation1 READY。C的post.create/comment.publish/dm.send/dm.conversation.create enforce，其余新增规则observe，旧SQL额度/首次联系及Gate仍执行。包含旧后端45e3948之后已合并#65/#69/#68/#71/#73、文档#67/#70/#72/#74及cda337c客户端修复；不含未合并评论Redis分支。

部署发现operator模板遗漏SETNX：go-redis SetNX expiration=0实际用SETNX，SET权限不足。root只给C/V operator加+setnx，隔离Unix Redis验证先1后0；runtime仍禁SETNX/CONFIG/跨namespace。本分支最小修正文档式ACL模板及[runbook](../design/shared-rate-limit-runbook.md)，未给runtime扩权、未改业务源码。operator JSON没有ACL字段，不能添加运行时不接受的配置项。

## 手机安装与只读验收

日常包 `org.hnuhole.hnuhole_mobile` 同签名install-r成功，versionCode2026102501 / 0.1.0-main-shared-rate，source856313c；APK SHA256 `80ab61929f6462d01d6f0ef5ea1da336887ee7aa330277d0a49ba6b7a6d6e277`，原签名SHA256 `adebd158e30b0d7dfbd38bd95664aa2d1afd9c88bd824a6ca3e61abf109290ea`。首装日期2026-10-20保留，没有卸载或清数据。安装后只读验收 **PASS**：原session自动进入首页，图片/GIF、个人页五栏目和用户资料、转帖空列表、帖子详情原两条评论及图片均正常。实际手机base.apk哈希与构建完全相同，PID23324日志fatal/unhandled/HandshakeException均0。未发送帖/评论/私信/邮件；不是完整业务写入验收。

脱敏[部署机器回执](../design/shared-rate-limit-deployment-verification.json)依据root本chat实际记录及外部backend-deployment-receipt.json逐项核对；原始receipt和备份留任务私有目录，不提交备份、秘密、APK、原始日志或个人serial。旧独立2433真机四阶段、940/3SKIP和后端39结果保留原版本，不因本次部署重算；iOS/生产/云/完整容量等边界不提升，历史模块裁决保留。

## 实际Redis引擎合成主体smoke

root审源码后对已部署引擎的4个随机合成主体实际测试PASS：post.create允许5次后拒1次，RetryAfter60；comment.publish允许12次后拒1次，RetryAfter60；dm.conversation.create允许10次后拒1次，RetryAfter600；dm.send允许30次后拒1次，RetryAfter1。四项相同proof重放Replay=true且不二扣，ownstate TTL均正且有界。SQL强制readOnly，businessAPICalls=0、namespaceMutationCalls=0，无真实业务发表。外部live-rate-smoke-receipt.json已核对并将脱敏结果纳入部署机器回执；这不等于新版日常包完整API429/弱网验收，原隔离2433证据仍按原范围。

safe_resume重复执行未新增PID，旧comment-reference-20261024/resume-development.py已由root备份并转发新版本，仍保留knownDB启动。实际runtime entry.query/read.account allowed且redis_errors=0。手机截图含现有内容仅保留外部证据，不放Git。
