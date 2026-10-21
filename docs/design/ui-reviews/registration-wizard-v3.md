# 三步注册交互稿 v3

AUTH-REGISTER-UI-02；2026-10-21；DESIGN_APPROVED。用户确认：“可以，就这样”。此前[v2](registration-wizard-v2.md)与图片保留。

恢复码框内右上角增加复制图标，点击复制完整26字符占位码，成功显示勾及复制反馈，失败提示手动保存。移除“暂不设置”重复动作；确认完整恢复码后，通过右下角箭头完成。通行密钥仍可选，恢复码必需。

[三步总览](../auth-flow-final/registration-v3/registration-three-steps.png)、[恢复码页](../auth-flow-final/registration-v3/03-security.png)、[确认后页](../auth-flow-final/registration-v3/05-passkey.png)、[复制反馈](../auth-flow-final/registration-v3/06-copied.png)、[320px深色](../auth-flow-final/registration-v3/07-security-narrow-dark.png)、[核对记录](../auth-flow-final/registration-v3/verification.json)。已实际目视核对。375px浅色、320px深色布局无横向溢出；复制按钮在框内；现代剪贴板成功、兼容复制成功、复制失败反馈均PASS。QA拦截剪贴板写入，没有改写用户系统剪贴板；页面仅在明确点击时复制，不读取剪贴板。错误恢复码不能完成，正确完整确认后允许不配置Passkey完成演示。

Edge完整三步流程、源码语法、源稿与iframe一致、原sandbox/CSP均PASS，页面错误0、外部请求0。只保存设计与本地原型；真实邮件、设备Passkey、数据库、Flutter、APK NOT_RUN。未提交、推送、合并或更新Sites。
