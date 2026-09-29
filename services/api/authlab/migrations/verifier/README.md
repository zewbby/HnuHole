# V 隔离实验迁移

在单独、可丢弃的 V 实验数据库中依序执行全部 SQL：`0001_authprivacy_lab.sql` 建立配额与收据边界，`0002_otp.sql` 增加 OTP／邮件任务／预算，`0003_confirmation.sql` 增加原确认与固定签名任务及退役后的续办。实验执行器按文件名排序同事务加载，不能用来覆盖现有数据库。

以一个事务执行完整文件。文件仅含 Up SQL，没有事务包装或 Down；由实验执行器决定是否提交。不可拿它覆盖现有数据库。

## 字段契约

| 表 | 核心字段 |
| --- | --- |
| `used_slots` | `slot_id bytea32` 主键，`state RESERVED/RETIRED/RELEASED`，`version bigint` |
| `email_quota` | `email_exact bytea` 主键，`current_slot bytea32` 全局唯一，`bootstrap_public_key bytea32`，`quota_version`；生成的 `slot_state=RESERVED` 只用于复合外键 |
| `retire_pending` | `old_slot bytea32` 主键，`email_exact/quota_version`，固定 `new_slot/new_bootstrap_public_key bytea32`，`retirement_authorization bytea123`，`state=PENDING` |
| `processed_receipts` | `slot_id bytea32` 主键，`purpose RETIRED/RELEASED`，`version`；无邮箱 |
| `request_results` | `(operation,key_digest bytea32)` 主键与 `UNIQUE(key_digest)`；LIVE 的 `request_hmac/hmac_key_version/installation_id/flow_id/result_code/expires_at`；EXPIRED 仅保留操作、摘要和状态 |

邮箱唯一性比较精确字节，不折叠大小写或别名。邮箱解析与校园域检查由调用层处理；实验中的 3–254 字节长度约束不构成邮箱语法校验。邮箱配额、公钥和退役待办在其生命周期内不可替换；正常换槽位在旧收据处理事务删除旧配额后重新插入。

## 原子效果

- RESERVED 槽位必须对应唯一当前配额，且没有 processed receipt。
- RETIRED/RELEASED 槽位必须同时没有旧配额、有同用途的永久 processed receipt；用途冲突、部分删除或部分终态提交均被拒绝。
- 退役待办复合外键绑定原精确地址、槽位和配额版本。处理旧槽位时须同事务删除待办、删除旧配额、写终态及 processed receipt。
- 旧槽位及 processed receipt 永久不可删除或改变用途，旧回执重复处理不能清理后来新槽位；请求结果 EXPIRED 锚点不能重新执行或删除。

Go 命令仍须严格验签并核对受信 C 身份、槽位、公钥散列、原待办及版本。先定位邮箱，再按规范取得地址锁和行锁，不能仅靠上述约束代替业务判断。只有提交成功后才可 ACK；事务里没有 SMTP、HSM 或对端 HTTP。

本实验已提供 OTP 确认，但不提供邮箱恢复旧号入口、真实密钥托管、可信备份恢复或 V/C 独立运营证明；表拥有者的 DDL 权限也没有作为生产权限模型验收。跨表状态以复合外键和 deferred constraint trigger 表达，依据 [PostgreSQL 约束文档](https://www.postgresql.org/docs/current/ddl-constraints.html)和 [CREATE TRIGGER](https://www.postgresql.org/docs/current/sql-createtrigger.html)。

## OTP 与原确认扩展

`otp_email_state`／`otp_flows` 固定邮箱代次与最新码；`otp_code_versions` 保存独立钥 HMAC，以短期识别旧码；`device_email_limits` 与 `otp_budget_events` 分开计设备真错和滚动地址预算。设备与地址的 `last_activity_at` 使用数据库时钟，闲置二十四小时且没有有效锁／生命周期引用时有界清理；仍有配额或未决证据时保留原代次。`mail_outbox` 先提交发送尝试、再接触 SMTP；原文加密，完成／过期即擦除，未知状态不重发。

`otp_confirmations` 持久原确认的旧／新槽位、公钥、OTP 期限及原准入桶，临时退役待办删除不丢这些绑定；`confirmation_sign_jobs` 保存固定消息与签名 CAS。`email_quota.reservation_confirmation_key_digest` 防原续办接管别人后来占用的同地址配额。结果仅原 POST 十分钟可重取，清理后的锚点只留操作／摘要／EXPIRED。未决旧退役继续处理，结果过期不能新签资格。

`confirmation_rejections` 仅为已计数的第三次错误保存原键摘要与不可延长的锁到期时刻，重放按数据库时间计算剩余等待，不再计验证码。原结果过期时同事务删除短期等待记录；不复制邮箱、验证码或安装标识。
