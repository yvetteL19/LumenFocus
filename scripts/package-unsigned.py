#!/usr/bin/env python3
"""Validate and package an internal-test build. Never signs, uploads, or creates a tag."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("release_checks", Path(__file__).with_name("validate-release.py"))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", required=True, type=Path, help="Built .app or .xcarchive")
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--version")
    parser.add_argument("--build")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="lumen-unsigned-", dir=args.output) as temporary:
        temporary = Path(temporary)
        report_path = temporary / "validation.json"
        options = ["--app", str(args.app), "--report", str(report_path)]
        for name in ("version", "build"):
            if getattr(args, name):
                options.extend([f"--{name}", getattr(args, name)])
        if checks.main(options):
            return 1
        report = json.loads(report_path.read_text())
        product = report["product"]
        name = f"LumenFocus-{product['version']}-{product['build']}-unsigned-not-for-distribution"
        archive = args.output / f"{name}.zip"
        checksum = archive.with_suffix(".zip.sha256")
        checks.require(not archive.exists() and not checksum.exists(), f"Refusing to replace existing artifact: {archive}")
        stage = temporary / name
        stage.mkdir()
        app, _ = checks.resolve_product(args.app)
        copied = stage / app.name
        subprocess.run(["ditto", str(app), str(copied)], check=True)
        copied_hashes = {str(file.relative_to(copied)): hashlib.sha256(file.read_bytes()).hexdigest()
                         for file in sorted(copied.rglob("*")) if file.is_file()}
        checks.require(copied_hashes == product["sha256"], "Copied app differs from validated product")
        report_path.rename(stage / "validation.json")
        (stage / "README.txt").write_text(
            "LumenFocus — UNSIGNED INTERNAL TEST BUILD — NOT FOR DISTRIBUTION\n\n"
            "This package has not passed App Store signing, provisioning, upload, or review.\n"
            "It is not a TestFlight or customer installer. No signing identity was applied by this tool.\n"
            "validation.json records local checks and SHA-256 hashes of every app file.\n"
            "The companion .zip.sha256 checks the downloaded archive; it is not a code signature.\n"
            "Automated checks do not establish physical-device behavior or App Store eligibility.\n")
        staged_zip = temporary / "artifact.zip"
        subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(stage), str(staged_zip)], check=True)
        digest = hashlib.sha256(staged_zip.read_bytes()).hexdigest()
        staged_zip.rename(archive)
        checksum.write_text(f"{digest}  {archive.name}\n")
        print(f"Created internal-test artifact: {archive}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (checks.ValidationError, OSError, subprocess.SubprocessError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
