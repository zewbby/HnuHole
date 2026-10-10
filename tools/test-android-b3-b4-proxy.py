#!/usr/bin/env python3
"""Focused bounds tests for actual-proof RP mutation; synthetic bytes only."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest

spec=importlib.util.spec_from_file_location('owned_b3b4_proxy',Path(__file__).with_name('android-auth-b3-b4-proxy.py'))
proxy=importlib.util.module_from_spec(spec);spec.loader.exec_module(proxy)


class RpMutationTests(unittest.TestCase):
    def body(self,raw):
        return json.dumps({'challengeId':'synthetic-not-a-proof','webauthnAttestation':{
            'id':'synthetic','response':{'attestationObject':base64.urlsafe_b64encode(raw).decode().rstrip('='),
            'clientDataJSON':'synthetic'}}}).encode()
    def test_mutates_only_exact_32_byte_hash(self):
        auth=hashlib.sha256(b'zewbby.github.io').digest()+b'\x41'+bytes(4)+bytes(range(80))
        for length in (b'\x58'+bytes([len(auth)]),b'\x59'+len(auth).to_bytes(2,'big')):
            raw=b'\xa1\x68authData'+length+auth
            before=json.loads(self.body(raw));after=json.loads(proxy.changed_rp_hash(self.body(raw)))
            altered=base64.urlsafe_b64decode(after['webauthnAttestation']['response']['attestationObject']+'===')
            pos=10+len(length)
            self.assertEqual(altered[:pos],raw[:pos])
            self.assertEqual(altered[pos:pos+32],hashlib.sha256(b'unassociated.zewbby.github.io').digest())
            self.assertEqual(altered[pos+32:],raw[pos+32:])
            after['webauthnAttestation']['response']['attestationObject']=before['webauthnAttestation']['response']['attestationObject']
            self.assertEqual(after,before)
    def test_refuses_wrong_original_hash_duplicate_key_truncated_or_oversized(self):
        good=hashlib.sha256(b'zewbby.github.io').digest()+bytes(5)
        for raw in (b'\xa1\x68authData\x58\x25'+bytes(37),
                b'\x68authData\x68authData',b'\xa1\x68authData\x59\x20\x00'+good,
                bytes(16385),b'\xa1\x68authData\x41'+good):
            with self.assertRaises((AssertionError,IndexError)):
                proxy.changed_rp_hash(self.body(raw))


if __name__=='__main__':unittest.main()
