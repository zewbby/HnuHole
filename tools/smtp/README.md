# QQ SMTP 零预算测试配置

本分支新增支持，仅用于开发环境小规模测试。本机开发C/V已加载并验证真实投递与已有账号邮箱登录；完整状态见 [邮箱认证交接](../../docs/branches/feat-email-auth-flow.md)，不代表生产发布。

在 Windows PowerShell 运行：

```powershell
wsl -u hnuhole -- python3 /mnt/e/Hnuhole-env/source/HnuHole-smtp-real-delivery/tools/smtp/configure_qq.py
```

依次输入完整 QQ 发件地址和 SMTP 授权码。第二项隐藏输入，输入后回车。不要提供 QQ 账号密码，不要将授权码发到聊天、命令行参数、Git 或 APK。

默认文件位于 Linux 用户的 `~/.config/hnuhole/smtp-test/`：目录权限700，生成的配置及独立授权码文件权限600。脚本打印配置 JSON 的路径；JSON 只含授权码文件路径。脚本不会联网、发送邮件或重启服务。

QQ 设置固定为 `smtpMode=tls`、`smtpAddress=smtp.qq.com:465`，发件地址与认证用户名一致。模板见 [qq-smtp.example.json](qq-smtp.example.json)。旧版本验证服务不认识新增字段，不能提前把它们写进正在使用的配置。

升级验证服务后，将生成片段的五项合并到原 V 配置，保留原 Gate、数据库、密钥、证书、端口等字段。可显式使用 `--verifier-config <现有开发V配置路径>` 生成私有备份并原子替换；该选项不重启服务，应先核对二进制版本与运行环境。SMTP 账号只放在 V。

升级时同时升级读取同一配置的authdev证据维护工具；旧工具会拒绝新增字段并停止维护，导致Gate按设计冻结。应使用新版正常签名恢复并维护，不能绕过Gate。本机测试已完成注册收信与既有账号登录。SMTP 接受投递不等于校园收件箱收到邮件；不对未知结果自动重发。

检查：`python3 -B -m unittest discover -s tools/smtp/tests -v`。Go SMTP 测试使用本地 TLS 服务和假凭据，不连接 QQ。
