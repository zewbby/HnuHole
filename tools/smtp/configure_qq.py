#!/usr/bin/env python3
"""Prepare QQ SMTP in Linux private files; no network connection or email send."""
import argparse
import getpass
import json
import os
from pathlib import Path
import re
import secrets
import stat
import sys


def private_directory(path):
    path = Path(path)
    if path.is_symlink():
        raise ValueError("private directory must not be a symlink")
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = path.stat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError("private directory must belong to you and have mode 700")
    return path.resolve()


def write_private(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())


def prepare(directory, address, authorization):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*@qq[.]com", address):
        raise ValueError("enter your complete @qq.com test sender address")
    if not re.fullmatch(r"[A-Za-z0-9]{16}", authorization):
        raise ValueError("QQ requires a 16-character authorization code, not the account password")
    directory = private_directory(directory)
    tag = secrets.token_hex(6)
    secret = directory / ("qq-" + tag + ".secret")
    fragment = directory / ("qq-" + tag + ".json")
    settings = {"smtpMode": "tls", "smtpAddress": "smtp.qq.com:465",
                "smtpFrom": address, "smtpUsername": address,
                "smtpPasswordFile": str(secret)}
    write_private(secret, authorization.encode("ascii"))
    write_private(fragment, (json.dumps(settings, indent=2) + "\n").encode("utf-8"))
    return fragment, settings


def apply_to_verifier(filename, settings):
    filename = Path(filename)
    info = filename.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > 32768:
        raise ValueError("V configuration must be your regular file, at most 32 KiB")
    if filename.parent.stat().st_mode & 0o022:
        raise ValueError("V configuration directory must not be writable by other users")
    original = filename.read_bytes()
    config = json.loads(original)
    if not isinstance(config, dict) or config.get("environment") != "dev" or not all(
        config.get(key) for key in ("otpKeyFile", "mailEncryptionKeyFile", "trustedCommunityKeyFile")
    ) or config.get("requestKeyFile"):
        raise ValueError("expected an existing dev verifier configuration, never C or production")
    updated = dict(config, **settings)
    encoded = (json.dumps(updated, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if len(encoded) > 32768:
        raise ValueError("updated V configuration is too large")
    suffix = secrets.token_hex(6)
    backup = filename.with_name(filename.name + ".smtp-backup-" + suffix)
    temporary = filename.with_name(filename.name + ".smtp-new-" + suffix)
    write_private(backup, original)
    write_private(temporary, encoded)
    current = filename.lstat()
    if (info.st_ino, info.st_mtime_ns, info.st_size) != (current.st_ino, current.st_mtime_ns, current.st_size):
        temporary.unlink()
        raise ValueError("V configuration changed concurrently; left it untouched")
    os.replace(temporary, filename)
    return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, default=Path.home() / ".config/hnuhole/smtp-test")
    parser.add_argument("--verifier-config", type=Path, help="explicitly update this existing dev V config, with a private backup")
    args = parser.parse_args()
    if sys.platform != "linux" or not sys.stdin.isatty():
        parser.error("run interactively in WSL/Linux as the backend owner")
    try:
        address = input("QQ test sender address: ").strip()
        authorization = getpass.getpass("QQ SMTP authorization code (hidden): ").strip()
        fragment, settings = prepare(args.directory, address, authorization)
        authorization = None
        print("Private SMTP settings prepared: " + str(fragment))
        if args.verifier_config:
            backup = apply_to_verifier(args.verifier_config, settings)
            print("Dev V SMTP settings updated; backup: " + str(backup))
        print("No service restarted, no connection made, no email sent.")
    except (OSError, ValueError, EOFError):
        # Never render exception values: JSON decoder errors and filesystem paths
        # may contain material from a user's configuration.
        print("Setup failed. Check the address, 16-character authorization code, file ownership and private permissions.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
