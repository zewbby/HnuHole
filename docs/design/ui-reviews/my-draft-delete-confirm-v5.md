# F1-13 草稿删除确认 v5：问题行缩小／宋体

日期：2026-10-08。状态：`DRAFT / AWAITING_USER_REVIEW`。

用户最终限定：“确认删除这篇草稿？ 这几个字有点太大了，小一点点，用宋体”。按该指令仅修正弹窗问题行，保留两行结构、问题原文、左取消／右确认、原按钮字体及亮朱红色。[当前宋体版v5](../ui-drafts/my-draft-delete-confirm-v5.png)由内置imagegen编辑[v4](../ui-drafts/my-draft-delete-confirm-v4.png)，853×1844像素；旧版全部保留。

已实际查看：问题行为清晰宋体风格衬线字形，字号相较v4收小且仍单行；两个按钮仍用原无衬线字，布局与动作不变，没有额外提示。字号目标约17逻辑单位，比原图约减18%，属于生成目标而非精确测量。本机确认存在`C:/Windows/Fonts/simsun.ttc`，但生成图不能证明实际嵌入了该字体；正式Flutter渲染需核对字体来源、字形和动态字号，不复制系统字体文件冒充可用移动端资产。此字体要求仅适用于当前弹窗的问题行，不自动改成全App字体。

行为沿用PERSONAL-DRAFT-DELETE-01，取消保留，明确确认且实际成功才移除选定草稿。当前仅图稿，源码及删除／返回、字体真实渲染、触控、读屏、对比度与设备均NOT_RUN。总进度10 FINAL＋3我的候选＋9未画，本页v5待评审。

## 内置imagegen提示词

```text
Use case: ui-mockup precise typography edit. The attached image is EDIT TARGET, two-row centered draft deletion popup. Change ONLY the question-heading text “确认删除这篇草稿？” in the WHITE DIALOG. Make that ONE text line slightly smaller: reduce its current visible font size by about18%, from roughly20logicalpx to17logicalpx. Change its typeface to Chinese SONGTI / SimSun 宋体, a clear printed Chinese serif with characteristic horizontal thin strokes, thicker vertical strokes and small triangular serifs, moderate NORMAL/MEDIUM weight, not a calligraphic brush, not sans-serif/黑体, not huge heavy bold. Keep it solid black, centered, SINGLE LINE, exactly same wording and punctuation. This heading must visually have more breathing room than reference and look like regular refined 宋体. Do NOT shrink the dialog or move its position. Preserve ALL other elements and their typography EXACTLY: left button “取消” remains existing dark sans-serif, RIGHT button “确认” remains white sans-serif on bright vermilion RED; same sizes, positions, widths, borders, corner radii and button font sizes. Retain exactly two rows in dialog, no subtitles, draft name or warnings. Entire dimmed My page background, photos, nicknames, titles, tabs, bottom navy plus, status9:41 and homegesture unchanged. White opaque dialog, crisp edge and restrained short shadow, same canvas approx853×1844. No extra labels/frame/watermark, no dark theme or decoration. ONLY heading text size and typeface change.
```
