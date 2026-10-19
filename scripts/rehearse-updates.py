#!/usr/bin/env python3
"""Prepare isolated signed app/feed fixtures, or serve them on loopback.

Quit the installed Utter and obtain consent for a throwaway signing keychain
before using this. The caller owns that keychain's creation and deletion.
"""
import argparse
import functools
import http.server
import json
import plistlib
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "com.opentype.voiceinput.rehearsal.20261019"
APP_NAME = "Utter Rehearsal.app"


def run(*args, **kwargs):
    return subprocess.run([str(a) for a in args], check=True, **kwargs)


def prepare(work, keychain, port):
    work.mkdir(parents=True, exist_ok=False, mode=0o700)
    tools = ROOT / ".build/artifacts/sparkle/Sparkle/bin"
    run("swift", ROOT / "scripts/tests/ed25519_fixture.swift", work / "keys",
        stdout=subprocess.DEVNULL)
    for path in (work / "keys").iterdir():
        path.chmod(0o600)
    seed = (work / "keys/seed.txt").read_bytes()
    other_seed = (work / "keys/other-seed.txt").read_bytes()
    public = (work / "keys/public.txt").read_text()
    home = work / "home"
    home.mkdir()
    environment = {"CFFIXED_USER_HOME": str(home), "HF_HOME": str(home / "huggingface"),
                   "HF_HUB_CACHE": str(home / "huggingface/hub")}
    prefs = home / "Library/Preferences"
    prefs.mkdir(parents=True)
    (prefs / f"{BUNDLE_ID}.plist").write_bytes(plistlib.dumps({
        "hasCompletedOnboarding": True, "hotkeyAccessibilityPrompted": True,
        "preloadSpeechModelOnLaunch": False, "preloadFormattingModelOnLaunch": False,
        "automaticUpdateChecks": True, "developerInterfaceEnabled": False,
        "uiLanguage": "en",
    }))
    template = plistlib.loads((ROOT / "Resources/UpdateInfo.plist").read_bytes())
    template.update(SUFeedURL=f"http://127.0.0.1:{port}/appcast.xml", SUPublicEDKey=public)
    (work / "UpdateInfo.plist").write_bytes(plistlib.dumps(template))
    (work / "notes.txt").write_text('Fix A & B\nAdd <C> "D"\n隔离更新演练\n')

    def sign(path, key=seed, detached=False):
        args = [tools / "sign_update", "--ed-key-file", "-"]
        if detached:
            args.append("-p")
        return run(*args, path, input=key, stdout=subprocess.PIPE).stdout.decode().strip()

    def feed(name, version, dmg, signature, base=None, signed=True):
        args = ["python3", ROOT / "scripts/generate-appcast.py", "--tag", f"v{version}",
                "--version", version, "--app-plist",
                work / version / APP_NAME / "Contents/Info.plist", "--dmg", dmg,
                "--signature", signature, "--release-notes", work / "notes.txt",
                "--enclosure-url-base", base or f"http://127.0.0.1:{port}",
                "--output", work / "feed" / f"{name}.xml"]
        run(*args, stdout=subprocess.DEVNULL)
        if signed:
            sign(work / "feed" / f"{name}.xml")

    (work / "feed").mkdir()
    for version, name in (("0.0.55", "older"), ("0.0.56", "same"), ("0.0.57", "newer")):
        stage = work / version
        stage.mkdir()
        app = stage / APP_NAME
        run("ditto", ROOT / "dist/Utter.app", app)
        path = app / "Contents/Info.plist"
        info = plistlib.loads(path.read_bytes())
        info.update(template)
        info.update(CFBundleIdentifier=BUNDLE_ID, CFBundleName="Utter Rehearsal",
                    CFBundleDisplayName="Utter Rehearsal", SUBundleName="Utter Rehearsal",
                    CFBundleShortVersionString=version, CFBundleVersion=version,
                    LSEnvironment=environment)
        path.write_bytes(plistlib.dumps(info))
        framework = app / "Contents/Frameworks/Sparkle.framework/Versions/B"
        for component in (framework / "Autoupdate", framework / "Updater.app", framework.parent.parent,
                          app / "Contents/MacOS/opentype-cli"):
            run("codesign", "--keychain", keychain, "--force", "--options", "runtime",
                "--sign", "Utter Rehearsal Signing", component)
        run("codesign", "--keychain", keychain, "--force", "--options", "runtime",
            "--sign", "Utter Rehearsal Signing", "--entitlements",
            ROOT / "Resources/OpenType.entitlements", app)
        run("codesign", "--verify", "--deep", "--strict", app)
        archive = work / "feed" / f"v{version}"
        archive.mkdir()
        dmg = archive / f"Utter-{version}.dmg"
        run("hdiutil", "create", "-quiet", "-fs", "APFS", "-format", "UDZO",
            "-srcfolder", stage, dmg)
        signature = sign(dmg, detached=True)
        feed(name, version, dmg, signature)
        if name == "newer":
            feed("bad-signature", version, dmg, sign(dmg, other_seed, detached=True))
            feed("unsigned", version, dmg, signature, signed=False)
            tampered = work / "feed/tampered/v0.0.57/Utter-0.0.57.dmg"
            tampered.parent.mkdir(parents=True)
            shutil.copyfile(dmg, tampered)
            with tampered.open("ab") as handle:
                handle.write(b"tampered")
            feed("tampered", version, tampered, signature, f"http://127.0.0.1:{port}/tampered")
    install = work / "installed" / APP_NAME
    install.parent.mkdir()
    run("ditto", work / "0.0.56" / APP_NAME, install)
    shutil.copyfile(work / "feed/same.xml", work / "feed/appcast.xml")
    (work / "manifest.json").write_text(json.dumps({
        "bundle_id": BUNDLE_ID, "app": str(install), "home": str(home),
        "feed": template["SUFeedURL"], "production_identity_used": False,
    }, indent=2) + "\n")
    print(f"Prepared {install}")


def serve(work, port):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def end_headers(self):
            self.send_header("Cache-Control", "no-store")
            super().end_headers()

        def log_message(self, message, *args):
            with (work / "requests.jsonl").open("a") as handle:
                handle.write(json.dumps({"time": time.time(), "request": self.requestline,
                                         "headers": dict(self.headers), "result": message % args}) + "\n")

    handler = functools.partial(Handler, directory=str(work / "feed"))
    print(f"Serving http://127.0.0.1:{port}/appcast.xml", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "serve"))
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--keychain", type=Path)
    parser.add_argument("--port", type=int, default=18739)
    args = parser.parse_args()
    work = args.work.resolve()
    if args.action == "prepare":
        if subprocess.run(["pgrep", "-f", "^/Applications/Utter.app/Contents/MacOS/Utter$"]
                          ).returncode == 0:
            parser.error("quit the installed Utter before preparing a rehearsal")
        if not args.keychain or not args.keychain.is_file():
            parser.error("prepare requires an existing throwaway --keychain")
        prepare(work, args.keychain.resolve(), args.port)
    else:
        serve(work, args.port)
