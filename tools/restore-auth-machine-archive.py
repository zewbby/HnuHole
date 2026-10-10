#!/usr/bin/env python3
"""Verify and decrypt the transferred auth cache before any extraction."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import tarfile
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

HEADER = b'HNUHOLE-AUTH-ARCHIVE-1\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--parts-directory', type=Path, required=True)
    parser.add_argument('--key-file', type=Path, required=True)
    parser.add_argument('--output-directory', type=Path, required=True)
    parser.add_argument('--extract', action='store_true')
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding='utf-8-sig'))
    key = base64.urlsafe_b64decode(args.key_file.read_text().strip())
    if len(key) != 32:
        raise ValueError('Expected a 256-bit archive key')
    args.output_directory.mkdir(parents=True, exist_ok=True)
    for archive in manifest['archives']:
        name = archive['name']
        if Path(name).name != name:
            raise ValueError('Invalid archive name')
        encrypted = args.output_directory / (name + '.joined.enc')
        plaintext = args.output_directory / (name + '.tar.gz')
        if encrypted.exists() or plaintext.exists():
            raise ValueError('Preserve existing restored files')
        with encrypted.open('xb') as combined:
            for part in archive['parts']:
                if Path(part['name']).name != part['name']:
                    raise ValueError('Invalid part name')
                path = args.parts_directory / part['name']
                if path.stat().st_size != part['bytes']:
                    raise ValueError('Archive part size mismatch')
                digest = hashlib.sha256()
                with path.open('rb') as source:
                    while chunk := source.read(4 * 1024 * 1024):
                        digest.update(chunk)
                        combined.write(chunk)
                if digest.hexdigest() != part['sha256']:
                    raise ValueError('Archive part SHA-256 mismatch')
        digest = hashlib.sha256()
        with encrypted.open('rb') as source:
            while chunk := source.read(4 * 1024 * 1024):
                digest.update(chunk)
        if digest.hexdigest() != archive['sha256']:
            raise ValueError('Complete encrypted archive SHA-256 mismatch')
        try:
            with encrypted.open('rb') as source, plaintext.open('xb') as target:
                if source.read(len(HEADER)) != HEADER:
                    raise ValueError('Unrecognized archive envelope')
                nonce = source.read(12)
                source.seek(-16, os.SEEK_END)
                tag = source.read(16)
                payload_end = source.tell() - 16
                source.seek(len(HEADER) + 12)
                decryptor = Cipher(algorithms.AES(key), modes.GCM(nonce, tag)).decryptor()
                decryptor.authenticate_additional_data(HEADER)
                while source.tell() < payload_end:
                    chunk = source.read(min(4 * 1024 * 1024, payload_end - source.tell()))
                    target.write(decryptor.update(chunk))
                target.write(decryptor.finalize())
            print('VERIFIED_AND_DECRYPTED: ' + name)
            if args.extract:
                destination = args.output_directory / (name + '-contents')
                if destination.exists():
                    raise ValueError('Preserve an existing extraction directory')
                destination.mkdir()
                with tarfile.open(plaintext, 'r:gz') as archive_file:
                    archive_file.extractall(destination, filter='data')
                print('EXTRACTED: ' + str(destination))
        except Exception:
            # Delete only the exact incomplete plaintext created by this run.
            plaintext.unlink(missing_ok=True)
            raise


if __name__ == '__main__':
    main()
