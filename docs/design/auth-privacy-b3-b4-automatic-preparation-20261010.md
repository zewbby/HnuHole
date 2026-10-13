# B3+B4 自动准备接续记录（2026-10-10）

用户要求：一次性完成固定 B3+B4；先完成无需手机的诊断、修复、构建与回归，再集中进行人工配合。不得增加范围或逐场景反复请求安装、指纹。

当前固定范围为 11 项。已有 4 项通过证据保留原版本：NI-C02、NI-D04、NI-K01、NI-K02。剩余 7 项 NI-C01、NI-C03、NI-C04、NI-D01、NI-D02、NI-D03、NI-D05 尚未通过，不能计为完成。

本轮已修改原生响应编码兼容、限定测试显示标签、关联错误诊断及相应原生测试和 release 探针。尚未执行本轮构建或回归；历史 native/release PASS 不能代证这些修改。后续须先同步 PendingOperation.kt 到构建缓存，并更新 release 检查集及源码哈希。

仍需完成：使用正常 discoverable assertion 并核对真实凭据 ID；关闭前先验证实际断言；修正移除夹具不强制同设备连续创建两条凭据；以实际 SQL 事务验证其他凭据保留；补齐原生窗口结束检查、计数与统一包构建。不得放宽空 userHandle、重写签名证明或把通用 cancellation 计为关联拒绝。

执行环境阻塞：受限执行与 node_repl 初始化返回 helper_unknown_error: setup refresh had errors；自动审批返回 stream disconnected before completion。命令未执行，审批未判定其不安全；不得绕过审批。恢复 Codex 执行环境后继续原批次，不启动新批次或重置环境。

本阶段没有启动手机安装、Passkey 系统窗口、卸载或账号关闭。保留现有服务、缓存、SDK/AVD、账号状态和原操作核对锚点。自动部分全部完成后，再给出统一人工操作清单与固定包哈希，进入一次集中手机窗口。

最终同步 module-acceptance-handoff.md、module-acceptance-ledger.json、HANDOFF.md、progress.md 和小型脱敏验证记录；未执行或失败项如实登记，不提交或推送未经当次授权的变更。


> **2026-10-10 B3＋B4 v16凭据选择失败收尾：**本轮剩余七项新增PASS为0，固定11项累计仍4项原版本PASS／7项FAIL。主包v16已更新并保留账号／草稿；12项原生测试、13项Release边界、当前分析和四包签名构建通过，共享188项及SQL249项沿用v15未变源码的原范围。调试名称已同时设置user.name／displayName，实际账号handle／签名检查未改。用户截图曾出现唯一合成标签，但实际目标断言未完成；同名列表查找和60秒窗口导致超时，失败原版本与原请求保留。定位脚本已改用专用临时XML、按唯一标签有限滚动，不自动选择／认证；尚未取得成功真实定位证据。停止本轮人工窗口，不再自动弹安装或认证，不再推进关闭。先通过实际可辨认目标和同一ID断言预检，才恢复固定项集中验收。环境、手机数据和历史证据保留；未提交／推送。见[当前自动准备范围](../../services/api/authlab/android-b3b4-v16-preparation-verification.json)。
