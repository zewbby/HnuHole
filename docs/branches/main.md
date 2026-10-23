# main

2026-10-23：[身份头像 PR #63](https://github.com/zewbby/HnuHole/pull/63) 已合入 `45e3948`；精确送审 head 22 项 CI 全 PASS，开发 C25／V6 ready，真我日常2315同签保数据覆盖与既有会话私信入口限定通过，未生产发布。原生7项及未验边界按原版本保留，见[任务与交付回执](identity-avatar-onboarding.md)。

2026-10-23：[移动端 PR #57](https://github.com/zewbby/HnuHole/pull/57) Squash合入 `1686a063328bb919ee8a38b51e0ae70f4d6536e2`；最终head `f1e85fc` 的20项适用CI全PASS、独立只读审查无阻断。五项修正及动图原生保存／短时帧性能在真我限定验收，开发C已更新、真我保数据恢复日常2303；真实大图长列表／长时内存、iOS、生产发布未验。见[任务与证据](fix-mobile-navigation-refresh.md)。下方旧时点状态保留历史。

2026-10-23：[P2 PR #51](https://github.com/zewbby/HnuHole/pull/51) 正常 merge 为 `988bb42045f4140c46cf9e890d985a774d033e16`，[P3 PR #52](https://github.com/zewbby/HnuHole/pull/52) 正常 merge 为 `665291cdf312dec94fb11a75527524a821c5f008`；精确 head 的全部适用产品／协作 CI 与独立整合审查通过，认证反馈 #53 完整保留。限定验收与剩余 SKIP／NOT_RUN 见[聊天任务](feat-direct-message-chat-completion.md)、[治理任务](feat-direct-message-governance.md)和[设备补验 #55](test-direct-message-device-recovery.md)。未部署、未正式发布，生产开关仍关闭，不提升整模块验收结论；下方为历史快照。

**2026-10-22 AUTH-SESSION-RESUME-01／[PR #48](https://github.com/zewbby/HnuHole/pull/48)已合入main `d450cde`：**修复开发重启误用recover而废止会话；同代次resume前置校验，冻结/独立锚不一致仍拒绝。真实隔离16项、vivo2143原会话跨后端重启/冷启、独立复核及最终七类CI通过，本机维护工具已加载，APK无需重装。未做整机长关机或生产验收；详见[任务](fix-session-restore.md)。下方未合并均为历史状态。

汇集已经合并的项目实现与文档。

2026-10-22：#44 Telegram私信展示/四导航及#47隔离开发环境可靠文字收发已合入main。生产默认关闭，未部署/发布；限定验收、独立agent审查和CI见[合并回执](../design/direct-message-p1-main-merge-20261022.json)。

核对日期：2026-10-22。

PR #38 的登录注册设计定稿及 PR #39 的真实 App 接入已合入 main（`c23620f`）；欢迎、语言／明暗外观及原位登录切换已实现，邮箱登录明确待接入。五项 CI 与独立 agent 审查通过，主线同签测试 APK 交付中，未正式发布。见[任务与证据](feat-auth-entry-flow.md)。


[PR #42](https://github.com/zewbby/HnuHole/pull/42)已合入main `09498b2`：三步注册、恢复码点击复制、完整确认和可选Passkey管理入口。最终head五项CI成功、宿主668项及分析0；同签主体APK单独交付，真实设备／邮件和生产未验，不提升历史模块结论。见[任务与合并回执](feat-registration-wizard-ui.md)。

## 本轮认证交付

**2026-10-22 AUTH-EMAIL-LOGIN-01／[PR #45](https://github.com/zewbby/HnuHole/pull/45) 已合入main `6bb59fa`：**真实QQ校邮注册与已有账号验证码登录接通，vivo原账号／唯一会话／冷启动恢复限定PASS；最终head全部9类远端workflow成功，独立agent审查无阻断（非GitHub成员批准）。677项Flutter、分析0，正式SQL／HTTPS／恢复回滚通过；同签主体2143已生成，与合并main应用运行输入相同，USB断开待覆盖安装。开发包仍需电脑／WSL／USB在线，未正式发布。详见[交付记录](feat-email-auth-flow.md)。下方未合并／邮箱待接入均为旧时点记录。

## 进度

截至 `a1cb812`，#29 真实互动摘要、#30 条件写围栏、#32 隔离联调交付、#33 隔离错误契约及[#31 列表详情互动](https://github.com/zewbby/HnuHole/pull/31)均已合入；共享实际后端仍 c923fa5a／C21／V4，不将前端 main 重标为后端二进制。main2008 有 FA-D07 残留提示，独立修复送审与定点见[后续任务](fix-feed-read-errors.md)，未正式发布。

主线包含协作规范、帖子图片前后端、Android S18原约定范围、PR #9的B5材料与闭号/图片擦除修复、PR #14的文字帖证据归档、PR #13的社区中文无障碍和图片/认证联合回归，以及PR #18的帖子举报审核与最小系统通知阶段1。

[PR #16](https://github.com/zewbby/HnuHole/pull/16) 已合入测试签名Android候选、隔离预发布配置与生命周期、正式迁移/精确权限核验、实际备份到双新实例恢复和应用回滚路径，并归档vivo S18最小文字/单PNG限定实测。合并提交 `32cb87b73e2feb518e1c5ec75ea11bb4d3414df1` 与已测最终head `a6f8f60` 完整文件树一致，八项最新检查全SUCCESS；见[合并回执](../release/android-prerelease-main-merge-20261019.json)。实现、验收和正式发布分别记录。

[PR #17](https://github.com/zewbby/HnuHole/pull/17)（`3e0cc02`）与[PR #19](https://github.com/zewbby/HnuHole/pull/19)（`2da7cdf`）已依次合入评论核心及完整业务接通：评论/具体回复、固定身份、点赞排序与定位、本人删除、单图、原生任务恢复及真实失败通知。正式迁移链0001..0017，Android限定验收与独立审查通过；评论开发任务关闭，未发布。合并文件树与已实测候选一致，详见[合并回执](../design/comments-main-merge-20261019.json)与[任务详情](feat-comments-backend-text.md)。

[PR #25](https://github.com/zewbby/HnuHole/pull/25) 已修复C/V Gate请求取消误冻结，合并提交 `54a6768fe607c37930959fab23c4876bb4ab531d`；真实SQL/TLS定向回归、受影响宿主CI与独立审查通过，真实故障仍保持冻结。仅交付服务端修复，新建测试资源已收尾；原Android候选及验收材料保持原SHA，未恢复旧环境、未部署或发布。见[任务](fix-gate-cancellation-freeze.md)。

## 剩余事项

[PR #27](https://github.com/zewbby/HnuHole/pull/27) 的真实浏览去重／时间游标／账号屏蔽后端（`f1752e1`），以及[PR #28](https://github.com/zewbby/HnuHole/pull/28) 的新版列表与自适应图片接线（`f3454d1`）已合入main；原完整模块、设备和生产边界不提升，未部署。帖子互动接口及列表详情接线已由 #29／#31 合入，后续错误提示修复见上述独立任务；各旧证据仍按原范围。

跨设备Passkey NI-X02按用户要求延期。8691/d80c手机debug包的11项限定结果不代证其他APK或完整原生安全；CI release默认.invalid，与手机包分开归档。iOS、正式签名、真实云、独立生产运营与完整App验收仍未完成，未正式发布；其余未验范围见[手机报告](../release/android-device-validation-20261019.md)。上述旧手机窗口已结束；本轮设备由新版列表 Android 验收会话按当前任务独占，前端不操作设备。后续开发从最新main新开需求分支。

## 详细记录

- [主线进度](../design/progress.md)
- [Android候选与隔离预发布交付](ci-android-prerelease.md)
- [举报审核阶段1](feat-report-moderation.md)
- [社区PR #13交付与验证范围](community-flutter-pages.md)
- [B5主线增量交付与验证范围](fix-b5-main-integration.md)
