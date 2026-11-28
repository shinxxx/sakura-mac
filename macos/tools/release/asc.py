#!/usr/bin/env python3
"""第 37 步：App Store Connect API 的小工具（只用 Python 标准库和系统的 openssl）。

用 API 密钥（.p8）签一个 JWT 去调用 App Store Connect API，不用 Apple ID 的密码。
密钥和编号从环境变量读（release.sh 从 ~/.config/sakura-mac/signing.env 读进来）：
  ASC_KEY_ID      密钥 ID（10 个字母数字）
  ASC_ISSUER_ID   Issuer ID
  ASC_KEY_PATH    .p8 文件的路径（放在仓库外，如 ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8）

  asc.py check                                  确认密钥能用
  asc.py register-bundle-id BUNDLE_ID NAME      注册 macOS 的 Bundle ID（已有时什么也不做）
  asc.py app-id BUNDLE_ID                       App Store Connect 里 App 记录的 ID（没有时返回 3）
  asc.py wait-build BUNDLE_ID BUILD [秒]        等上传的构建处理完（VALID 时返回 0）
  asc.py setup-internal-testing BUNDLE_ID       建 TestFlight 的内部测试组（所有构建自动可用），把团队的成员加进去

不打印密钥的内容，也不打印成员的邮件地址。
"""
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com"
GROUP_NAME = "Sakura 内部テスト"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der, size=32):
    """openssl 输出的 ECDSA 签名（DER 的 SEQUENCE{INTEGER r, INTEGER s}）→ JWT 用的 r||s（各 32 字节）。"""
    if der[0] != 0x30:
        raise ValueError("不是 DER 的 SEQUENCE")
    pos = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    out = b""
    for _ in range(2):
        if der[pos] != 0x02:
            raise ValueError("不是 DER 的 INTEGER")
        n = der[pos + 1]
        value = der[pos + 2:pos + 2 + n].lstrip(b"\x00")
        if len(value) > size:
            raise ValueError("整数太长")
        out += value.rjust(size, b"\x00")
        pos += 2 + n
    return out


def raw_to_der(raw):
    """der_to_raw 的反过来（测试里用 openssl 验证签名）。"""
    half = len(raw) // 2
    parts = b""
    for v in (raw[:half], raw[half:]):
        v = v.lstrip(b"\x00") or b"\x00"
        if v[0] & 0x80:
            v = b"\x00" + v
        parts += bytes([0x02, len(v)]) + v
    return bytes([0x30, len(parts)]) + parts


def make_jwt(key_id, issuer_id, key_path, now=None, lifetime=1200):
    now = int(now if now is not None else time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer_id, "iat": now, "exp": now + lifetime, "aud": "appstoreconnect-v1"}
    signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "." +
                     b64url(json.dumps(payload, separators=(",", ":")).encode()))
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", os.path.expanduser(key_path)],
                         input=signing_input.encode(), capture_output=True, check=True).stdout
    return signing_input + "." + b64url(der_to_raw(der))


class Client:
    def __init__(self, key_id, issuer_id, key_path):
        self.token = make_jwt(key_id, issuer_id, key_path)

    def request(self, method, path, body=None, params=None):
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", "Bearer " + self.token)
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as res:
                text = res.read()
                return json.loads(text) if text else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            try:
                errors = json.loads(detail).get("errors", [])
                detail = "; ".join(f"{x.get('title', '')}: {x.get('detail', '')}" for x in errors) or detail
            except ValueError:
                pass
            raise SystemExit(f"App Store Connect API 出错（{method} {path}，HTTP {e.code}）：{detail}")

    def get(self, path, **params):
        return self.request("GET", path, params=params)

    def post(self, path, body):
        return self.request("POST", path, body=body)


def client_from_env():
    missing = [k for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not os.environ.get(k)]
    if missing:
        raise SystemExit("缺少环境变量：" + "、".join(missing) + "（见 macos/tools/release/signing.env.example）")
    path = os.path.expanduser(os.environ["ASC_KEY_PATH"])
    if not os.path.isfile(path):
        raise SystemExit(f"没有 API 密钥文件：{path}")
    return Client(os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], path)


def find_app(c, bundle_id):
    apps = c.get("/v1/apps", **{"filter[bundleId]": bundle_id, "limit": 10}).get("data", [])
    for a in apps:
        if a["attributes"].get("bundleId") == bundle_id:
            return a
    return None


def cmd_check(c, _args):
    c.get("/v1/apps", limit=1)
    print("API 密钥可以使用")
    return 0


def cmd_register_bundle_id(c, args):
    bundle_id, name = args[0], args[1]
    found = c.get("/v1/bundleIds", **{"filter[identifier]": bundle_id, "limit": 50}).get("data", [])
    for b in found:
        if b["attributes"].get("identifier") == bundle_id:
            print(f"Bundle ID 已注册：{bundle_id}（{b['attributes'].get('platform')}）")
            return 0
    c.post("/v1/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": bundle_id, "name": name, "platform": "MAC_OS"}}})
    print(f"已注册 Bundle ID：{bundle_id}")
    return 0


def cmd_app_id(c, args):
    app = find_app(c, args[0])
    if not app:
        print(f"App Store Connect 里还没有 Bundle ID 是 {args[0]} 的 App 记录")
        return 3
    print(app["id"])
    return 0


def cmd_wait_build(c, args):
    bundle_id, build = args[0], args[1]
    timeout = int(args[2]) if len(args) > 2 else 3600
    app = find_app(c, bundle_id)
    if not app:
        print(f"App Store Connect 里没有 {bundle_id} 的 App 记录")
        return 3
    deadline = time.time() + timeout
    last = None
    while True:
        builds = c.get("/v1/builds", **{"filter[app]": app["id"], "filter[version]": build,
                                        "filter[preReleaseVersion.platform]": "MAC_OS", "limit": 5}).get("data", [])
        state = builds[0]["attributes"].get("processingState") if builds else "NOT_FOUND"
        if state != last:
            print(f"构建 {build}：{state}", flush=True)
            last = state
        if state == "VALID":
            return 0
        if state in ("FAILED", "INVALID"):
            return 1
        if time.time() > deadline:
            print(f"等了 {timeout} 秒还没处理完")
            return 2
        time.sleep(30)


def cmd_setup_internal_testing(c, args):
    app = find_app(c, args[0])
    if not app:
        print(f"App Store Connect 里没有 {args[0]} 的 App 记录")
        return 3
    groups = c.get("/v1/betaGroups", **{"filter[app]": app["id"], "limit": 50}).get("data", [])
    group = next((g for g in groups if g["attributes"].get("isInternalGroup")
                  and g["attributes"].get("name") == GROUP_NAME), None)
    if not group:
        group = c.post("/v1/betaGroups", {"data": {"type": "betaGroups", "attributes": {
            "name": GROUP_NAME, "isInternalGroup": True, "hasAccessToAllBuilds": True},
            "relationships": {"app": {"data": {"type": "apps", "id": app["id"]}}}}})["data"]
        print(f"已建内部测试组「{GROUP_NAME}」（所有构建自动可用）")
    else:
        print(f"内部测试组「{GROUP_NAME}」已存在")
    existing = c.get(f"/v1/betaGroups/{group['id']}/betaTesters", limit=200).get("data", [])
    have = {t["attributes"].get("email", "").lower() for t in existing}
    users = c.get("/v1/users", limit=200).get("data", [])
    added = 0
    for u in users:
        a = u["attributes"]
        email = a.get("username", "")
        if not email or email.lower() in have:
            continue
        c.post("/v1/betaTesters", {"data": {"type": "betaTesters", "attributes": {
            "email": email, "firstName": a.get("firstName", ""), "lastName": a.get("lastName", "")},
            "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": group["id"]}]}}}})
        added += 1
    print(f"测试者：原有 {len(existing)} 位，新加 {added} 位")
    return 0


COMMANDS = {
    "check": (cmd_check, 0),
    "register-bundle-id": (cmd_register_bundle_id, 2),
    "app-id": (cmd_app_id, 1),
    "wait-build": (cmd_wait_build, 2),
    "setup-internal-testing": (cmd_setup_internal_testing, 1),
}


def main(argv):
    if len(argv) < 1 or argv[0] not in COMMANDS or len(argv) - 1 < COMMANDS[argv[0]][1]:
        print(__doc__)
        return 2
    func, _ = COMMANDS[argv[0]]
    return func(client_from_env(), argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
