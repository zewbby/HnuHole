"""Update this independent branch's handoff without rewriting historical passes."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    design = ROOT / "docs/design"
    evidence = json.loads((design / "post-image-media-verification-20261015.json").read_text())
    if evidence["scopedResult"] != "PASS":
        raise RuntimeError("completed scoped evidence required")
    summary = "> **2026-10-15 帖子图片后端独立交付：**分支 `codex/post-image-media`，从已提交社区 `e0c128033682923d519ea99546d72503b085a99e` 在独立 clone 实现真实 SQL 原字节存储、最多九张不可变清单、单项短期补传能力、完整验证后原子公开、受保护清单/原图读取与撤销/清理。Go 72个顶层／含子项244 PASS、Python合成图4 PASS、OpenAPI6份、全包编译/vet PASS；宿主替身与真实TLS/SQL/文件系统范围分列，不代表实际cmd/Goose升级/Flutter/设备/iOS/生产通过。只读参考前端 `a696742f943c1cfe6a5005024dccaf40be752d8f`，未修改或合并其工作区；接线前须处理 imageCount/空正文、新媒体摘要、60秒终止租约。PM01/B05/B06仍为后端已实现／宿主与平台待实现或验收，评论/私信只登记未来契约。见[契约与方案](post-image-media-contract.md)、[脱敏证据](post-image-media-verification-20261015.json)；正常提交推送回执另记，不部署、不发布。下方社区与认证证据保留原版本与范围。\n\n"
    for name in ("HANDOFF.md", "progress.md", "module-acceptance-handoff.md"):
        path = design / name
        data = path.read_text()
        if "帖子图片后端独立交付" not in data:
            index = data.index("\n\n") + 2
            path.write_text(data[:index] + summary + data[index:], encoding="utf-8")
    table = """
## PM01 帖子图片服务端（2026-10-15）

| 项目 | 当前证据与边界 |
| --- | --- |
| 实现 | `services/api/internal/postmedia/`、`authprivacy/community_post_images.go`、`authprivacyhttp/post_images_endpoints.go`、迁移0014及精确grants；协议见 `packages/openapi/post-image-api.yaml` 和媒体黄金向量 |
| 真实SQL/字节 | 九图7+2补传、完整清单/散列/尺寸、GIF/WebP原字节、私有受限runtime、取消/禁言/封禁/注销/身份删除/截止清理、原身份重试、竞争围栏；实际文件Gate与限资源Python验证器 |
| HTTP | `post_images_postgres_test.go` 实际loopback TLS+SQL；`post_images_endpoints_test.go` 为严格路由/闭合DTO宿主替身，单独计证 |
| 已执行 | Go72顶层/含子项244全部PASS，Python4、OpenAPI6、全包编译与vet PASS；源指纹/逐用例/重复计数合并见脱敏证据 |
| NOT_RUN | 实际cmd媒体装配、正式Goose旧库前向升级、Flutter上传/持久图片草稿/loader接线、Android API29+设备/原格式相册、iOS、容量/备份擦除/生产安全 |
| 跨模块 | A01/A03/A06/A08/A10/A13、B02/B05/B06/B11与X05；新迁移/授权的scoped回归不升级整模块历史PASS |
| 后续 | 前端按固定双方SHA先解决DTO/摘要/失效差异；独立环境显式配置validator、迁移与grants，再集成验证。评论B07、私信B09未实现，不借用帖子端点 |

复验入口 `services/api/authlab/run-post-images-isolated.sh`，环境与命令见[媒体契约](post-image-media-contract.md)。本轮没有调用Flutter/SDK/ADB/手机，也没有重复TalkBack验收；iOS继续单列NOT_RUN。
"""
    path = design / "module-acceptance-handoff.md"
    data = path.read_text()
    if "## PM01 帖子图片服务端" not in data:
        path.write_text(data + "\n" + table, encoding="utf-8")
    path = design / "module-acceptance-ledger.json"
    ledger = json.loads(path.read_text())
    if "postImageInventoryParent" not in ledger:
        ledger["postImageInventoryParent"] = {key: ledger.get(key) for key in ("branch", "baselineHeadCommit", "workflow", "sourceFingerprint")}
    ledger.update(recordedOn="2026-10-15", branch="codex/post-image-media",
                  baselineHeadCommit=evidence["startingCommit"], workflow="POST_IMAGES_BACKEND_SCOPED_PASS_HOST_AND_PRODUCTION_PENDING")
    ledger["sourceFingerprint"] = {"sha256": evidence["sourceFingerprint"]["canonicalLF_SHA256"],
                                   "presentFileCount": evidence["sourceFingerprint"]["fileCount"],
                                   "evidence": "docs/design/post-image-media-verification-20261015.json",
                                   "scope": "Independent backend/contract runtime source inputs with canonical LF; historical community evidence remains under its original SHA"}
    current = {"recordedOn": "2026-10-15", "branch": "codex/post-image-media", "stableId": "PM01",
               "implementationState": "BACKEND_IMPLEMENTED_HOST_NOT_IMPLEMENTED", "scopedResult": "PASS", "fullModuleResult": "NOT_RUN",
               "report": "docs/design/post-image-media-contract.md", "evidence": "docs/design/post-image-media-verification-20261015.json",
               "testedSourceFingerprint": evidence["sourceFingerprint"]["canonicalLF_SHA256"], "frontendReadOnlyCommit": evidence["frontendReadOnlyCommit"],
               "testCounts": evidence["testCounts"], "notRun": evidence["notRun"],
               "nextAcceptance": "Fixed-SHA host DTO/empty-body/digest/lease alignment and uploader/durable image drafts, explicit isolated runtime/Goose upgrade; Android API29+, iOS and production separately"}
    for module in ledger["modules"]:
        if module["id"] in ("A01", "A03", "A06", "A08", "A10", "A13", "B02", "B05", "B06", "B11"):
            module["postImageMedia20261015"] = current
        elif module["id"] in ("B07", "B09"):
            module["postImageReuseContract20261015"] = {"result": "NOT_RUN", "implementation": "NOT_IMPLEMENTED", "contractOnly": True, "report": current["report"]}
    if not any(module["id"] == "PM01" for module in ledger["modules"]):
        ledger["modules"].append({"id": "PM01", "name": "帖子图片原字节上传、受保护读取与发布绑定", "implementationState": "PARTIAL",
                                  "acceptanceState": "BACKEND_SCOPED_HOST_PASS_FRONTEND_AND_PLATFORM_PENDING", "currentResult": "NOT_RUN",
                                  "verificationEntries": ["PM01-HOST", "X05"], "crossModuleScenes": ["X05"], **current})
    ledger["moduleCount"] = len(ledger["modules"])
    ledger["currentPostImageMedia"] = current
    path.write_text(json.dumps(ledger, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
