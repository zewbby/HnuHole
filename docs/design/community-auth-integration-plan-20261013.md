# 社区＋认证联合回归与单台Android验收

> **2026-10-14 当前统一任务单：**用户将双实体Android验证追加到原三项工作之后，顺序为①单机文字社区流程②原生存储与生命周期③系统Passkey及单机回归④双设备NI-X01/NI-X02。见[四阶段统一任务单](community-android-unified-acceptance-plan-20261014.md)。当前只更新计划/交接，没有新增测试或设备操作；单机窗口仍延期，第二设备与两机窗口尚未确认，RP/package/signature关联须另行准备审批。20261013主机/构建证据和其“排除第二设备”保留为原范围历史；新任务整体须四阶段全部收口才通过，iOS/生产和未实现业务仍独立。

> **Git与清理回执：**整合后源码提交`28cee4656edd710d60676a81794c20cd49f45351`（父提交为上述社区保存SHA和固定认证SHA）已正常推送且远端核对一致。此后交接回执仅改文档/台账，443项运行输入未变。三处canonical任务根经owner与进程核对后清理PASS，约11.07GiB逻辑文件、SDK副本/缓存/APK/合成CA及调试私钥均删除，源码、测试、脱敏记录与外部复验脚本保留；不做VHD压缩或全局清理。见[交付回执](community-auth-integration-delivery-20261013.json)。设备仍按用户指令延期，后续须重建独立材料并获得窗口，不能把已删除APK/签名当作可直接安装的制品。

日期2026-10-13。任务目录 `E:/HnuHole-community-f4-20261012/repo`，分支 `codex/community-flutter-pages`。原起点4d58116bdde2c1d2d406b965590bc1625a5c7955；保存并推送7452dadefb52e7b695cdd1079d21083fcb6cae02；固定认证d859cb05c772cdf8d8b75e439a2bfedf0414dd46。原主机mobile311和认证22/0/2不是联合验收。

1. 审查/保存当前20文件：已完成，只纳入源码、测试及脱敏交接，普通推送；不含私钥/账号/数据库/缓存/APK。
2. 对固定已提交认证候选三方整合，保留文字页、closure owner/业务vault、SQL0013/最小权限及锁；更新差异清单。没有重做页面或新增业务。
3. 独占SDK/cache/新PG/端口执行checks→auth-regression→integration→server→posts-privileges→auth-runtime(R03)→最终vet；两原生插件分析、Passkey现有Dart测试、宿主守卫/JVM策略及OpenAPI按实际入口复验。每项保存退出码/日志/源码指纹，失败不关闭校验，最后修改重跑受影响项。
4. 原生Android标准main Debug/Release及instrumentation构建、manifest/DEX/签名与实际插件准备；不签生产Release、不安装或使用手机。只在本任务副本生成隔离测试材料。
5. 清单/候选准备后确认具体设备、占用时段、安装包名/签名及数据影响。获窗口再验证登录、选择身份、发帖、列表/详情、我的、删除、退出重进、注销清理；原生business7、进程/重启恢复与实际插件执行。人工指纹/系统动作单独提示，凭据不进入聊天或Git。
6. 更新交接/模块台账/progress，保留历史版本，核对最终代码覆盖；正常提交/推送本分支，不强推、不合main、不发布Release或部署生产。

当前C盘约3.5GiB、E盘约167GiB；WSL磁盘在E盘。工具复制/缓存/临时制品均在E盘或该WSL。本轮只用明确归属一次性数据库，不使用认证数据库、账号、密钥、签名、恢复材料或变化中工作树，不停其他服务，不改全局PATH/代理/证书/系统配置。

范围排除：第二实体Android NI-X01/X02、iOS、生产部署/灾备/独立审计；未实现的评论/私信/图片/搜索/推送仍不实现。单台Android设备未跑前标NOT_RUN，不把标准构建或主机替身计设备PASS。

当前执行：步骤1至4完成，七stage及受影响认证主机检查和原生构建PASS；步骤5用户明确延期，所有设备用例NOT_RUN，无ADB/设备操作。步骤6保存并普通推送整合结果，清理本任务独占SDK/缓存/APK/合成材料，保留脱敏交接与证据。最终范围、实际命令和失败修复见[联合报告](community-auth-integration-report-20261013.md)、[机器记录](community-auth-integration-20261013.json)。未来设备验收需重新核对工具容量、独占缓存、新环境/签名/CA及明确设备窗口；原APK/私钥不跨任务复用。