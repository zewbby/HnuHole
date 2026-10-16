#!/usr/bin/env python3
"""Private, disposable canaries for the real R03 processes; never print values."""
import base64
import json
import pathlib
import secrets
import sys


def create(directory):
    values = {
        "email": "ac03-" + secrets.token_hex(12) + "@hainanu.edu.cn",
        "password": "ac03-password-" + secrets.token_hex(12),
        "uuid": "ac03-invalid-uuid-" + secrets.token_hex(12),
        "trace": "ac03-private-trace-" + secrets.token_hex(12),
        "cKey": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("="),
        "vKey": base64.urlsafe_b64encode(secrets.token_bytes(32)).decode().rstrip("="),
    }
    (directory / "privacy-canaries.json").write_text(json.dumps(values))
    # PREPARE/EXECUTE exercises actual parameter-bearing failures. Client-side
    # diagnostics stay private; server and ordinary app logs must omit values.
    sql = """CREATE TEMP TABLE privacy_diagnostics_canary (
 email text UNIQUE, password text CHECK(password <> '{password}')
);
PREPARE privacy_bound_canary(text,text) AS INSERT INTO privacy_diagnostics_canary VALUES($1,$2);
EXECUTE privacy_bound_canary('{email}','safe-test-value');
EXECUTE privacy_bound_canary('{email}','safe-test-value');
EXECUTE privacy_bound_canary('another-synthetic-address','{password}');
SELECT '{uuid}'::uuid;
""".format(**values)
    (directory / "privacy-canary.sql").write_text(sql)
    (directory / "privacy-c-body.json").write_text(json.dumps({
        "username": "private_user", "password": values["password"],
        "installationId": "AQEBAQEBAQEBAQEBAQEBAQ",
        "email": values["email"],  # Unknown C field must fail before business.
    }))
    (directory / "privacy-v-body.json").write_text(json.dumps({
        "email": values["email"], "password": values["password"],
    }))
    for party in ("c", "v"):
        (directory / ("privacy-" + party + "-headers.private")).write_text(
            "X-Request-ID: AgICAgICAgICAgICAgICAg\n"
            "X-Correlation-ID: " + values["trace"] + "\n"
            "Traceparent: " + values["trace"] + "\n"
            "Baggage: " + values["email"] + "\n"
            "Idempotency-Key: " + values[party + "Key"] + "\n"
            + ("V-Installation-ID: AgICAgICAgICAgICAgICAg\n" if party == "v" else "")
        )



def verify(directory):
    values = json.loads((directory / "privacy-canaries.json").read_text())
    for party in ("c", "v"):
        errors = (directory / ("privacy-" + party + "-client.private")).read_text()
        # A logging pass requires each intended error to have actually occurred.
        if not all(term in errors for term in ("duplicate key", "check constraint", "invalid input syntax")):
            raise SystemExit("R03 privacy canary did not exercise all SQL error classes")
        if not all(values[key] in errors for key in ("email", "password", "uuid")):
            raise SystemExit("R03 bound values did not reach the intended SQL failures")
        server_log = (directory / ("privacy-pg-" + party + ".log")).read_text()
        if "AC03_RUNTIME_LOG_CONTROL" not in server_log:
            raise SystemExit("R03 privacy log capture is missing its positive control")
        if any(value in server_log for value in values.values()):
            raise SystemExit("R03 private SQL values appeared in the PostgreSQL server log")
    for log in directory.glob("*.log"):
        text = log.read_text(errors="replace")
        if any(value in text for value in values.values()):
            raise SystemExit("R03 sensitive canary appeared in ordinary process diagnostics")
    for party in ("c", "v"):
        response = json.loads((directory / ("privacy-" + party + "-response.private")).read_text())
        if set(response) != {"error", "requestId"} or set(response["error"]) != {"code", "message"}:
            raise SystemExit("R03 privacy failure response has unexpected fields")
        text = json.dumps(response)
        if any(value in text for value in values.values()) or response["requestId"] == "AgICAgICAgICAgICAgICAg":
            raise SystemExit("R03 privacy failure returned sensitive values or an inbound request ID")
    # The actual lifecycle already used real HTTP inputs. Its private state
    # supplies additional canaries; these values must also stay out of logs.
    state = json.loads((directory / "probe-state" / "session.json").read_text())
    def strings(value):
        if isinstance(value, str) and len(value) >= 6:
            yield value
        elif isinstance(value, dict):
            for child in value.values():
                yield from strings(child)
        elif isinstance(value, list):
            for child in value:
                yield from strings(child)
    process_text = "\n".join(log.read_text(errors="replace") for log in directory.glob("*.log"))
    if any(value in process_text for value in strings(state)):
        raise SystemExit("R03 private lifecycle state appeared in ordinary diagnostics")


directory = pathlib.Path(sys.argv[2])
if not directory.is_dir() or directory.name[:16] != "hnuhole-runtime.":
    raise SystemExit("R03 privacy canary requires its known disposable directory")
if sys.argv[1] == "create":
    create(directory)
elif sys.argv[1] == "verify":
    verify(directory)
else:
    raise SystemExit("Unknown privacy canary operation")
