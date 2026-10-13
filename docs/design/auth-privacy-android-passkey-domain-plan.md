# Android Passkey 免费测试 RP 方案

日期：2026-10-05。用户没有现成 RP 域名，要求准备免费方案；iOS 本轮排除。

建议使用 GitHub Pages 的用户站点 `https://zewbby.github.io`，对应独立公共仓库 `zewbby.github.io`。GitHub Free 支持公共仓库 Pages；用户站点的文件位于域名根目录，能满足必须在 `/.well-known/assetlinks.json` 部署的要求。一般项目站点的 `/仓库名/` 路径不能代替这个固定路径。依据：[GitHub Pages 类型与免费范围](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)、[静态站点及 .nojekyll](https://docs.github.com/en/pages/getting-started-with-github-pages/creating-a-github-pages-site)。本方案是测试 RP，后续正式域／发布签名另行配置。

已从实际安装来源 APK 读取 Android Debug 签名证书 SHA256：`FD:26:B2:76:CB:17:0B:F0:84:A9:32:D3:B3:91:9B:D3:AA:44:87:43:95:80:99:68:BD:D7:4D:DA:B8:73:89:DC`。package 为 `org.hnuhole.hnuhole_mobile`。只授予 `delegate_permission/common.get_login_creds`，不接管全部网页链接。

已发布关联文件：[公开 assetlinks](https://zewbby.github.io/.well-known/assetlinks.json)、[源码副本](../../infra/passkey/android-debug-test-site/.well-known/assetlinks.json)、[debug XML](../../apps/mobile/android/app/src/debug/res/values/passkey_associations.xml)。仅 assetlinks、`.nojekyll`、说明页与 robots 四文件公开，不含应用源码或运行秘密。

用户已明确授权创建并发布，现有 Git 凭据归属核验为 zewbby；无需浏览器登录。独立[公共仓库](https://github.com/zewbby/zewbby.github.io)的 Pages 发布提交 `1ff129f5a479c1bbd8cde59a4f0d27e9732fb9a4` 构建成功；HTTPS 正常证书校验、200 JSON、无重定向、内容一致与 Google Digital Asset Links linked=true 均已实际核验。见[证据](../../services/api/authlab/android-passkey-domain-verification.json)。关联就绪不代表设备 ceremony 已通过。

Android 关联只进入本轮 debug 测试变体；C 在明确归属的开发配置中应用固定 RP／Android origin。真实 API 仍通过 USB loopback 私有 CA HTTPS 连接，不因关联静态文件部署而公开 C/V、数据库或 Mailpit。任何发布变体配置与生产部署需要另行完成。
