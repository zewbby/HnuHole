# F1-13 删除草稿确认 v2：醒目删除色

日期：2026-10-08。状态：`DRAFT / AWAITING_USER_REVIEW`。

用户看过v1后要求“这个删除草稿的颜色要用亮的，醒目的颜色”。使用内置imagegen只修正删除主按钮为亮朱红色，保留白字、布局、取消、警示、背景列表和其他蓝色元素。当前[删除确认v2](../ui-drafts/my-draft-delete-confirm-v2.png)为待评审候选，[v1](../ui-drafts/my-draft-delete-confirm-v1.png)保留为暗砖红历史。已实际查看输出：主按钮明显提亮为红色，中文和警示均保留，取消按钮描边及背景身份／状态未改。生成颜色未逐像素测量，目标约`#F04438`，不冒称对比度或平台通过。

本次只改变删除动作色，不扩为全局强调色，不重新定稿我的其他两页。删除仍待本人确认，取消保留；行为、触控、读屏、存储删除及设备均NOT_RUN。身份三页正式归档，本批我的三页待评审；总进度10 FINAL＋3 DRAFT＋9未出图。

## 内置imagegen提示词

```text
Use case: ui-mockup precise color edit. Input screenshot is the EDIT TARGET: 我的 / 删除这篇草稿 bottom confirmation sheet. Change ONLY the destructive primary button background labeled “删除草稿”: replace its muted dark brown/brick fill with a vivid CLEAR BRIGHT VERMILION RED #F04438 (or close), flat solid high visibility, crisp WHITE strong semibold label “删除草稿” unchanged. User specifically requests a bright striking color for this delete action. Make it visibly red, not dusty brown/burgundy, not dark, not pastel, no glow or gradient. Keep exact button shape, size, placement and corner radius. Preserve all other pixels/elements as closely as possible: white sheet, heading “删除这篇草稿？”, draft title “周末一起去图书馆”, warning “删除后无法恢复。”, outlined cancel “取消”, close X, handle, shadow, underlying dimmed mixed list and its photos/avatars/titles/statuses, header and tabs, safearea, entire composition. Do NOT recolor the underlying central plus, blue draft badge or selected tab underline. Do NOT add actions or change wording. ONE same portrait full-screen screenshot approx853×1844, no frame, annotations or watermark. White app framework with substantial typography unchanged.
```
