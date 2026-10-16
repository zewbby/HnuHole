# F1-13 草稿删除确认 v3：居中弹窗

日期：2026-10-08。状态：`DRAFT / AWAITING_USER_REVIEW`。

后续修正：用户要求框内仅两行，问题“确认删除这篇草稿？”和左取消／右确认，当前以[两行弹窗v4](my-draft-delete-confirm-v4.md)为候选。本版额外标题／说明保留为历史，不计定稿。

用户要求“用弹窗吧，别用这种”，覆盖原底部确认面板样式。当前[居中弹窗v3](../ui-drafts/my-draft-delete-confirm-v3.png)以白色居中弹窗呈现，保留标题“删除这篇草稿？”、具体草稿“周末一起去图书馆”和警示“删除后无法恢复。”。动作同排：左侧描边“取消”，右侧亮朱红“删除草稿”。已实际查看：居中位置、文案、动作顺序和醒目删除色正确，无拖拽条、底部面板或提前成功提示；原草稿仍在背景中，其他蓝色元素未改。

使用内置imagegen，v2为编辑目标，本人混排v1用于恢复被旧面板遮挡的背景；[底部亮色v2](../ui-drafts/my-draft-delete-confirm-v2.png)与暗色v1保留为历史。取消或系统返回／遮罩关闭只能保留草稿，必须明确点击删除并实际成功后才移除项目。长按草稿→删除草稿入口不变，未添加额外确认层。本次只修正删除确认形态，不自动定稿新图或更改其他页、全局配色。

源码、保存删除、反馈和返回、对比度、触控、读屏、安全区与设备均NOT_RUN。静态候选不证明业务／平台通过。当前10 FINAL＋3我的候选＋9未出图。

## 内置imagegen提示词

```text
Use case: ui-mockup precise modal revision. Input1 is EDIT TARGET: 我的 page with bottom-sheet 删除草稿 confirmation and bright red delete button. Input2 is supporting BACKGROUND reference: same 我的 mixed list with NO modal. User requests a CENTERED POP-UP DIALOG instead of bottom sheet. Keep underlying full page content/layout/avatars/photos/card titles/tab state/nav unchanged using image2 to restore the portion formerly hidden under the bottom sheet. Put one neutral black modal scrim over the entire white page. Remove bottom sheet completely, no handle, no close X, no bottom action panel.
Add a compact WHITE CENTERED DIALOG in the middle of screen, approximately80% screen width, rounded16logicalpx corners, crisp subtle edge and short anchoring shadow, substantial native app finish matching approved save-failure dialog. Centered strong BLACK heading EXACTLY “删除这篇草稿？”. Below the exact target title “周末一起去图书馆” centered in semibold dark slate; below warning EXACTLY “删除后无法恢复。” in readable darker slate. Generous but compact padding, legible simplified Chinese, no illustration.
At bottom of dialog ONE HORIZONTAL ROW of TWO buttons, equal heights and balanced widths: LEFT white outlined secondary “取消” dark semibold text, RIGHT bright vivid vermilion RED #F04438 filled primary “删除草稿” with crisp WHITE semibold text. Both same corner radius8logicalpx and48logicalpx tap-height target. Side-by-side ONLY, never stacked. No extra confirmation, copy button, third action or success toast. The draft stays visibly in original background because not deleted yet. Restore original white bottom navigation and home gesture bar beneath scrim as reference2, inactive controls behind modal. Do NOT recolor underlying blue plus, draft badge, tab underline or failure status; only destructive button is bright red. White app framework, strong substantial text/controls not airy/faint; no dark theme, no glass/gradient/glow/3D decoration. One same portrait853×1844 screenshot approximately, no phone frame or labels.
```
