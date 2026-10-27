# 阶段7 PR与远端CI交付

2026-10-26，COMMENT-SNAPSHOT-REDIS-01。已按用户对具体远端、分支和操作的授权完成提交、推送，创建并附加[PR #80](https://github.com/zewbby/HnuHole/pull/80)。任务分支为codex/feat/comment-snapshot-redis，目标main；未合并或发布。

## 被测版本与结果

功能提交21f52f9e70f7b5526f271019e283b178cf8ee8c5；Gate夹具修复7c115ebd8de61fab1d93033c22b690b9f2bc25c4；导航测试修复41eaf5e4334ca2fe77503588e18d98c83f51ec27。后者为本记录的完整CI被测head，15个workflow均SUCCESS，26项实际job检查SUCCESS，另1项actual-process-acceptance因仅workflow_dispatch按设计SKIP。逐项链接与结果见[机器回执](stage-7-remote-ci-evidence.json)。未运行性能/30分钟整轮，本轮CI不关闭性能待验项。

本回执追加后若只有文档变更，最终head及对应CI以[PR实时Checks](https://github.com/zewbby/HnuHole/pull/80/checks)和D盘最终交付证据核对，避免文档自引用SHA。agent审查不等于GitHub成员批准；独立成员review/批准仍按仓库要求处理。

## 实际失败与最小修复

1. 初轮head21f52f9：25实际job通过、Gate失败、性能job按设计跳过。旧Gate入口只有单集群PG，缺少Redis/固定Goose/图片fixture；另有严格C schema清单未包含既有迁移0025的头像资产表。修复复用现有归属明确的双集群夹具，完整执行go test -race ./...和vet；清理C/V两域测试间的Goose跟踪表，对齐精确schema清单并保留列/跨域/特权断言。没有缩小测试范围。
2. head7c115eb：完整Gate回归通过；图片workflow的Flutter导航widget因真实解码未完便关闭，报Image stream disposed，984 PASS/1 FAIL/3既有SKIP。仅修改原导航测试，在关闭/撤销前等待ViewerLoadStatus.ready及decodedFrames>0，保留导航、删除与锚点断言；没有修改图片产品生命周期或抑制异常。
3. head41eaf5e：全部适用job通过，两项失败闭环；原失败日志摘录、job链接与版本保留在D盘，未重标或以重试覆盖。

本机只针对新CI修复做YAML/接线、shell语法、gofmt/Dart格式、明确暂存差异及仓库协作规则检查；完整产品结果取自实际远端CI，没有重复本机SQL/Redis、真机、实际30分钟或性能验收。

## 整合与保全

先备份160个任务文件、原diff与索引，再将任务分支从c051981快进至已核实main c17a667。六处共享文档/台账保留双方记录：main143条、本任务6条，共149条；其他148条记录逐项保持，原本任务5条历史不改。主线35个不重叠变更文件完整保留。阶段7CI修复仅改workflow、测试夹具、导航测试和当前工作项记录，功能产品逻辑保持原审查版本。

## 遗留条件

默认运行、缺省及模板保持postgres/readPostgres=true/readRedis=false。最终steady replyExpanded的PG140.6527ms、Redis151.3024ms、P95 +7.5716285574%原FAIL保留；兼容续页1000对+0.0622506666%PASS仅关闭对应缺口。阶段5不是全PASS，P5-D1仍0/60、NOT_EVALUATED；本机诊断和性能环境建设停止。

可靠环境性能项处理并取得显式启用授权前，不执行Redis双读/新建/停PG读取。旧功能、容量、故障、30分钟和真我限定证据按原版本与范围复用，不提升为完整生产UI/native vault、iOS或生产验收。合并、部署、Redis启用均未授权。
