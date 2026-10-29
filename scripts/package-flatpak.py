#!/usr/bin/env python3
"""Build a Flatpak bundle on Linux without a compiler or a separate application server."""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
APP_ID = "io.github.buddy.SpelunkrGuide"


def run(*args):
    subprocess.run(args, check=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", default="51", help="GNOME Platform branch")
    parser.add_argument("--output", type=Path, default=ROOT / "dist/spelunkr-guide-x86_64.flatpak")
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="spelunkr-flatpak-") as temporary:
        work = Path(temporary)
        build = work / "app"
        files = build / "files"
        share = files / "share" / APP_ID
        share.mkdir(parents=True)
        shutil.copytree(ROOT / "web", share / "web")
        shutil.copy2(ROOT / "clients/linux/main.py", share / "main.py")
        shutil.copy2(ROOT / "PROVENANCE.md", share / "PROVENANCE.md")
        for folder, source, destination in [
            ("applications", f"clients/linux/{APP_ID}.desktop", f"{APP_ID}.desktop"),
            ("metainfo", f"clients/linux/{APP_ID}.metainfo.xml", f"{APP_ID}.metainfo.xml"),
            ("icons/hicolor/scalable/apps", "web/icon.svg", f"{APP_ID}.svg"),
        ]:
            directory = files / "share" / folder
            directory.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / source, directory / destination)
        (files / "bin").mkdir()
        launcher = files / "bin/spelunkr-guide"
        launcher.write_text(f'#!/bin/sh\nexec python3 /app/share/{APP_ID}/main.py "$@"\n')
        for path in files.rglob("*"):
            path.chmod(0o755 if path.is_dir() else 0o644)
        launcher.chmod(0o755)
        (build / "metadata").write_text(
            f"[Application]\nname={APP_ID}\nruntime=org.gnome.Platform/x86_64/{args.runtime}\n"
            f"sdk=org.gnome.Sdk/x86_64/{args.runtime}\ncommand=spelunkr-guide\n"
        )
        run("flatpak", "build-finish", "--share=network", "--share=ipc", "--socket=wayland",
            "--socket=fallback-x11", "--socket=pulseaudio", "--device=dri", str(build))
        repository = work / "repository"
        run("flatpak", "build-export", "--disable-sandbox", str(repository), str(build), "stable")
        run("flatpak", "build-bundle", "--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo",
            str(repository), str(args.output.resolve()), APP_ID, "stable")
    print(f"Built {args.output}")


if __name__ == "__main__":
    main()
