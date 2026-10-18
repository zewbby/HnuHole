"""Remove only this task's Linux caches, synthetic fixtures, temps and raw logs.

Retains the authoritative Windows clone and Linux source mirror. Refuses active
task processes and symlinked/outside targets. No service or device commands.
"""
import json
import os
from pathlib import Path
import shutil
import sys

ROOT = Path("/home/hnuhole/post-image-media-20261015")


def main():
    if not ROOT.is_dir() or ROOT.is_symlink() or ROOT.resolve() != ROOT or ROOT.stat().st_uid != os.getuid():
        raise RuntimeError("owned absolute root verification failed")
    ancestors = {os.getpid()}
    process = os.getpid()
    while process > 1:
        fields = Path(f"/proc/{process}/status").read_text().splitlines()
        process = int(next(line.split()[1] for line in fields if line.startswith("PPid:")))
        ancestors.add(process)
    active = []
    for entry in Path("/proc").iterdir():
        if not entry.name.isdigit() or int(entry.name) in ancestors:
            continue
        try:
            if str(ROOT).encode() in (entry / "cmdline").read_bytes():
                active.append(int(entry.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    if active:
        raise RuntimeError("task processes still active; no files removed")
    targets = [ROOT / name for name in ("go-cache", "go-mod", "pip-cache", "python", "fixtures", "tmp")]
    targets += list(ROOT.glob("*.log")) + list(ROOT.glob("*.jsonl"))
    for target in targets:
        if target.is_symlink() or target.resolve().parent != ROOT:
            raise RuntimeError("refusing outside/symlink cleanup target")
    destination = Path(sys.argv[1])
    evidence = json.loads(destination.read_text())
    if evidence.get("schemaVersion") != "hnuhole-post-image-media-evidence/v1":
        raise RuntimeError("expected task evidence before cleanup")
    result = {"status": "PASS", "root": str(ROOT), "removed": [], "alreadyAbsent": [], "retained": ["repo (source mirror)", "authoritative E:/Hnuhole-post-image-media-20261015/repo"], "activeOwnedProcesses": 0}
    for target in targets:
        if not target.exists():
            result["alreadyAbsent"].append(target.name)
            continue
        if target.is_dir():
            # Go intentionally makes module-cache directories read-only. Adjust
            # only verified own directories, without following their symlinks.
            for directory, _, _ in os.walk(target, followlinks=False):
                path = Path(directory)
                if path.is_symlink() or path.stat().st_uid != os.getuid():
                    raise RuntimeError("foreign/symlink directory in task cache")
                path.chmod(0o700)
            shutil.rmtree(target)
        else:
            target.unlink()
        result["removed"].append(target.name)
    evidence["cleanup"] = result
    destination.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Owned task caches, fixtures, temporary material and raw logs removed; source and redacted evidence retained.")


if __name__ == "__main__":
    main()
