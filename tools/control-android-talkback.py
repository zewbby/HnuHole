"""Bounded host evidence for a human-assisted, owned vivo TalkBack run.

Does not enable services or collect speech, notifications, passwords or app text.
Original accessibility settings can only be restored from this run's snapshot.
"""
import argparse
import datetime
import json
import re
import subprocess
from pathlib import Path

DEVICE = "10CEAG17RY003M7"
PACKAGE = "com.google.android.marvin.talkback"
VISION_AID = "com.vivo.visionaid.builtin/com.vivo.visionaid.imagedetect.VisionAidAccessibilityService"
ADB = Path("D:/zewbbyTest/Hnuhole-env/android-sdk/platform-tools/adb.exe")
ROOT = Path("D:/zewbbyTest/Hnuhole-android-live-faults-20261005/matrix")


def run(*args):
    result = subprocess.run([str(ADB), "-s", DEVICE, *args], capture_output=True,
                            text=True, encoding="utf-8", timeout=30)
    if result.returncode:
        raise RuntimeError("Owned device accessibility operation unavailable")
    return result.stdout.strip()


def snapshot():
    enabled = run("shell", "settings", "get", "secure", "accessibility_enabled")
    services = run("shell", "settings", "get", "secure", "enabled_accessibility_services")
    dump = run("shell", "dumpsys", "accessibility")
    version = re.search(r"\bversionName=([^\s]+)", run("shell", "dumpsys", "package", PACKAGE))
    # Only the bound-service summary, not installed services or window data,
    # establishes a loaded service. Keep the raw dumps local to this call.
    lines = dump.splitlines()
    bound = False
    for index, line in enumerate(lines):
        if not any(key in line for key in ("Bound services", "mBoundServices", "boundServices")):
            continue
        indent = len(line) - len(line.lstrip())
        section = [line]
        for following in lines[index + 1:]:
            if following.strip() and len(following) - len(following.lstrip()) <= indent:
                break
            section.append(following)
        # This vivo dump prints bound service labels, not component names.
        # Require its spoken TalkBack entry plus a live Google service record.
        if any("Service[label=TalkBack," in value and "FEEDBACK_SPOKEN" in value for value in section):
            bound = True
    activity = run("shell", "dumpsys", "activity", "services", PACKAGE)
    live_component = re.search(r"ServiceRecord[^\n]*" + re.escape(PACKAGE) + r"/[^\n]*TalkBackService", activity) is not None
    bound = bound and live_component and "ProcessRecord" in activity
    return {"accessibilityEnabled": enabled, "enabledServices": services,
            "talkBackSelected": PACKAGE in services, "talkBackBound": bound,
            "talkBackVersion": version[1] if version else "UNKNOWN"}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["baseline", "status", "restore", "stage"])
    parser.add_argument("--phase", choices=["phone-talkback-navigate", "phone-talkback-read"])
    args = parser.parse_args()
    assert (ROOT / "OWNER").read_text().strip() == "HNUHOLE_ANDROID_MATRIX_V1"
    marker = ROOT / "driver/apps/mobile/.device-app-owner"
    assert marker.read_text() == DEVICE + "|hnuhole-android-live-matrix-20261006"
    baseline = ROOT / "talkback-settings-baseline.json"
    if args.action == "stage":
        value = json.loads(run("shell", "run-as", "org.hnuhole.hnuhole_mobile", "cat",
                               "files/owned-device-driver-stage.json"))
        assert str(value["pid"]) == run("shell", "pidof", "org.hnuhole.hnuhole_mobile")
        print(json.dumps(value))
        return
    current = snapshot()
    if args.action == "baseline":
        assert not baseline.exists(), "Preserve the original baseline"
        baseline.write_text(json.dumps(current, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(current))
    elif args.action == "status":
        assert args.phase
        assert current["accessibilityEnabled"] == "1" and current["talkBackSelected"]
        assert current["talkBackBound"], "TalkBack selected but loaded service not confirmed"
        record = {"result": "PASS", "phase": args.phase, "actualLoadedTalkBack": True,
                  "actualAccessibilityEnabled": True, "version": current["talkBackVersion"],
                  "speechCaptured": False, "settingsFabricated": False}
        evidence = ROOT / (args.phase + "-host.json")
        previous = json.loads(evidence.read_text(encoding="utf-8")) if evidence.exists() else {}
        observations = previous.get("observations", [])
        observations.append({"capturedAtUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                             "actualLoadedTalkBack": True, "actualAccessibilityEnabled": True})
        record["observations"] = observations
        evidence.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(record))
    else:
        original = json.loads(baseline.read_text(encoding="utf-8"))
        def members(value): return {item for item in value.split(":") if item and item != "null"}
        previous = members(original["enabledServices"])
        current_members = members(current["enabledServices"])
        introduced = current_members - previous
        # The first human activation in this run selected this exact vivo
        # service instead of TalkBack. Restore that known test-only change too;
        # refuse any unrelated new service rather than override its preference.
        assert all(item.startswith(PACKAGE + "/") or item == VISION_AID for item in introduced)
        assert previous <= current_members
        if original["enabledServices"] == "null":
            run("shell", "settings", "delete", "secure", "enabled_accessibility_services")
        else:
            assert re.fullmatch(r"[A-Za-z0-9._/:]*", original["enabledServices"])
            run("shell", "settings", "put", "secure", "enabled_accessibility_services", "'" + original["enabledServices"] + "'")
        run("shell", "settings", "put", "secure", "accessibility_enabled", original["accessibilityEnabled"])
        after = snapshot()
        assert after["accessibilityEnabled"] == original["accessibilityEnabled"]
        assert after["enabledServices"] == original["enabledServices"]
        record = {"result": "PASS", "originalAccessibilityRestored": True,
                  "unrelatedAccessibilityServicesUnchanged": True, "talkBackOriginallyEnabled": original["talkBackSelected"],
                  "testEnabledVivoVisionAidRestored": VISION_AID in introduced,
                  "restoredSettingKeys": ["accessibility_enabled", "enabled_accessibility_services"]}
        (ROOT / "talkback-settings-restoration.json").write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(record))


if __name__ == "__main__":
    main()
