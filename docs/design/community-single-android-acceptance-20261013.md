# 联合源码单台Android验收清单

> **2026-10-14 当前统一任务单：**用户将双实体Android验证追加到原三项工作之后，顺序为①单机文字社区流程②原生存储与生命周期③系统Passkey及单机回归④双设备NI-X01/NI-X02。见[四阶段统一任务单](community-android-unified-acceptance-plan-20261014.md)。当前只更新计划/交接，没有新增测试或设备操作；单机窗口仍延期，第二设备与两机窗口尚未确认，RP/package/signature关联须另行准备审批。20261013主机/构建证据和其“排除第二设备”保留为原范围历史；新任务整体须四阶段全部收口才通过，iOS/生产和未实现业务仍独立。

日期2026-10-13。第二实体Android NI-X01/X02、iOS、生产部署不纳入本轮通过。认证d859cb05c772cdf8d8b75e439a2bfedf0414dd46的22/0/2及旧社区311是原版本证据，不能代验联合App。设备结果全部NOT_RUN；用户现已明确回复“暂不提供设备窗口；先提交推送整合成果，设备验收保持待执行”。未使用ADB、安装、强停、清数据、卸载或重启手机。标准及隔离候选APK已构建核对；因设备延期，APK/新调试私钥/合成CA材料在交付后清理，未来需独立重建并重新确认设备窗口与数据影响。

先完成标准main Debug/Release ARM64及instrumentation构建，核对manifest、DEX、签名、源码摘要和实际插件注册。Release不配置生产签名、不发布；所有工具及缓存放在E盘或E盘上的WSL内，不调用SDKmanager自动安装。

安装或使用手机前须确认具体物理设备、占用时段和现有App数据影响。建议使用本任务独立包名 org.hnuhole.hnuhole_mobile.communityf5、本任务合成调试签名和新建一次性C/V环境；不覆盖认证主包或acceptance包，不借用认证账号、数据库、签名、密钥或恢复材料。独立包名仅为构建副本overlay，产品Dart源码和已定页面保持相同。若同名包已存在，先只读核对归属和签名，再说明冲突，不自行清除。

设备窗口确认内容：型号及归属、约30至45分钟、认证会话已释放、允许安装隔离包及强停/重开本任务包、是否允许整机重启。需要系统认证或指纹时另行明确提示，由用户在设备操作，不索取秘密。任何adb、安装、启动、重启、卸载或清数据命令在确认前均不执行。

| ID | 操作与证据 | 当前结果 |
|---|---|---|
| CA-A01 | 实际main启动；正式目录/auth/post HTTP、Keystore/business key/SQLite/Passkey插件注册，无MissingPlugin或失败后继续访问 | NOT_RUN |
| CA-A02 | 本任务合成账号正常登录，核实际C/V/Gate/SQL事实；退出后重新登录 | NOT_RUN |
| CA-A03 | 创建/选择身份，在既定编辑与确认页发布，固定原identityId/channelId | NOT_RUN |
| CA-A04 | 重复点击只有一次CREATE；丢响应或重开核同一commandId/digest，不另发命令 | NOT_RUN |
| CA-A05 | 通道列表、正文详情、我的与SQL一致；自动核对和实际中文输入 | NOT_RUN |
| CA-A06 | 正常删除及DELETE丢响应核原命令，正文清除并返回原列表，无重复副作用 | NOT_RUN |
| CA-A07 | 退出重进、A/B切换、草稿/未知命令/删除事实隔离，迟到结果不越账号 | NOT_RUN |
| CA-A08 | 仅强停/重开本任务隔离包，恢复原草稿/命令/绑定，记录新原生进程PID | NOT_RUN |
| CA-A09 | 获整机重启许可后复验Keystore、业务库与已持久状态；不代证断电/OEM迁移 | NOT_RUN |
| CA-A10 | 正式申请注销，经原七天期限和普通worker；清未公开载荷/回执关联及本地库/key，闭号墓碑拒重开，另一账号保留 | NOT_RUN |
| CA-A11 | AndroidBusinessStorageTest原生7项，使用专用namespace及匹配APK | NOT_RUN |
| CA-A12 | vault认证16项、真实进程恢复、原生Passkey codec/错误分类12项，按本次实际执行计数 | NOT_RUN |
| CA-A13 | 实际Passkey接口及取消/拒绝边界；系统正向ceremony另需本任务批准RP/package/signature关联和人工窗口，不能以codec或旧22项代证 | NOT_RUN |

同一runner可支持多个ID，不重复计数。未知结果保留原待办；失败重试保留原身份/通道。注销只用本任务新一次性库和合成数据，测试可信时间推进不改SQL期限或绕过worker，不称真实自然等待七天。

每项保存源码指纹、APK摘要/签名、物理设备事实、包名/PID、命令/时段/退出码、独立SQL布尔事实/计数和脱敏日志摘要。账号、token、验证码、恢复码、证明或私钥不进入Git/聊天；构建、主机替身和人工回答不能计设备PASS。

原原生脚本只选认证类，不能代验business7。仪器APK须核testApplicationId与runner，不覆盖归属不明的同名包。不直接运行带旧auth固定runId或旧账号路径的设备脚本。本任务新签名/包名没有旧认证RP关联，不自动发布assetlinks或改变provider/autofill；缺正向Passkey条件时明确记录阻塞。

完成后仅按确认窗口清本任务资源；用户要求保留隔离App/数据时按约定处理，不自行卸载其他App。最终区分联合主机、原生构建、实际单设备与本轮排除范围。