# F1-07 草稿保存失败 v2：居中弹框

日期：2026-10-08。状态：`LAYOUT_APPROVED / SUPERSEDED_BY_V3`。

用户要求：“草稿保存失败建议弄成弹框，左边是放弃，右边是重试”。看过本版后确认“可以”，同时要求“质感要做的好一点，厚重一点，不要轻飘飘的”。本版布局因此已通过，视觉继续修正，以[加强分量v3](post-composer-save-failed-v3.md)为当前候选；尚不计为整页FINAL。其余F1-08／09／10身份图不改。

当前图：[草稿保存失败v2](../ui-drafts/post-composer-save-failed-v2.png)。原[底部面板v1](../ui-drafts/post-composer-save-failed-v1.png)保留，仅为修正前历史，不作为当前候选。

采用白色居中弹框、黑色标题和暗灰蓝主动作，编辑内容作为模态背景保留。标题“草稿保存失败”；正文“内容还在当前页面。／放弃将丢失未保存的修改。”；仅一行两个动作，左侧描边“放弃”，右侧暗灰蓝“重试”。没有复制文字的第三按钮，没有底部拖拽条或额外确认。

行为：放弃表示放弃本次未保存修改并退出原编辑操作；重试重新尝试草稿保存，仍失败时保留编辑内容，保存成功后按原退出意图返回。系统返回或遮罩关闭若允许，应只回编辑，不能代选放弃。普通退出保存成功不新增确认。此为草稿本地保存失败，不是发布任务失败；此前复制文字入口要求按本次用户两按钮指令调整。

已实际查看输出：弹框居中，中文提示可读，左右按钮顺序正确；“重试”为主动作，未出现保存成功标记。灰暗背景是模态遮罩，不改变白色框架。生成图对编辑区图片位置与几何有轻微漂移，正式实现以已定稿编辑页组件为准，不能借此改动原编辑布局。

仅修改图稿与文档，Flutter代码未实现。保存故障、重试／放弃／系统返回行为、真实触控、读屏、动态字号、对比度与设备验收均NOT_RUN。当前仍6 FINAL＋4 DRAFT＋12未出图。

## 内置imagegen提示词

```text
Use case: ui-mockup precise revision. Edit the attached full-screen mobile writing screenshot. Keep the entire writing page composition exactly unchanged: 9:41 status, back arrow, centered “写帖子” / “搭子”, top right dark muted blue “下一步”, title 周末一起去图书馆, the two body paragraphs, 图片 0/9 and pale add image tile. Restore the bottom white editor area beneath the modal; there must be NO bottom sheet or “草稿已保存” success label.
Replace the existing large bottom sheet with ONE small centered white confirmation DIALOG over a restrained neutral black scrim covering the writing page. App framework underneath remains WHITE. Dialog centered in screen, around 80% screen width, compact height around 22% screen; rounded corners about16 logical px, no ornament or icon. Black centered bold heading exactly “草稿保存失败”. Below readable centered slate explanation in two lines exactly “内容还在当前页面。” and “放弃将丢失未保存的修改。” Then a SINGLE horizontal row of TWO equal-width buttons with good spacing and padding: LEFT “放弃” as a white outlined secondary button with dark slate text; RIGHT “重试” as a muted dark gray-blue #304458 filled primary button with WHITE text. Buttons are side by side, never stacked. NO third action, NO copy text button, NO close X, NO bottom sheet handle, NO extra confirmation. Top/back/title/body/photo sections remain as in input, naturally visible behind scrim. Bottom gesture bar retained. Same ~853×1844 portrait screen without device frame, watermark, presentation labels. Clear mature simplified Chinese typography, generous but compact dialog padding. Strong contrast, pure white surfaces, no bright blue, no full dark theme, no ornamental gradients.
```
