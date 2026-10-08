# F1-07—F1-10 出图提示词与版本

日期：2026-10-08。使用内置 imagegen；四页独立调用，身份失效页另作一次集中修正。原稿保留，未经用户确认均为 DRAFT。以下提示词供复现和审查，不是新的产品规则。

## save_failed

参考：`docs/design/ui-drafts/post-composer-edit-v1.png`。

```text
Use case: ui-mockup. Deliver ONE full-screen portrait mobile app screenshot, same approximate 852×1846 size/aspect and same quiet Chinese system sans typography as the reference. It is a real UI design PNG, no device frame, no presentation board, no annotations or watermarks. Preserve the pure WHITE application framework, black titles, slate secondary text, thin neutral separators, muted dark gray-blue #304458 primary controls with white labels. No bright blue, no dark mode, no trees/illustration decorations, no glass, no ornamental gradients. Natural small avatar photos are allowed. Keep the same 9:41 status bar and bottom home gesture safe area.
Input image is the EDIT TARGET: approved writing screen. Keep its header, exact title “周末一起去图书馆”, channel “搭子”, title/body/图片 sections and pale add-picture tile exactly in position. Keep the body text: “周六下午想去图书馆坐一会儿，看看书，也把拖了很久的作业写完。” then separate paragraph “不用一直聊天，各做各的就好。累了可以一起出去走走。” User attempted to leave and saving the DRAFT failed; remain on this editor, all content stays. Keyboard closed. Add a restrained 12% black modal scrim, and a WHITE bottom sheet with rounded top corners, approximately bottom 34% of screen. Sheet has centered subtle drag handle, top-right close X. Inside 24px logical horizontal padding: bold left aligned heading “草稿保存失败”; readable supporting line “内容还在当前页面，请重试保存或先复制文字。”; smaller secondary warning “放弃退出会丢失未保存的修改。” generous spacing. Three clear full-width stacked actions: primary muted dark gray-blue rounded rectangle “重试保存”; white outlined secondary rectangle “复制文字”; bottom plain charcoal text action “放弃并退出”. Equal logical tap heights around48. Bottom home gesture visible white. Remove the old “草稿已保存” footer behind the overlay so this screenshot cannot falsely claim success. Do not add publish actions, error code, banner or an extra confirmation dialog. Retain underlying editor unchanged, no navigation bottom bar. Show actual legible exact simplified Chinese, balanced tight sheet, strong hierarchy and ample white content above.
```

## identity_select

参考：`docs/design/ui-drafts/post-publish-confirm-v1.png`。

```text
Use case: ui-mockup. Deliver ONE full-screen portrait mobile app screenshot, same approximate 852×1846 size/aspect and same quiet Chinese system sans typography as the reference. It is a real UI design PNG, no device frame, no presentation board, no annotations or watermarks. Preserve the pure WHITE application framework, black titles, slate secondary text, thin neutral separators, muted dark gray-blue #304458 primary controls with white labels. No bright blue, no dark mode, no trees/illustration decorations, no glass, no ornamental gradients. Natural small avatar photos are allowed. Keep the same 9:41 status bar and bottom home gesture safe area.
Input image is the EDIT TARGET: approved 发布确认 screen. Preserve its top header 发布确认 / 搭子, title 周末一起去图书馆, tags label 标签 选填 with 2/3 and #自习 #周末 +, and original current identity 松间. User tapped current identity. Add the same restrained 12% black modal scrim and a WHITE bottom sheet from around y=1070 to bottom, keeping the context above visible. Rounded top corners and centered subtle handle. Heading left “选择发言身份”, close X right. Three clean list rows, no cards: circular nature avatar (misty mountain forest) + nickname “松间”; circular blue mountain avatar + “远山”; circular autumn-tree avatar + “北岸”. Each avatar around48 logical px, nickname bold moderate16, right radio selection circle. 松间 is selected dark gray-blue with white tick; other two empty neutral outlined circles. Thin row dividers, generous touch spacing, no identity numbers/account names/subtitle relations. Bottom separated footer “管理身份” with right chevron. No “确定”, no “发布” button in the sheet: tapping a row selects and closes, returning to confirmation without posting. Cover the underlying bottom 确认发布 action with the sheet. Same reference visual size, warm enough from nature avatars, completely WHITE UI.
```

## identity_empty

参考：`docs/design/ui-drafts/post-publish-confirm-v1.png`。

```text
Use case: ui-mockup. Deliver ONE full-screen portrait mobile app screenshot, same approximate 852×1846 size/aspect and same quiet Chinese system sans typography as the reference. It is a real UI design PNG, no device frame, no presentation board, no annotations or watermarks. Preserve the pure WHITE application framework, black titles, slate secondary text, thin neutral separators, muted dark gray-blue #304458 primary controls with white labels. No bright blue, no dark mode, no trees/illustration decorations, no glass, no ornamental gradients. Natural small avatar photos are allowed. Keep the same 9:41 status bar and bottom home gesture safe area.
Input image is the EDIT TARGET: approved 发布确认 screen. Preserve exact title 周末一起去图书馆, header 发布确认 / 搭子, tags 标签 选填 with 2/3 and #自习 #周末 +. Change underlying 发言身份 row to neutral outline user placeholder and “尚未设置身份”, supporting “设置后可发布”, and an arrow. The account has zero speaking identities. Underlying 确认发布 is disabled pale gray, never active blue. Add restrained 12% black modal scrim and WHITE bottom sheet approximately bottom 30% of screen, round top corners, centered subtle handle, close X top-right. Left heading “还没有发言身份”. Supporting text “先设置昵称和头像，再回来发布。” Below a smaller quiet assurance “已填写的内容会保留。” Big full width muted dark gray-blue button “设置身份”; below white outlined button “暂不设置”. Clean spacing and white bottom home gesture safe area. No decorative cartoon empty illustration, no forced login, no created identity, no auto-publish, no destructive actions, no editor preview. The sheet guides into identity setup; cancel simply returns to original confirmation preserving all fields. Exact Chinese, same mature sober whitespace and typography as the approved reference.
```

## identity_invalid

参考：`docs/design/ui-drafts/post-publish-confirm-v1.png`。

```text
Use case: ui-mockup. Deliver ONE full-screen portrait mobile app screenshot, same approximate 852×1846 size/aspect and same quiet Chinese system sans typography as the reference. It is a real UI design PNG, no device frame, no presentation board, no annotations or watermarks. Preserve the pure WHITE application framework, black titles, slate secondary text, thin neutral separators, muted dark gray-blue #304458 primary controls with white labels. No bright blue, no dark mode, no trees/illustration decorations, no glass, no ornamental gradients. Natural small avatar photos are allowed. Keep the same 9:41 status bar and bottom home gesture safe area.
Input image is the EDIT TARGET: approved 发布确认 screen. Preserve header 发布确认 / 搭子, exact title 周末一起去图书馆, tags 标签 选填 with 2/3 and #自习 #周末 +. Original choice 松间 became unavailable before task acceptance and must be explicitly reselected when there are two surviving identities. Change the underlying identity row to neutral outline person placeholder “请选择发言身份”. Underlying 确认发布 button disabled pale gray. Add restrained 12% black modal scrim and a WHITE bottom sheet approximately bottom 40% of screen, same corner/handle/close icon style as other identity panels. Heading “重新选择身份”. Immediately below show a calm readable slate notice “原选择的身份已失效，请重新选择。” with NO alarming giant red icon. Two surviving identity list rows: circular blue mountain avatar + “远山”; circular autumn-tree avatar + “北岸”. Both right radio circles are EMPTY outline gray: no preselected other identity. Thin divider between rows. Footer separated row “管理身份” right chevron. No additional confirm or publish button; tapping a valid row returns to confirmation, does not post. Do not include 松间 in selectable options, do not reveal account identifiers, do not say a published task can change identity, no success check. Completely WHITE surfaces, muted gray-blue accent only, exact Chinese and strong alignment.
```

## identity_invalid 集中修正 v2

参考：本批身份失效v1为目标，身份选择v1为头像依据。两个原文件均保留。

```text
Use case: ui-mockup precise revision. Input image1 is EDIT TARGET, the identity-invalid mobile screenshot. Input image2 is supporting avatar/component reference, the identity-selection screenshot. Preserve EVERY part of image1 exactly: white bottomsheet, top underlying confirmation backdrop, header, exact Chinese strings, two unselected radio circles, no selected identity, positions and all sizes. Change ONLY the circular avatar photos: replace 远山's circular avatar in image1 with the EXACT same blue jagged snowy mountain avatar used for 远山 (second row) in image2; replace 北岸's circular avatar in image1 with the EXACT same autumn mountain/lake landscape avatar used for 北岸 (third row) in image2. Do not use the 松间 avatar. Fixed identities must keep identical avatar imagery across states. Also match image1's close X and empty radio border neutral color to image2. Do not change names, text, spacing, panel height, selected state, dimmed white background, aspect or dark gray-blue palette. One portrait screen image only, no device frame or labels.
```
