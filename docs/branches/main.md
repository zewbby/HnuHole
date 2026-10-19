# main

汇集已经合并的项目实现与文档。

核对日期：2026-10-19。

## 进度

主线包含协作规范、帖子图片前后端、Android S18原约定范围、PR #9的B5材料与闭号/图片擦除修复、PR #14的文字帖证据归档、PR #13的社区中文无障碍和图片/认证联合回归，以及PR #18的帖子举报审核与最小系统通知阶段1。

[PR #16](https://github.com/zewbby/HnuHole/pull/16) 已合入测试签名Android候选、隔离预发布配置与生命周期、正式迁移/精确权限核验、实际备份到双新实例恢复和应用回滚路径，并归档vivo S18最小文字/单PNG限定实测。合并提交 `32cb87b73e2feb518e1c5ec75ea11bb4d3414df1` 与已测最终head `a6f8f60` 完整文件树一致，八项最新检查全SUCCESS；见[合并回执](../release/android-prerelease-main-merge-20261019.json)。实现、验收和正式发布分别记录。

## 剩余事项

跨设备Passkey NI-X02按用户要求延期。8691/d80c手机debug包的11项限定结果不代证其他APK或完整原生安全；CI release默认.invalid，与手机包分开归档。iOS、正式签名、真实云、独立生产运营与完整App验收仍未完成，未正式发布；其余未验范围见[手机报告](../release/android-device-validation-20261019.md)。手机窗口已结束，不再ADB；后续开发从最新main新开需求分支。

## 详细记录

- [主线进度](../design/progress.md)
- [Android候选与隔离预发布交付](ci-android-prerelease.md)
- [举报审核阶段1](feat-report-moderation.md)
- [社区PR #13交付与验证范围](community-flutter-pages.md)
- [B5主线增量交付与验证范围](fix-b5-main-integration.md)
