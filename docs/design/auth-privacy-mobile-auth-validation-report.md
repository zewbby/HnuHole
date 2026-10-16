# 移动端认证状态机交付与验证

日期：2026-09-30。分支：`codex/auth-privacy-handoff`。基线：`58db8a3f4cf07d1006eca6eedd9843733d542383`。本轮延续已授权实现，采用已收口的协议、C/V OpenAPI、恢复决定与账号契约，无新增 grilling。

## 已实现范围

Flutter 原有入口树接入认证状态机：V 独立校邮申请／确认、C bootstrap 持钥注册、单次展示恢复码并隐藏后完整重输、私有用户名密码登录、会话恢复与接替失效提示、活跃且剩余不超过七天的同令牌续期、恢复码受限重设、七天注销申请与原能力状态核对。重设成功不自动登录，不取消注销；缓冲期取消必须由用户明确输入密码主动登录。

`AuthStore` 把所有认证状态置于一个系统安全存储记录，串行读取／更新，严格验证 schema、部署 scope、独立安装ID、原请求键、能力编码、UTC日期、工作流状态与绑定；缓存为不可变对象。只有原生写入确认并读回相同值后才通知页面，未知写入使缓存失效，恢复时重新读。邮箱、OTP及V键不进入C请求；C私有用户名／密码／恢复材料不进入V。两个固定 HTTPS origin 独立，禁止重定向，传输响应有尺寸／时间／形状限制，错误不保存请求和服务端自由文本。

登出第一阶段持久保存对应 token 摘要的标记；第二阶段原子派生独立撤销秘密并删除同一 Bearer。启动优先转换标记；旧独立撤销能力在后台及前台恢复时重试，仅服务端204确认后删除，不按本地到期时间丢弃。旧任务不阻塞或删除后来新会话。401只清对应旧token；503／超时隐藏节点并保留安全令牌及树位置，重试重新向C确认。

OTP未知结果持久原键和等待时点，第40秒可核对原结果；只有明确NOT_SENT允许新申请。结果410需要用户明确结束过期核对，保留bootstrap槽位并受V预算限制。注册提交未知保留原意图／键，转用户主动密码登录，不重建旧提交或恢复令牌。密码重设先保存原意图／键，再POST；404、PENDING、410保留核对能力；已确认终态持久。注销先保存closureId、状态秘密／摘要及仅供原POST重试的旧Bearer并暂停社区访问；已知状态后删除旧Bearer。迟到响应不得清新token、改原截止或回退终态。

Android适配器使用不可导出的Keystore AES-GCM密钥、namespace AAD、`noBackupFilesDir`密文、AtomicFile替换及文件／目录同步后确认；已有记录缺钥时失败。iOS使用非同步、`AfterFirstUnlockThisDeviceOnly` Keychain，等待SecItem成功；另有非秘密且排除备份的同步安装标记，重装时先删除遗留Keychain状态，重新生成独立安装ID。无普通文件、Preferences或内存降级。增加Android/iOS宿主工程、禁Android应用备份，正式发布签名待配置。

## 验证证据

最终验证均成功（Flutter 3.47.5／Dart 3.13.4；Go 1.27.1；PostgreSQL 18.6）：

| 工作目录 | 命令 | 结果 |
| --- | --- | --- |
| apps/mobile | flutter pub get | 退出0，锁文件已固定 |
| apps/mobile | flutter analyze | 退出0，无诊断 |
| apps/mobile | flutter test --reporter expanded | 退出0，78项通过 |
| packages/auth_vault | flutter pub get --offline；flutter analyze --no-pub | 退出0，无诊断；使用已下载缓存 |
| packages/auth_vault | swiftc -frontend -parse ios/Classes/AuthVaultPlugin.swift | 退出0，仅语法解析，非iOS链接／运行 |
| apps/mobile | flutter build apk --debug --target-platform android-arm64 --no-pub | 未通过：初次Gradle下载EOF，bin分发重试到配置阶段，缺NDK 28.2.13676358；未生成APK |
| services/api | sh authlab/run-isolated.sh | 退出0，独立非超管C/V PostgreSQL＋race＋vet |
| services/api | go test -race -count=1 -p 1 ./... | 退出0，未配置数据库DSN的直接回归 |
| services/api | go vet ./... | 退出0 |
| 仓库根 | git diff --check | 退出0 |

78项分为固定协议向量6、真实TLS接口19、注册／重设／注销故障19、会话与持久存储20、页面组件9、平台通道与不可变记录5。隔离Go包用时：authprivacy 104.584秒、protocol 1.809秒、authprivacyhttp 8.719秒；直接race分别2.468／1.358／1.966秒。原生包首次在线解析受沙箱网络限制失败，随后使用已有依赖缓存离线解析与分析通过，没有修改系统工具链。

最终命令、版本、退出码、测试数与文件SHA-256见[机器记录](../../services/api/authlab/mobile-auth-verification.json)。Dart测试涵盖固定协议向量、真实本机TLS传输、工作流与并发故障、组件和MethodChannel边界；实际原生存储由故障可注入替身测试，不能当作真机耐久性证据。

UI沿用已有Material主题及输入控件，使用项目指定的ui-ux-pro-max／frontend-design和UI复审流程。375px、1.6字号注册与深色恢复码页面无overflow；深色容器文字对比度至少4.5。实际渲染截图：[注册](validation/mobile-auth/auth-registration-375px-160pct.png)、[恢复码](validation/mobile-auth/auth-recovery-code-dark-375px.png)。未新增截图上传／分析SDK／自动剪贴板路径。

## 交付边界与下一步

本轮完成核心移动认证状态机与客户端接线。服务端Safety Gate代码不改，其PostgreSQL／HTTPS故障套件已全量回归。客户端不裁决或解除Gate；每个授权仍由C权威端点决定。仅本地固定帧／公钥绑定检查不等于客户端对V的严格验签，权威验签仍由C执行。

Android SDK API36与Java25已存在，Android调试构建在缺NDK 28.2.13676358处失败；Gradle禁自动安装平台组件。完整Xcode缺失。尚未证明Android/iOS原生构建、Keychain／Keystore真机故障、杀进程／断电／磁盘满、备份恢复和重装。临时SDK不是系统安装。真实客户端→真实C/V数据库→业务目录的整链联调尚未做；原生产目录会话仍未连接新Gate，因此本轮不是生产授权接入验收。设备列表／恢复码轮换页面、原生Passkey桥接及固定RP/origin专项审阅、业务注销清理和通知、独立授时／外部锚点运营、人类独立安全审计继续待验收。

下一切片应先做Android/iOS构建和真机安全存储故障验证，并准备固定测试域名／证书的真实C/V整链联调，再完成设备与恢复凭据管理页面。生产接入须继续统一所有业务授权到Safety Gate；没有这些证据不得宣称整套认证可以上线。
