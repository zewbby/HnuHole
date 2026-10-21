# 三步注册流程与恢复码复制

任务 AUTH-REGISTER-UI-02 / AUTH-REGISTER-IMPLEMENT-03；2026-10-21；分支 `feat/registration-wizard-ui`，按用户要求不带codex。原设计基线4d76f2c，实施前整合最新main `a746fa8`，保留#37外观和#40登录首页导航。用户已确认v3：“可以，就这样”，随后授权“开始改并且更新提交合并”。

[PR #42](https://github.com/zewbby/HnuHole/pull/42)交付获确认HTML源稿、三步效果图和真实Flutter实现。已合并main `09498b2bc0987a8865c768922e98607cef6fef89`，与检查通过的head `e1d2b0a` 完整文件树一致。五项最终CI全部SUCCESS；见[合并回执](../design/validation/registration-wizard-20261021/main-merge.json)。未正式发布。

注册第一步校园邮箱＋验证码、第二行右侧取码；第二步用户名密码；第三步一次展示恢复码、框内复制、隐藏后完整确认。10px蓝色矢量进度标识三步。只有用户明确点击才复制原码；失败给出手动保存提示，不读剪贴板、不将原码或密码加入外观偏好。去掉“暂不设置”，开户后保留可选Passkey入口，通过右下角完成箭头继续既有首页导航。

通行密钥入口打开既有真实凭据管理页面，由现有密码重验／系统凭据／原结果核对处理，不显示虚假的已设置状态。未新增Passkey或邮箱登录协议；邮箱验证码登录仍待接入。注册邮箱已知收码冷却结束后允许更正，未知／确认待核对时保留原操作；新地址不能确认旧申请。恢复、注销、会话和Gate边界沿用现有实现。

验证：分析0；全量668项；真实字体auth_screen20项；375px浅色、320px深色1.6倍字；剪贴板成功／失败、一次显示、完整确认、完成回调与可选设置导航。独立agent只读审查首轮发现邮箱更正和集成选择器问题，均修复；最终无阻断（非GitHub成员批准）。现有真实设备集成入口已迁移到新控件，并补按钮本体启用等待，实际设备／邮件／Passkey／iOS／生产 NOT_RUN。

[实现与截图证据](../design/validation/registration-wizard-20261021/verification.json)、[设计v3](../design/ui-reviews/registration-wizard-v3.md)。Android ARM64 debug本地构建通过；最终head的GitHub CI另以PR核对；合并后交付主线同签主体APK，包及机器私有材料不进Git。既有独立邮箱登录需求报告工作树保留，不混入本PR。
