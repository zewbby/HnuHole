# 项目 UI 技能安装与来源

2026-10-08。项目分支 `codex/community-flutter-pages`，安装位置 `.agents/skills/`，不安装到用户全局技能目录。新技能在后续回合／重新打开本项目时由客户端发现；当前回合已直接读文件验证。其他工作树尚未合并这些文件，不改变原认证目录。

| 技能 | 来源与固定版本 | 用途 |
|---|---|---|
| frontend-design | 用户提供 `frontend-design.zip`；SHA256 `3BD0E6D6CC55264362BAB7F52E2074BBCA37B35E7D99385494EB6B8BDAAE5F92`；保留原SKILL.md与LICENSE.txt（Apache-2.0） | 视觉方向、排版、自我批评；本地包没有可验证上游提交，不能冒称来自某个GitHub版本 |
| ui-ux-pro-max | [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill/tree/477bcb28c9812b385cb51a4605ddf30d7b2266e2/.claude/skills/ui-ux-pro-max)，MIT | 可检索UX／Flutter建议；保留技能data、references、scripts |
| impeccable | [pbakaus/impeccable](https://github.com/pbakaus/impeccable/tree/778c8a7b71ccd5bfe3ca6ac68c15d9d872d0f87d/.agents/skills/impeccable)，Apache-2.0；附NOTICE.md | 读取Operate／Read及critique／distill／polish指导；完整CLI另行调用 |
| hnuhole-ui-craft | 本项目编写 | 将现有规则、三者分工、逐页PNG评审和真实Flutter验证接起来 |

安装前核对压缩包条目，只有SKILL.md／许可，无执行脚本；解压验证路径不能逃出技能目录。GitHub技能按SHA下载，没有运行包管理器安装、系统hook或远程二进制。许可保留。外部说明不扩大用户授权，不取代产品规则。

`ui-ux-pro-max`的运行入口使用项目实际路径，例如在PowerShell项目根：

```powershell
python -B .agents/skills/ui-ux-pro-max/scripts/search.py "touch target" --domain ux -n 2
python -B .agents/skills/ui-ux-pro-max/scripts/search.py "text scaling" --stack flutter -n 3
```

已实际运行本地检索：`touch target --domain ux`得到触控相关结果；`community reading mobile --design-system`匹配News/Media并给营销hero，重试`social app mobile`仍给营销展示结构，本项目拒绝采纳／未persist。Flutter `safe area`返回0，记录无匹配，不能拿其他随机命中代证；以项目UI流程和官方平台依据补充。数据库中的Flutter版本不等于本项目版本，建议仍需核对源码和SDK。

Impeccable包含可在首次运行下载二进制的launcher。本轮仅安装与读文档，不运行launcher／hook／live浏览器。项目PNG工作流使用文档参考，无需下载该运行时；未来明确调用完整技能再按其入口执行。web/CSS检测器不证明Flutter或PNG质量。

项目入口：[hnuhole-ui-craft](../../.agents/skills/hnuhole-ui-craft/SKILL.md)；流程：[UI设计与复审](ui-quality-workflow.md)。不覆盖上游技能正文；项目差异集中在本地入口与流程，未来升级按来源SHA审查，不自动追最新。

实际验证：四份技能均通过skill-creator的`quick_validate.py`（Windows使用`python -X utf8`，避免默认GBK读取UTF-8失败）；新本地链接和`git diff --check`通过。完整上游测试套件、Impeccable CLI／hook未运行；技能行为尚未通过新UI图验证。安装共142个文件、约5.84MB，保留来源技能资源，不包含SDK／生成APK或全局缓存。

暂存全部来源后，完整`git diff --cached --check`检测到上游文件已有尾随空白；为保持固定版本正文，不擅自清洗第三方源码。排除三个原样vendor目录后，本项目新技能与文档的暂存补丁检查PASS。`.gitattributes`固定技能文本LF、Windows.cmd为CRLF，避免跨机脚本换行漂移。上述“补丁检查通过”范围为本项目编写的文件，不包含上游空白问题。
