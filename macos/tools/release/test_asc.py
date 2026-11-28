#!/usr/bin/env python3
"""第 37 步：asc.py 的测试（不连 App Store Connect）。用临时生成的 EC 密钥签 JWT，再用 openssl 验证签名。

  python3 macos/tools/release/test_asc.py
"""
import base64
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402


def unb64(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


class AscTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.key = os.path.join(cls.tmp.name, "AuthKey_TEST.p8")
        cls.pub = os.path.join(cls.tmp.name, "pub.pem")
        # App Store Connect 的 .p8 是 PKCS#8 的 P-256 私钥
        ec = subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout"],
                            capture_output=True, check=True).stdout
        p8 = subprocess.run(["openssl", "pkcs8", "-topk8", "-nocrypt"], input=ec,
                            capture_output=True, check=True).stdout
        with open(cls.key, "wb") as f:
            f.write(p8)
        subprocess.run(["openssl", "ec", "-in", cls.key, "-pubout", "-out", cls.pub],
                       capture_output=True, check=True)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_jwt_header_and_payload(self):
        token = asc.make_jwt("ABC123DEFG", "11111111-2222-3333-4444-555555555555", self.key, now=1000)
        h, p, s = token.split(".")
        self.assertEqual(json.loads(unb64(h)), {"alg": "ES256", "kid": "ABC123DEFG", "typ": "JWT"})
        payload = json.loads(unb64(p))
        self.assertEqual(payload["iss"], "11111111-2222-3333-4444-555555555555")
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertEqual(payload["iat"], 1000)
        # App Store Connect 不接受超过 20 分钟的令牌
        self.assertLessEqual(payload["exp"] - payload["iat"], 1200)
        self.assertEqual(len(unb64(s)), 64)

    def test_jwt_signature_verifies(self):
        for _ in range(5):   # r、s 有时以 0x00 开头或最高位是 1，多试几次
            token = asc.make_jwt("ABC123DEFG", "issuer", self.key)
            signing_input, sig = token.rsplit(".", 1)
            der = asc.raw_to_der(unb64(sig))
            sig_file = os.path.join(self.tmp.name, "sig.der")
            with open(sig_file, "wb") as f:
                f.write(der)
            r = subprocess.run(["openssl", "dgst", "-sha256", "-verify", self.pub, "-signature", sig_file],
                               input=signing_input.encode(), capture_output=True)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_der_raw_round_trip(self):
        raw = bytes([0x00, 0x80] + [1] * 30) + bytes([0xFF] * 32)
        self.assertEqual(asc.der_to_raw(asc.raw_to_der(raw)), raw)
        raw = bytes(range(1, 33)) + bytes(range(33, 65))
        self.assertEqual(asc.der_to_raw(asc.raw_to_der(raw)), raw)

    def test_missing_env(self):
        env = {k: v for k, v in os.environ.items() if not k.startswith("ASC_")}
        old = os.environ
        try:
            os.environ = env
            with self.assertRaises(SystemExit) as cm:
                asc.client_from_env()
            self.assertIn("ASC_KEY_ID", str(cm.exception))
        finally:
            os.environ = old

    def test_usage(self):
        self.assertEqual(asc.main([]), 2)
        self.assertEqual(asc.main(["register-bundle-id", "only-one"]), 2)


if __name__ == "__main__":
    unittest.main()
