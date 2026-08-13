#!/usr/bin/env python3
"""PassOne build pipeline: environment check + release builds.

Checks the toolchain and reports what is present and what is missing, then
builds the Go server, the Flutter app (Linux + Android), and the Linux
AppImage. Output artifacts land in server/dist/.

Usage:
  python3 scripts/build.py                 # full pipeline
  python3 scripts/build.py --check-only    # only the environment report
  python3 scripts/build.py --no-apk        # skip the Android build
  python3 scripts/build.py --no-appimage   # skip the AppImage
  python3 scripts/build.py --no-server     # skip the Go server
  python3 scripts/build.py --no-linux      # skip the Linux release bundle
  python3 scripts/build.py --download-tools  # fetch appimagetool if missing
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"
SERVER = ROOT / "server"
DIST = SERVER / "dist"
TOOLS = ROOT / "tools"

VERSION = "2.1.0"
APPDIR_NAME = f"passone-appdir"
APPIMAGE_URL = (
    "https://github.com/AppImage/appimagetool/releases/download/continuous/"
    "appimagetool-x86_64.AppImage"
)
APPIMAGE_BIN = TOOLS / "appimagetool-x86_64.AppImage"

HOME = Path.home()
FLUTTER_CANDIDATES = [
    shutil.which("flutter"),
    str(HOME / "flutter/flutter/bin/flutter"),
    str(HOME / "flutter/bin/flutter"),
]


class Check:
    def __init__(self, name, cmd, version_re=None, on_stderr=False, hint=""):
        self.name = name
        self.cmd = cmd
        self.version_re = version_re
        self.on_stderr = on_stderr
        self.hint = hint
        self.ok = False
        self.version = ""
        self.extra = ""
        # When True the result set before run() is preserved (used by checks
        # whose outcome depends on filesystem state, e.g. the Android SDK).
        self.locked = False

    def run(self):
        try:
            p = subprocess.run(
                self.cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
            out = p.stderr if self.on_stderr else p.stdout
            first = out.strip().splitlines()[0] if out.strip() else ""
            if self.version_re:
                m = re.search(self.version_re, first)
                if m:
                    self.version = m.group(1)
                    self.ok = True
            else:
                self.ok = self.ok if self.locked else p.returncode == 0
            if not self.extra:
                self.extra = first
        except (OSError, subprocess.SubprocessError):
            self.ok = False
        return self.ok


def resolve_flutter():
    for c in FLUTTER_CANDIDATES:
        if c and Path(c).exists():
            return c
    return None


def find_android_sdk():
    lprops = APP / "android" / "local.properties"
    if lprops.exists():
        for line in lprops.read_text().splitlines():
            if line.startswith("sdk.dir="):
                return Path(line.split("=", 1)[1].strip())
    env = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    return Path(env) if env else None


def run(cmd, cwd=None, env=None, check=True):
    print(f"\n$ {' '.join(str(c) for c in cmd)}")
    e = dict(os.environ)
    if env:
        e.update(env)
    r = subprocess.run([str(c) for c in cmd], cwd=cwd, env=e)
    if check and r.returncode != 0:
        sys.exit(f"FAILED (exit {r.returncode}): {' '.join(str(c) for c in cmd)}")
    return r


def check_environment():
    flutter = resolve_flutter()
    sdk = find_android_sdk()

    checks = [
        Check("git", ["git", "--version"], r"git version (\S+)"),
        Check("gh", ["gh", "--version"], r"gh version (\S+)"),
        Check("go", ["go", "version"], r"go([\d.]+)"),
    ]
    if flutter:
        checks.append(Check("flutter", [flutter, "--version"], r"Flutter ([\d.]+)"))
        checks.append(
            Check("dart", [str(Path(flutter).parent / "dart"), "--version"],
                  r"([\d.]+)")
        )
    else:
        checks.append(Check("flutter", ["flutter", "--version"],
                            r"Flutter ([\d.]+)", hint="install Flutter"))
    checks += [
        Check("java", ["java", "-version"], r'"?([\d.]+)', on_stderr=True),
        Check("cmake", ["cmake", "--version"], r"cmake version (\S+)"),
        Check("ninja", ["ninja", "--version"], r"(\S+)"),
        Check("clang", ["clang", "--version"], r"clang version (\S+)"),
        Check("gtk+-3.0 (pkg-config)",
              ["pkg-config", "--modversion", "gtk+-3.0"], r"(\S+)"),
    ]

    if sdk:
        platforms = sdk / "platforms"
        build_tools = sdk / "build-tools"
        apis = sorted(p.name for p in platforms.glob("android-*")) if platforms.exists() else []
        tools = sorted(p.name for p in build_tools.iterdir()) if build_tools.exists() else []
        c = Check("Android SDK", ["true"])
        c.ok = bool(apis) and bool(tools)
        c.locked = True
        c.extra = f"{sdk} (API {','.join(apis)} | build-tools {','.join(tools)})"
        if not c.ok:
            c.hint = "SDK found but missing platforms or build-tools"
        checks.append(c)
    else:
        checks.append(Check("Android SDK", ["true"],
                            hint="set sdk.dir in app/android/local.properties"))

    if APPIMAGE_BIN.exists():
        checks.append(Check("appimagetool", ["true"]))
        checks[-1].ok = True
        checks[-1].extra = str(APPIMAGE_BIN)
    else:
        checks.append(Check("appimagetool", ["true"],
                            hint="run with --download-tools"))

    print("\nEnvironment check\n" + "-" * 72)
    failed = []
    for c in checks:
        c.run()
        marker = "[ OK ]" if c.ok else "[FAIL]"
        line = f"  {marker} {c.name:<24} {c.version or c.extra}"
        if not c.ok and c.hint:
            line += f"   (missing: {c.hint})"
        print(line.rstrip())
        if not c.ok:
            failed.append(c.name)

    print("-" * 72)
    if failed:
        print(f"Missing tools: {', '.join(failed)}")
    else:
        print("All tools present.")
    return failed


def build_server():
    print("\n== Building Go server ==")
    DIST.mkdir(parents=True, exist_ok=True)
    run(["go", "build", "-trimpath", "-ldflags=-s -w",
         "-o", DIST / "passone-server-linux-x64", "./cmd/passone"],
        cwd=SERVER)


def build_linux(flutter):
    print("\n== Building Flutter Linux release ==")
    run([flutter, "gen-l10n"], cwd=APP)
    run([flutter, "build", "linux", "--release"], cwd=APP)


def build_apk(flutter, sdk):
    print("\n== Building Flutter Android release APK ==")
    env = {"ANDROID_HOME": str(sdk), "ANDROID_SDK_ROOT": str(sdk)} if sdk else None
    run([flutter, "build", "apk", "--release"], cwd=APP, env=env)


def package_artifacts():
    print("\n== Packaging artifacts ==")
    DIST.mkdir(parents=True, exist_ok=True)
    bundle = APP / "build/linux/x64/release/bundle"
    if not bundle.exists():
        sys.exit("Linux bundle not found; run the Linux build first")
    tar = DIST / f"passone-linux-x64-{VERSION}.tar.gz"
    with tarfile.open(tar, "w:gz") as tf:
        tf.add(bundle, arcname="bundle")
    print(f"  {tar}")

    apk = APP / "build/app/outputs/flutter-apk/app-release.apk"
    if apk.exists():
        dst = DIST / f"passone-android-{VERSION}.apk"
        shutil.copyfile(apk, dst)
        print(f"  {dst}")


def build_appimage():
    print("\n== Building AppImage ==")
    if not APPIMAGE_BIN.exists():
        print("  appimagetool missing, skipping (use --download-tools)")
        return
    bundle = APP / "build/linux/x64/release/bundle"
    icon = APP / "assets/icon/app_icon.png"
    if not bundle.exists():
        sys.exit("Linux bundle not found; run the Linux build first")

    appdir = Path(tempfile.mkdtemp(prefix="passone-appdir-"))
    usr_lib = appdir / "usr/lib/passone"
    shutil.copytree(bundle, usr_lib)
    shutil.copyfile(icon, appdir / "passone.png")
    (appdir / "usr/share/applications").mkdir(parents=True, exist_ok=True)
    (appdir / "usr/share/icons/hicolor/256x256/apps").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(icon, appdir / "usr/share/icons/hicolor/256x256/apps/passone.png")

    (appdir / "AppRun").write_text(
        '#!/bin/sh\n'
        'SELF="$(readlink -f "$0")"\n'
        'HERE="${SELF%/*}"\n'
        'export LD_LIBRARY_PATH="$HERE/usr/lib/passone/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"\n'
        'exec "$HERE/usr/lib/passone/passone_app" "$@"\n'
    )
    (appdir / "AppRun").chmod(0o755)
    (appdir / "passone.desktop").write_text(
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=PassOne\n"
        "GenericName=Password manager\n"
        "Comment=Store passwords, TOTP secrets and SSH keys\n"
        "Icon=passone\n"
        "Exec=passone\n"
        "Terminal=false\n"
        "Categories=Utility;Security;\n"
        "StartupNotify=false\n"
    )

    out = DIST / f"passone-{VERSION}-x86_64.AppImage"
    run([APPIMAGE_BIN, "--appimage-extract-and-run",
         appdir, out], cwd=ROOT)
    print(f"  {out}")
    shutil.rmtree(appdir, ignore_errors=True)


def download_tools():
    print("\n== Downloading appimagetool ==")
    TOOLS.mkdir(parents=True, exist_ok=True)
    run(["curl", "-sL", "-o", APPIMAGE_BIN, APPIMAGE_URL])
    APPIMAGE_BIN.chmod(0o755)


def main():
    ap = argparse.ArgumentParser(description="PassOne build pipeline")
    ap.add_argument("--check-only", action="store_true",
                    help="only print the environment report")
    ap.add_argument("--no-server", action="store_true")
    ap.add_argument("--no-linux", action="store_true")
    ap.add_argument("--no-apk", action="store_true")
    ap.add_argument("--no-appimage", action="store_true")
    ap.add_argument("--download-tools", action="store_true",
                    help="download appimagetool if missing")
    args = ap.parse_args()

    failed = check_environment()
    flutter = resolve_flutter()
    sdk = find_android_sdk()

    if args.download_tools:
        download_tools()

    if args.check_only:
        return

    if not args.no_server:
        if "go" not in failed:
            build_server()
        else:
            print("Skipping server build: go missing")

    if not (args.no_linux and args.no_apk):
        if flutter is None:
            print("Skipping Flutter builds: flutter missing")
        else:
            if not args.no_linux:
                build_linux(flutter)
            if not args.no_apk:
                if sdk is None:
                    print("Skipping APK build: Android SDK not found")
                else:
                    build_apk(flutter, sdk)
            package_artifacts()

    if not args.no_appimage:
        build_appimage()

    print("\nDone. Artifacts in server/dist/:\n")
    for f in sorted(DIST.glob("*")):
        print(f"  {f.name}  ({f.stat().st_size // 1024} KiB)")
    print()


if __name__ == "__main__":
    main()
