import base64, hashlib, hmac, json, time, unittest
from backend.reports import web_auth

KEY = b"k" * 32


def make(claims, key=KEY, alg="HS256"):
    b = lambda d: base64.urlsafe_b64encode(json.dumps(d).encode()).rstrip(b"=").decode()
    h, p = b({"alg": alg, "typ": "JWT"}), b(claims)
    sig = base64.urlsafe_b64encode(hmac.new(key, f"{h}.{p}".encode(), hashlib.sha256).digest()).rstrip(b"=").decode()
    return f"{h}.{p}.{sig}"


class VerifyJwt(unittest.TestCase):
    def ok(self, **over):
        return {"exp": time.time() + 300, "token_type": "access", **over}

    def test_valid(self):
        self.assertEqual(web_auth.verify_jwt(make(self.ok(user_id="u")), KEY)["user_id"], "u")

    def test_rejects(self):
        for name, tok in {
            "bad sig": make(self.ok(), key=b"x" * 32),
            "expired": make(self.ok(exp=time.time() - 600)),
            "no exp": make({"token_type": "access"}),
            "not access": make(self.ok(token_type="refresh")),
            "nbf future": make(self.ok(nbf=time.time() + 600)),
            "alg none": make(self.ok(), alg="none"),
            "garbage": "abc",
        }.items():
            with self.subTest(name), self.assertRaises(ValueError):
                web_auth.verify_jwt(tok, KEY)


class Framed(unittest.TestCase):
    def test_pages_only_in_iframe(self):
        self.assertTrue(web_auth.framed("iframe", asset=False))
        for dest in (None, "", "document", "frame", "empty", "script"):
            with self.subTest(dest):
                self.assertFalse(web_auth.framed(dest, asset=False))

    def test_assets_only_as_subresources(self):
        for dest in ("script", "style", "image", "empty"):
            with self.subTest(dest):
                self.assertTrue(web_auth.framed(dest, asset=True))
        for dest in (None, "", "document", "iframe"):
            with self.subTest(dest):
                self.assertFalse(web_auth.framed(dest, asset=True))


if __name__ == "__main__":
    unittest.main()
