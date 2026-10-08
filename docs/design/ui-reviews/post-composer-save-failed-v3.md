# F1-07 草稿保存失败 v3：加强视觉分量

日期：2026-10-08。状态：`FINAL / USER_APPROVED`。

正式图：[发帖-草稿保存失败](../../../UI产品图/发帖-草稿保存失败.png)，853×1844；原[厚重版v3](../ui-drafts/post-composer-save-failed-v3.png)及v1／v2完整保留。使用内置imagegen基于[居中弹框v2](../ui-drafts/post-composer-save-failed-v2.png)编辑。用户先认可居中弹框及左放弃／右重试布局，要求加强质感；看过v3后明确“用厚重的版本定稿，告诉我现在画图的进度情况”。据此确认本页布局和厚重版视觉，身份三页未自动定稿，不扩展为最终全局主题。

保留布局、白色框架、提示文字、左放弃／右重试。加强黑色标题和按钮字重、说明文字对比、左按钮边界及弹框短阴影；右按钮仍使用偏暗偏灰蓝。已实际查看：弹框有明确表面边界，正文可读，左右两动作和提示不变，无新增操作或装饰。生成图有细微明暗及纹理，不宣称像素已满足纯色目标；实现须以真实UI组件校准颜色、素材和已定稿编辑页位置。

行为沿用[两按钮弹框记录](post-composer-save-failed-v2.md)及[POST-DRAFT-SAVE-FAIL-01](../modules/post-composer.md)。本轮只做图稿和规则／进度同步，业务源码未实现，保存／放弃／返回、读屏、真实触控、对比度和设备验证均NOT_RUN。当前7 FINAL＋3身份候选＋12未出图，共22页；通道列表3页及编辑与确认4页全部定稿，下一步先评审已出图身份三态，再继续“我的”3页。

## 内置imagegen提示词

```text
Use case: ui-mockup precise visual polish. The attached image is the EDIT TARGET, an approved centered-dialog mobile screen. The user approves its composition and asks for a more substantial, grounded visual finish, not airy or faint. KEEP EXACTLY the same full-screen layout, element positions, size, entire Chinese copy, two-action centered-dialog structure, left “放弃” and right “重试”. Preserve the editor background content and white app framework, status bar 9:41, “写帖子” / “搭子” header, title 周末一起去图书馆, body, images section, gesture bar. No new elements, actions, copy or decoration.
Improve ONLY visual weight of the foreground dialog: pure opaque white dialog surface with a crisp restrained cool-gray edge and natural short soft shadow that anchors the dialog. No floating ambient glow. Heading “草稿保存失败” in solid near-black #101820 with slightly stronger bold Chinese system weight, preserve its size and placement. Explanatory two lines “内容还在当前页面。” and “放弃将丢失未保存的修改。” in darker charcoal-slate #354250 so they have decisive readable contrast, preserve size and line breaks. Left button remains WHITE and outlined, strengthen its border to clear slate gray #82909F (about1.5 logical px), stronger semibold dark text “放弃”. Right button becomes a slightly deeper subdued navy #263B4E, a solid matte fill without gradients/texture or washed-out highlights, crisp WHITE semibold text “重试”; keep exact existing button shapes, equal widths, heights and positions. Keep corners same, no 3D bevel or gloss, no heavy cartoon drop shadow, no pure black primary button, no bright saturated blue. Background neutral modal scrim remains unchanged; underlying page is WHITE, never dark theme. Aim for sober polished native app contrast and visual substance. Deliver one 853×1844 portrait screenshot approximately matching input, no device frame or labels.
```
