# 三步注册 UI 交互稿

任务 AUTH-REGISTER-UI-02；2026-10-21；分支 feat/registration-wizard-ui，从最新 main 4d76f2c 建立，不带codex。用户明确指定原index.html，并要求先展示效果图。

本轮更新该文件及其可编辑source，交付顶部10px蓝色SVG进度、校邮验证／用户名密码／账号安全三部分。第3部分保留恢复码一次展示与完整确认，随后可选Passkey；只演示界面，不修改后端、Flutter、线上站点或APK。

此前v2：真实Edge渲染总览与5状态已交付候选，源码语法／完整三步路径／恢复码确认通过，零页面错误、零外部请求；容器原sandbox和CSP保留。设备及真实认证NOT_RUN。见[评审](../design/ui-reviews/registration-wizard-v2.md)、[证据](../design/auth-flow-final/registration-v2/verification.json)。用户未确认本版，不宣称整流程定稿；未提交／推送／合并。

2026-10-21 v3：用户确认“可以，就这样”，本地注册设计DESIGN_APPROVED。恢复码框内增加复制图标，移除“暂不设置”，恢复码完整确认后可直接通过箭头完成；通行密钥可选。375px浅色／320px深色和三种复制路径PASS；见[v3评审](../design/ui-reviews/registration-wizard-v3.md)与[证据](../design/auth-flow-final/registration-v3/verification.json)。此前v2待反馈状态已由本次确认更新；产品实现、线上发布、APK未执行。
