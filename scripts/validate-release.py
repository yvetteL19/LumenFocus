#!/usr/bin/env python3
"""Read-only local release checks. A passing result never grants App Store approval."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path("LumenFocus/LumenFocus")
LOCALES = ("en", "zh-Hans")
BUNDLE_ID = "Yvette.LumenFocus"
MIN_OS = "13.0"


class ValidationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise ValidationError(message)


def read_plist(path):
    try:
        value = plistlib.loads(path.read_bytes())
        require(isinstance(value, dict), f"{path}: expected a plist dictionary")
        return value
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise ValidationError(f"{path}: invalid or missing plist ({error})") from error


def decode_quoted(token):
    """Apple .strings quoted string escapes (also used for simple Swift literals)."""
    def escape(match):
        value = match.group(1)
        if value.startswith(("U", "u")) and len(value) == 5:
            return chr(int(value[1:], 16))
        escapes = {"n": "\n", "r": "\r", "t": "\t", '"': '"', "\\": "\\"}
        require(value in escapes, f"Unsupported string escape: \\{value}")
        return escapes[value]
    return re.sub(r"\\([Uu][0-9a-fA-F]{4}|.)", escape, token[1:-1])


def read_strings(path):
    raw = path.read_bytes()
    if raw.startswith((b"bplist", b"<?xml")):
        result = read_plist(path)
        require(all(isinstance(k, str) and isinstance(v, str) for k, v in result.items()),
                f"{path}: localization must contain string keys and values")
        return result
    text = raw.decode("utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig")
    token = re.compile(r'\s+|/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[=;]', re.S)
    tokens, offset = [], 0
    for match in token.finditer(text):
        require(not text[offset:match.start()].strip(), f"{path}: malformed .strings near offset {offset}")
        part = match.group()
        if not part.isspace() and not part.startswith(("//", "/*")):
            tokens.append(part)
        offset = match.end()
    require(not text[offset:].strip() and len(tokens) % 4 == 0, f"{path}: incomplete .strings entry")
    result = {}
    for index in range(0, len(tokens), 4):
        key, equal, value, semi = tokens[index:index + 4]
        require(key.startswith('"') and value.startswith('"') and equal == "=" and semi == ";",
                f"{path}: malformed .strings entry {index // 4 + 1}")
        key, value = decode_quoted(key), decode_quoted(value)
        require(key not in result, f"{path}: duplicate localization key {key!r}")
        require(bool(value.strip()), f"{path}: empty translation for {key!r}")
        result[key] = value
    require(bool(result), f"{path}: localization is empty")
    return result


def placeholders(value):
    """Compare argument position/type, permitting explicit translator reordering."""
    pattern = re.compile(r"%(?:(\d+)\$)?[-+#0 ']*(?:\d+)?(?:\.\d+)?(hh|ll|[hljztL])?([@diuoxXfFeEgGaAcCsSp])")
    arguments, index, next_argument = [], 0, 1
    while index < len(value):
        if value[index] != "%":
            index += 1
            continue
        if value[index:index + 2] == "%%":
            index += 2
            continue
        match = pattern.match(value, index)
        require(match is not None, f"Unsupported or unescaped format placeholder in {value!r}")
        position, length, kind = match.groups()
        require(position is None or int(position) > 0, f"Invalid argument position in {value!r}")
        arguments.append((int(position) if position else next_argument, (length or "") + kind))
        if not position:
            next_argument += 1
        index = match.end()
    return Counter(arguments)


def validate_locales(paths):
    tables = {locale: read_strings(path) for locale, path in paths.items()}
    base = tables["zh-Hans"]
    for locale, table in tables.items():
        require(table.keys() == base.keys(),
                f"{locale}: localization keys differ; missing={sorted(base.keys() - table.keys())}, "
                f"extra={sorted(table.keys() - base.keys())}")
        for key, value in table.items():
            require(placeholders(key) == placeholders(value), f"{locale}: format arguments differ for {key!r}")
    return tables


def version_tuple(value):
    require(isinstance(value, str) and re.fullmatch(r"\d+(?:\.\d+){0,2}", value), f"Invalid version: {value!r}")
    return tuple((list(map(int, value.split("."))) + [0, 0])[:3])


def expected_versions(root, version=None, build=None):
    project = (root / "LumenFocus/LumenFocus.xcodeproj/project.pbxproj").read_text()
    def setting(name):
        values = set(re.findall(rf"\b{name}\s*=\s*([^;]+);", project))
        require(len(values) == 1, f"{name}: expected one consistent project value; pass an explicit override if intentional")
        return values.pop().strip().strip('"')
    version, build = version or setting("MARKETING_VERSION"), build or setting("CURRENT_PROJECT_VERSION")
    version_tuple(version)
    version_tuple(build)
    return version, build


def validate_source(root):
    source = root / SOURCE
    info = read_plist(source / "Info.plist")
    for key, variable in (("CFBundleShortVersionString", "MARKETING_VERSION"), ("CFBundleVersion", "CURRENT_PROJECT_VERSION")):
        require(info.get(key) == f"$({variable})", f"Source {key} must use $({variable})")
    tables = validate_locales({locale: source / f"{locale}.lproj/Localizable.strings" for locale in LOCALES})
    # Explicit literal lookups only; arbitrary runtime-built keys and visible SwiftUI text need UI review.
    lookup = re.compile(r'\b(?:L|NSLocalizedString|LocalizedStringKey|localize)\(\s*("(?:\\.|[^"\\])*")')
    for swift in source.rglob("*.swift"):
        for match in lookup.finditer(swift.read_text()):
            literal = match.group(1)
            if "\\(" not in literal:
                key = decode_quoted(literal)
                require(key in tables["en"], f"{swift}: missing literal localization key {key!r}")
    icon_dir = source / "Assets.xcassets/AppIcon.appiconset"
    images = json.loads((icon_dir / "Contents.json").read_text()).get("images", [])
    require(len(images) == 10, "Expected all 10 macOS app icon representations")
    for entry in images:
        path = icon_dir / entry.get("filename", "")
        require(path.is_file(), f"Missing app icon: {path}")
        data = path.read_bytes()
        require(data.startswith(b"\x89PNG\r\n\x1a\n") and len(data) >= 24, f"Invalid PNG icon: {path}")
        pixels = int(entry["size"].split("x")[0]) * int(entry["scale"].removesuffix("x"))
        require(struct.unpack(">II", data[16:24]) == (pixels, pixels), f"Wrong icon dimensions: {path}")
    privacy = read_plist(source / "PrivacyInfo.xcprivacy")
    require(privacy.get("NSPrivacyTracking") is False and privacy.get("NSPrivacyTrackingDomains") == []
            and privacy.get("NSPrivacyCollectedDataTypes") == [], "Privacy manifest changed: review local-only claims")
    require(privacy.get("NSPrivacyAccessedAPITypes") == [{
        "NSPrivacyAccessedAPIType": "NSPrivacyAccessedAPICategoryUserDefaults",
        "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}], "Review declared required-reason APIs")
    entitlements = read_plist(source / "LumenFocus.entitlements")
    require(entitlements == {"com.apple.security.app-sandbox": True,
                             "com.apple.security.files.user-selected.read-write": True},
            "Source entitlements changed: review the minimal App Store permission baseline")
    return tables, privacy, entitlements


def macho_slices(path):
    """Read fat Mach-O headers and minimum macOS load commands without executing the app."""
    data = path.read_bytes()
    magic = data[:4]
    require(magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"), f"{path}: expected a universal Mach-O executable")
    count = struct.unpack_from(">I", data, 4)[0]
    require(0 < count <= 16, "Invalid universal architecture count")
    width, fmt = (32, ">IIQQII") if magic == b"\xca\xfe\xba\xbf" else (20, ">IIIII")
    result = {}
    for index in range(count):
        cpu, _, offset, size, *_ = struct.unpack_from(fmt, data, 8 + index * width)
        name = {0x01000007: "x86_64", 0x0100000C: "arm64"}.get(cpu, hex(cpu))
        require(name not in result and offset + size <= len(data), f"Invalid Mach-O slice {name}")
        chunk = data[offset:offset + size]
        require(chunk[:4] == b"\xcf\xfa\xed\xfe", f"{name}: expected little-endian 64-bit Mach-O")
        _, actual_cpu, _, file_type, commands, command_bytes, _, _ = struct.unpack_from("<8I", chunk)
        require(actual_cpu == cpu and file_type == 2, f"{name}: not an executable slice")
        require(commands <= 4096 and 32 + command_bytes <= len(chunk), f"{name}: truncated load commands")
        cursor, minimum = 32, None
        for _ in range(commands):
            command, length = struct.unpack_from("<II", chunk, cursor)
            require(length >= 8 and cursor + length <= 32 + command_bytes, f"{name}: invalid load command")
            if command == 0x32:
                require(length >= 24, f"{name}: invalid LC_BUILD_VERSION")
                platform, minimum = struct.unpack_from("<II", chunk, cursor + 8)
                require(platform == 1, f"{name}: executable is not built for macOS")
            elif command == 0x24:
                require(length >= 16, f"{name}: invalid LC_VERSION_MIN_MACOSX")
                minimum = struct.unpack_from("<I", chunk, cursor + 8)[0]
            cursor += length
        require(minimum is not None, f"{name}: missing minimum macOS load command")
        value = (minimum >> 16, (minimum >> 8) & 255, minimum & 255)
        require(value <= version_tuple(MIN_OS), f"{name}: binary requires macOS {value}, above declared {MIN_OS}")
        result[name] = ".".join(map(str, value))
    require(set(result) == {"arm64", "x86_64"}, f"Expected arm64 + x86_64, got {sorted(result)}")
    return result


def resolve_product(path):
    path = path.resolve()
    if path.suffix == ".app":
        require(path.is_dir(), f"Missing app: {path}")
        return path, None
    require(path.suffix == ".xcarchive", "--app must point to an .app or .xcarchive")
    archive = read_plist(path / "Info.plist")
    properties = archive.get("ApplicationProperties", {})
    require(archive.get("ArchiveVersion") == 2 and isinstance(properties, dict), "Invalid Xcode archive metadata")
    relative = Path(properties.get("ApplicationPath", ""))
    require(not relative.is_absolute() and ".." not in relative.parts and relative.parts[:1] == ("Applications",),
            "Archive ApplicationPath must be within Products/Applications")
    app = path / "Products" / relative
    require(app.suffix == ".app" and app.is_dir(), f"Archive app missing: {app}")
    return app, properties


def command(arguments):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=60, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ValidationError(f"Cannot run {arguments[0]}: {error}") from error
    require(result.returncode == 0, f"{' '.join(arguments)} failed: {(result.stderr or result.stdout).strip()}")
    return result.stdout, result.stderr


def app_store_preflight(app, expected_entitlements, team_id, runner=command):
    require(bool(team_id) and re.fullmatch(r"[A-Z0-9]{10}", team_id), "--app-store-ready requires a valid --team-id")
    runner(["codesign", "--verify", "--deep", "--strict", "-R=anchor apple generic", str(app)])
    stdout, stderr = runner(["codesign", "--display", "--verbose=4", str(app)])
    details = stdout + stderr
    # Apple TN3161 documents both current and Mac-specific App Store leaf names.
    require(re.search(r"^Authority=(?:Apple Distribution|3rd Party Mac Developer Application): .+", details, re.M) is not None,
            "Expected an Apple Distribution or Mac App Distribution signature for App Store submission (unsigned/ad-hoc/development/Developer ID is insufficient)")
    require(f"TeamIdentifier={team_id}\n" in details + "\n", "Signature TeamIdentifier does not match --team-id")
    raw, _ = runner(["codesign", "--display", "--entitlements", "-", "--xml", str(app)])
    try:
        signed = plistlib.loads(raw.encode())
    except (ValueError, plistlib.InvalidFileException) as error:
        raise ValidationError("Unable to read signed entitlements") from error
    require(isinstance(signed, dict), "Signed entitlements must be a dictionary")
    for key, value in expected_entitlements.items():
        require(signed.get(key) == value, f"Missing or changed signed entitlement: {key}")
    allowed = set(expected_entitlements) | {"com.apple.application-identifier", "com.apple.developer.team-identifier",
                                           "com.apple.security.get-task-allow", "beta-reports-active"}
    require(not set(signed) - allowed, f"Unexpected signed entitlements: {sorted(set(signed) - allowed)}")
    require(signed.get("com.apple.security.get-task-allow", False) is False, "Release must not permit debugger attachment")
    if "com.apple.application-identifier" in signed:
        require(signed["com.apple.application-identifier"] == f"{team_id}.{BUNDLE_ID}", "Signed application identifier mismatch")
    if "com.apple.developer.team-identifier" in signed:
        require(signed["com.apple.developer.team-identifier"] == team_id, "Signed team entitlement mismatch")
    return {"status": "passed-local-signature-checks", "teamID": team_id,
            "pending": ["Xcode App Store validation and distribution provisioning", "App Store Connect processing", "TestFlight and App Review"]}


def validate_app(path, tables, privacy, version, build):
    app, archive = resolve_product(path)
    info = read_plist(app / "Contents/Info.plist")
    expected = {"CFBundleIdentifier": BUNDLE_ID, "CFBundlePackageType": "APPL",
                "CFBundleShortVersionString": version, "CFBundleVersion": build,
                "LSUIElement": True, "LSApplicationCategoryType": "public.app-category.healthcare-fitness"}
    for key, value in expected.items():
        require(info.get(key) == value and type(info.get(key)) is type(value), f"Product {key}: expected {value!r}, got {info.get(key)!r}")
    require(version_tuple(info.get("LSMinimumSystemVersion")) == version_tuple(MIN_OS), f"Minimum OS must remain {MIN_OS}")
    name = info.get("CFBundleExecutable", "")
    require(bool(name) and Path(name).name == name and "$(" not in name, "Invalid CFBundleExecutable")
    executable = app / "Contents/MacOS" / name
    require(executable.is_file() and executable.stat().st_mode & 0o111, f"Missing or non-executable binary: {executable}")
    architectures = macho_slices(executable)
    resources = app / "Contents/Resources"
    for filename in ("AppIcon.icns", "Assets.car"):
        resource = resources / filename
        require(resource.is_file() and resource.stat().st_size > 0, f"Missing/empty core resource: {resource}")
    require(read_plist(resources / "PrivacyInfo.xcprivacy") == privacy, "Bundled privacy manifest differs from source")
    bundled = validate_locales({locale: resources / f"{locale}.lproj/Localizable.strings" for locale in LOCALES})
    require(bundled == tables, "Bundled localization differs from source; rebuild the product")
    if archive is not None:
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            require(archive.get(key) == info[key], f"Archive {key} differs from its app")
    hashes = {str(file.relative_to(app)): hashlib.sha256(file.read_bytes()).hexdigest()
              for file in sorted(app.rglob("*")) if file.is_file()}
    return app, {"bundleID": BUNDLE_ID, "version": version, "build": build, "minimumMacOS": MIN_OS,
                 "architectures": architectures, "archiveMetadataChecked": archive is not None,
                 "locales": list(LOCALES), "sha256": hashes}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--app", type=Path, help="Built .app or .xcarchive; required unless --source-only")
    parser.add_argument("--source-only", action="store_true")
    parser.add_argument("--version", help="Expected MARKETING_VERSION when overridden at build time")
    parser.add_argument("--build", help="Expected CURRENT_PROJECT_VERSION when overridden at build time")
    parser.add_argument("--app-store-ready", action="store_true", help="Add local Apple Distribution signature checks; does not upload or imply approval")
    parser.add_argument("--team-id", help="Expected 10-character developer team ID for signed preflight")
    parser.add_argument("--report", type=Path, help="Write a JSON report on success or failure")
    args = parser.parse_args(argv)
    report = {"schemaVersion": 1, "checkedAtUTC": datetime.now(timezone.utc).isoformat(),
              "mode": "app-store-local-preflight" if args.app_store_ready else "unsigned-internal-validation",
              "status": "failed", "distributionReady": False,
              "appStorePreflight": {"status": "not-run"}, "errors": []}
    try:
        require(args.app is not None or args.source_only, "Specify --app (.app or .xcarchive), or explicitly choose --source-only")
        require(not (args.source_only and (args.app or args.app_store_ready)), "--source-only cannot be combined with product checks")
        version, build = expected_versions(args.root, args.version, args.build)
        tables, privacy, entitlements = validate_source(args.root)
        report["source"] = {"localizationKeys": len(tables["en"]), "locales": list(LOCALES), "status": "passed"}
        if args.app:
            app, report["product"] = validate_app(args.app, tables, privacy, version, build)
            if args.app_store_ready:
                report["appStorePreflight"] = app_store_preflight(app, entitlements, args.team_id)
        report["status"] = "passed"
    except (ValidationError, OSError, UnicodeError, ValueError, KeyError, struct.error) as error:
        report["errors"].append(str(error))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
    if report["errors"]:
        print("FAIL: " + "; ".join(report["errors"]), file=sys.stderr)
        return 1
    print(f"PASS: {report['mode']}; {report['source']['localizationKeys']} bilingual keys. Distribution approval remains pending.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
