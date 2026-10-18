# ADR 0006：文字发布的命令回执、公开事务与停止代次

日期：2026-10-08。状态：accepted for implementation design，业务实现及动态验收NOT_RUN。

## 背景

[产品规则](../design/modules/post-composer.md)要求确认后回通道、后台公开、未知结果核对原任务；[匿名契约](../design/auth-privacy-business-contract.md)要求受理时原子固定账号＋帖子的身份，并在申请注销、处罚或删身份先赢时停止未公开任务。退出、换机或密码重设则不取消已受理任务。

如果CREATE超时后的GET查无被当作“没提交”，用户换身份新发时迟到原请求仍可能公开。若仅检查当前ACTIVE／未禁言，取消注销或处罚到期又会让先前任务自动复活。若直接依赖会话代次，正常退出和换机反而会错误取消已受理任务。

## 决策

采用账号域的不可变命令回执、独立任务尝试和两次最终C事务。受理事务一次建立固定身份／任务／原结果；公开事务由无Bearer的worker复核当前Gate和持久权限，提交可见内容及PUBLISHED。

命令查无只返回UNKNOWN_NOT_OBSERVED。显式seal与原命令按同账号锁串行；缺原结果则留下NOT_ACCEPTED防重执行记录，已有结果则保持原事实。已受理任务通过单独cancel处理，不让seal推翻受理。

引入publicationStopGeneration。申请注销、生效封禁／禁言在原最终事务推进；旧attempt捕获的代次不匹配时永久停止。会话接替、退出、重设和临时Gate冻结不推进该代次。显式合法retry新增attempt，不能自动恢复旧attempt。

## 权衡

相比单次同步创建，增加命令/任务/attempt表、封印接口、worker与生命周期hooks，并需永久小型防重执行墓碑。代价换来后台发送、未知结果和停止竞争的确定语义；若后续改回单次同步发布，客户端恢复和已有回执迁移成本很高。

不采用“404就另发”“旧session无效就取消”或“只检查当前处罚”的简化方式，因为它们分别违反迟到幂等、已受理继续及停止不复活的规则。

## 后果与验证

[后端设计](../design/community-text-posting-backend-design.md)与[OpenAPI](../../packages/openapi/post-api.yaml)是实施入口。数据库/Go/Dart/设备尚未验；T2必须取得封印与迟到提交、cancel/publication竞争、申请关闭后取消、处罚到期和身份删除的SQL证据。普通封禁API或身份CRUD通过不能代证内容联动，生产容量／墓碑保留仍单列。
