"""Test-side decoder for the explicitly versioned packed ledger.

This is inspection only; runtime accounting remains the Lua full scan.
"""
import base64
import struct
import uuid


def decode(raw):
    assert raw[:8] == b'HNCSL02\0' and len(raw) >= 68
    until, count = struct.unpack_from('>QI', raw, 56)
    assert len(raw) == 68 + 206 * count
    entries = {}
    for position in range(68, len(raw), 206):
        record = raw[position:position + 206]
        ident = str(uuid.UUID(bytes=record[:16]))
        cost, created, expires, lease, flags, state = struct.unpack_from('>IQQQBB', record, 176)
        assert ident not in entries and state in (1, 2, 3)
        text = lambda value: base64.urlsafe_b64encode(value).decode().rstrip('=')
        entries[ident] = dict(owner=text(record[16:48]), request=text(record[48:80]),
                              scope=text(record[80:112]), token=text(record[112:144]),
                              digest=record[144:176].hex(), cost=cost, created=created,
                              expires=expires, lease=lease, flags=flags,
                              state={1:'pending',2:'active',3:'aborting'}[state])
    return dict(until_ms=until, entries=entries)
