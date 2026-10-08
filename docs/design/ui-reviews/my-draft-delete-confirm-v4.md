# F1-13 草稿删除确认 v4：两行弹窗

日期：2026-10-08。状态：`DRAFT / AWAITING_USER_REVIEW`。

用户指定：“框内一共两行，第一行，确认删除这篇草稿？第二行 左边取消 右边确认”。当前[两行居中弹窗v4](../ui-drafts/my-draft-delete-confirm-v4.png)按原文呈现，第一行为单行问题，第二行左“取消”、右亮朱红“确认”。删除具体标题和无法恢复说明不再放入弹窗；该指令覆盖原额外文案要求，删除仍不可恢复。原草稿标题保留在背景卡片，其他页面不改。

使用内置imagegen编辑[居中弹窗v3](../ui-drafts/my-draft-delete-confirm-v3.png)，v1—v3保留历史。已实际查看：弹窗仅两行，问题未换行、按钮顺序和文案正确，红色确认清楚可辨，没有第三行或额外确认步骤。背景图像细节可能有生成漂移，实际组件须复用本人混排页，不将本图当真实交互截图。

取消、返回或关闭保留草稿；点击确认仅确认当前选定草稿的删除，实际成功后移除，失败保留并反馈，不能误删其他项。当前仅图稿与文档，业务／触控／读屏／持久化／设备均NOT_RUN，不登记PASS。总计仍10正式＋3我的候选＋9未出图；v4尚未定稿。

## 内置imagegen提示词

```text
Use case: ui-mockup precise modal edit. Input is the EDIT TARGET, 我的 page with centered white 删除草稿 dialog. User gives exact simplification: dialog contains ONLY TWO ROWS total. Replace ONLY the dialog contents and shrink its height appropriately, keeping same centered position, white material, rounded corners, clear edge and subtle anchoring shadow, strong readable substantial Chinese typography. ROW 1: a SINGLE centered line of bold near-black text EXACTLY “确认删除这篇草稿？” — must fit on ONE line, do not wrap, choose appropriate font size inside same approximately76% screen width. ROW 2: a horizontal row of TWO equally sized buttons, LEFT “取消” white with slate border/dark semibold text; RIGHT “确认” bright vivid vermilion red #F04438 with crisp WHITE semibold text. Labels must be exactly two characters each. Clear compact padding around both rows; dialog height roughly130logicalpx, no enormous empty space. This is all the text INSIDE dialog: “确认删除这篇草稿？” then “取消” “确认”. REMOVE the specific draft title “周末一起去图书馆” FROM DIALOG ONLY, REMOVE “删除后无法恢复。” FROM DIALOG, REMOVE old “删除草稿” button label. No third row, subtitle, warning, icon, close X, handle or extra action. Preserve ALL background page details unchanged, including draft title which MUST remain on the BACKGROUND CARD, profile 松间, header/tabs, all card photos/nicknames/statuses/hearts, dimming scrim, bottom navy plus and nav,9:41 and homegesture. One approx853×1844 portrait app screenshot, no device frame/watermark/labels. Overall framework WHITE, bright color only for confirmation destructive button, no gradients or decorative textures.
```
