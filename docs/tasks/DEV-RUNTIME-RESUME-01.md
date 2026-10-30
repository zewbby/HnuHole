# DEV-RUNTIME-RESUME-01 — 旧启动入口绑定已核验部署

- 模式：常规；负责人／状态维护人：本任务Session。
- 分支／PR：`fix/development-runtime-resume`，[PR #91](https://github.com/zewbby/SpeechFUL/pull/91)；初始基线6233c8f，已整合主线规则efef91f。
- 授权依据与边界：用户要求“旧启动脚本也修一下…验证通过后提PR直接合并”；包含三个已知旧入口的私有备份、恢复器安装、必要平稳停启验收与PR。不得清库、recover、降级或扩展正式部署。
- 更新日期：2026-10-30。
- 状态：实现已完成；验证PASS（最终head CI以PR为准）；合并未合并；生产未发布；本机已安装。

## 目标与范围

原safe-resume/reconnect等旧命令统一转发到私有、版本绑定的恢复器，当前只批准a2e98eb的C28/V7及原三Redis；漂移、旧进程、PID复用或Gate异常拒绝，不自动回退。未来部署由负责人显式重新pin。未创建新开机任务，手机USB转发独立处理。

## 接口与依赖

[恢复器说明](../../tools/development_runtime/README.md)定义私有DEVELOPMENT-RESUME/1清单；清单及秘密不进Git。复用已pin的本机adapter用于SQL/归属/启动/清理，间接静态依赖强制覆盖，动态Gate与Redis进程journal分别校验。相关模块A02/A03/A06/A12，模块整体结论不提升。

## 验收标准

- 错版本/配置/数据库schema/进程归属拒绝，双同步resume先于API，无recover/reset/初始化namespace。
- 两PG/三Redis/四API-watch全停后由旧入口恢复原部署，严格TLS ready且原会话/代次/审计不变。
- 三旧入口重复调用PID不变，测试和专用CI通过。

## 当前进度与证据

| 项目 | 被测版本／环境 | 结果与证据 |
| --- | --- | --- |
| 源码与安装 | fe8cba1中的resume.py，SHA256 0b22952d8554c8d32b86528628f145108137038ec559238435ec46357427628c；后继仅整合规则/任务文档 | 本机三个旧入口备份后替换，实际部署已完成 |
| 单元与编排 | Linux Python普通和-O，unittest discover -s tools/development_runtime/tests -v | 10项各PASS；依赖缺项、动态证据、失败顺序、归属与幂等 |
| 真实依赖冷启动 | 同一非root WSL原数据，最终安装源码；原入口全停再启及重复调用 | PASS，见[脱敏记录](../design/validation/development-runtime-resume-20261030.json) |
| 独立审查 | 新规则整合前按原AGENTS安排的只读agent review，源码摘要与安装相同 | 无阻断；不是GitHub成员批准。未由审查agent复跑私有环境 |
| 附加手机 | 当前主体无可启动activity | NOT_RUN，不重装/重登代证；原PR89隔夜结果保持原范围 |

## 阻碍与下一步

无代码阻断；最终精确head必要CI通过后按用户授权合并，保存回执。整合efef91f后本页为唯一任务状态来源；[早期分支记录](../branches/fix-development-runtime-resume.md)和旧HANDOFF等保留为此前规则阶段快照，后续不再并行维护。生产/iOS/再次真实隔夜窗口未追加验收。
