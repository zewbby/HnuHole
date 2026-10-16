# F1-13 草稿删除确认 v5：问题行缩小／宋体

日期：2026-10-08。状态：`FINAL / USER_APPROVED`。

用户限定问题行字号小一点并用宋体，随后明确“可以，这种弹框的正文尽量都用宋体，取消 确认这种不需要”，并明确“定稿”。本页两行结构、宋体问题行、左取消／右亮朱红确认及原按钮字体正式确认。正式图为[我的-删除草稿确认](../../../UI产品图/我的-删除草稿确认.png)，853×1844像素；[原v5](../ui-drafts/my-draft-delete-confirm-v5.png)及v1—v4全部保留。原v5由内置imagegen编辑v4，正式归档未重新生成。

已实际查看：问题行为清晰宋体风格衬线字形，字号相较v4收小且仍单行；两个按钮仍用原无衬线字，布局与动作不变，没有额外提示。字号目标约17逻辑单位，比原图约减18%，属于生成目标而非精确测量。本机确认存在`C:/Windows/Fonts/simsun.ttc`，但生成图不能证明实际嵌入了该字体；正式Flutter渲染需核对字体来源、字形和动态字号，不复制系统字体文件冒充可用移动端资产。用户现将“这类弹框正文尽量宋体、按钮不需要”确认为后续设计规则，记录在[UI流程](../ui-quality-workflow.md)；不自动把全App字体改成宋体或重画其他正式图。

行为沿用PERSONAL-DRAFT-DELETE-01，取消保留，明确确认且实际成功才移除选定草稿。当前仅图稿，源码及删除／返回、字体真实渲染、触控、读屏、对比度与设备均NOT_RUN。总进度11 FINAL＋2我的候选＋9未画；本页正式定稿，混排与空态尚未确认，先收口现有两张候选后继续发布任务类。

## 内置imagegen提示词

```text
Use case: ui-mockup precise typography edit. The attached image is EDIT TARGET, two-row centered draft deletion popup. Change ONLY the question-heading text “确认删除这篇草稿？” in the WHITE DIALOG. Make that ONE text line slightly smaller: reduce its current visible font size by about18%, from roughly20logicalpx to17logicalpx. Change its typeface to Chinese SONGTI / SimSun 宋体, a clear printed Chinese serif with characteristic horizontal thin strokes, thicker vertical strokes and small triangular serifs, moderate NORMAL/MEDIUM weight, not a calligraphic brush, not sans-serif/黑体, not huge heavy bold. Keep it solid black, centered, SINGLE LINE, exactly same wording and punctuation. This heading must visually have more breathing room than reference and look like regular refined 宋体. Do NOT shrink the dialog or move its position. Preserve ALL other elements and their typography EXACTLY: left button “取消” remains existing dark sans-serif, RIGHT button “确认” remains white sans-serif on bright vermilion RED; same sizes, positions, widths, borders, corner radii and button font sizes. Retain exactly two rows in dialog, no subtitles, draft name or warnings. Entire dimmed My page background, photos, nicknames, titles, tabs, bottom navy plus, status9:41 and homegesture unchanged. White opaque dialog, crisp edge and restrained short shadow, same canvas approx853×1844. No extra labels/frame/watermark, no dark theme or decoration. ONLY heading text size and typeface change.
```
