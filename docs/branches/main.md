# main

汇集已经合并的项目实现与文档。

核对日期：2026-10-20。

## 进度

主线包含协作规范、帖子图片前后端、Android S18原约定范围、PR #9的B5材料与闭号/图片擦除修复、PR #14的文字帖证据归档、PR #13的社区中文无障碍和图片/认证联合回归，以及PR #18的帖子举报审核与最小系统通知阶段1。

[PR #16](https://github.com/zewbby/HnuHole/pull/16) 已合入测试签名Android候选、隔离预发布配置与生命周期、正式迁移/精确权限核验、实际备份到双新实例恢复和应用回滚路径，并归档vivo S18最小文字/单PNG限定实测。合并提交 `32cb87b73e2feb518e1c5ec75ea11bb4d3414df1` 与已测最终head `a6f8f60` 完整文件树一致，八项最新检查全SUCCESS；见[合并回执](../release/android-prerelease-main-merge-20261019.json)。实现、验收和正式发布分别记录。

[PR #17](https://github.com/zewbby/HnuHole/pull/17)（`3e0cc02`）与[PR #19](https://github.com/zewbby/HnuHole/pull/19)（`2da7cdf`）已依次合入评论核心及完整业务接通：评论/具体回复、固定身份、点赞排序与定位、本人删除、单图、原生任务恢复及真实失败通知。正式迁移链0001..0017，Android限定验收与独立审查通过；评论开发任务关闭，未发布。合并文件树与已实测候选一致，详见[合并回执](../design/comments-main-merge-20261019.json)与[任务详情](feat-comments-backend-text.md)。

[PR #25](https://github.com/zewbby/HnuHole/pull/25) 已修复C/V Gate请求取消误冻结，合并提交 `54a6768fe607c37930959fab23c4876bb4ab531d`；真实SQL/TLS定向回归、受影响宿主CI与独立审查通过，真实故障仍保持冻结。仅交付服务端修复，新建测试资源已收尾；原Android候选及验收材料保持原SHA，未恢复旧环境、未部署或发布。见[任务](fix-gate-cancellation-freeze.md)。

## 剩余事项

[PR #27](https://github.com/zewbby/HnuHole/pull/27) 的真实浏览去重／时间游标／账号屏蔽后端（`f1752e1`），以及[PR #28](https://github.com/zewbby/HnuHole/pull/28) 的新版列表与自适应图片接线（`f3454d1`）已合入main；原完整模块、设备和生产边界不提升，未部署。后续帖子互动接口见[独立任务](feat-feed-interactions.md)，不提前计作主线能力。

跨设备Passkey NI-X02按用户要求延期。8691/d80c手机debug包的11项限定结果不代证其他APK或完整原生安全；CI release默认.invalid，与手机包分开归档。iOS、正式签名、真实云、独立生产运营与完整App验收仍未完成，未正式发布；其余未验范围见[手机报告](../release/android-device-validation-20261019.md)。手机窗口已结束，不再ADB；后续开发从最新main新开需求分支。

## 详细记录

- [主线进度](../design/progress.md)
- [Android候选与隔离预发布交付](ci-android-prerelease.md)
- [举报审核阶段1](feat-report-moderation.md)
- [社区PR #13交付与验证范围](community-flutter-pages.md)
- [B5主线增量交付与验证范围](fix-b5-main-integration.md)
