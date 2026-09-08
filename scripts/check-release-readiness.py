#!/usr/bin/env python3
"""Check release sources; --live also verifies public App Review destinations."""
from pathlib import Path
from html.parser import HTMLParser
import argparse
import plistlib
import urllib.request
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
BASE = "https://wrexist.github.io/Airline-Empire/"
parser = argparse.ArgumentParser()
parser.add_argument("--live", action="store_true")
args = parser.parse_args()
errors = []
manifest = plistlib.loads((ROOT / "AirlineEmpireApp/Resources/PrivacyInfo.xcprivacy").read_bytes())
reasons = {entry["NSPrivacyAccessedAPIType"]: entry["NSPrivacyAccessedAPITypeReasons"]
           for entry in manifest["NSPrivacyAccessedAPITypes"]}
if "CA92.1" not in reasons.get("NSPrivacyAccessedAPICategoryUserDefaults", []):
    errors.append("Missing private UserDefaults reason CA92.1")

class Links(HTMLParser):
    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ("href", "src") and value and not urllib.parse.urlparse(value).scheme:
                target = (ROOT / "site" / value.split("#")[0]).resolve()
                if not target.exists():
                    errors.append(f"Broken local site link: {value}")

for name in ("index", "privacy", "support", "terms"):
    text = (ROOT / f"site/{name}.html").read_text()
    if "REPLACE_ME" in text:
        errors.append(f"Placeholder in {name}.html")
    Links().feed(text)
for locale in ("en-US", "en-GB"):
    for kind, suffix in (("privacy", "privacy.html"), ("support", "support.html"), ("marketing", "")):
        actual = (ROOT / f"store/metadata/{locale}/{kind}_url.txt").read_text().strip()
        if actual != BASE + suffix:
            errors.append(f"Wrong {locale} {kind} URL: {actual}")
paywall = (ROOT / "AirlineEmpireCore/Sources/AirlineEmpireCore/Monetization/PaywallContent.swift").read_text()
for page in ("terms.html", "privacy.html"):
    if BASE + page not in paywall:
        errors.append(f"Paywall does not link to {page}")
if args.live:
    for page in ("", "privacy.html", "support.html", "terms.html"):
        try:
            with urllib.request.urlopen(BASE + page, timeout=15) as response:
                text = response.read().decode()
                if response.status != 200 or "Airline Empire" not in text or "<h1>" not in text:
                    errors.append(f"Invalid public page: {BASE + page}")
        except Exception as error:
            errors.append(f"Unreachable public page {BASE + page}: {error}")
for error in errors:
    print("FAIL:", error)
print(f"Release source checks: {'FAILED' if errors else 'passed'}")
raise SystemExit(bool(errors))
