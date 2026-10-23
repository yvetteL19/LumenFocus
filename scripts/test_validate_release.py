"""Small, isolated fixtures; no Xcode build, application launch, signing, or user defaults."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("release_checks", Path(__file__).with_name("validate-release.py"))
checks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checks)


def write_plist(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(plistlib.dumps(value))


def binary(architectures=(0x01000007, 0x0100000C), minimum=13 << 16):
    slices = []
    for cpu in architectures:
        load = struct.pack("<6I", 0x32, 24, 1, minimum, 15 << 16, 0)
        slices.append(struct.pack("<8I", 0xFEEDFACF, cpu, 0, 2, 1, len(load), 0, 0) + load)
    result = struct.pack(">II", 0xCAFEBABE, len(slices))
    offset = 8 + 20 * len(slices)
    for cpu, chunk in zip(architectures, slices):
        result += struct.pack(">5I", cpu, 0, offset, len(chunk), 0)
        offset += len(chunk)
    return result + b"".join(slices)


class ReleaseValidationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="lumen-release-fixture-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = self.root / checks.SOURCE
        source.mkdir(parents=True)
        # Reuse only deterministic source resources; mutate copies, never the checkout.
        for filename in ("Info.plist", "LumenFocus.entitlements", "PrivacyInfo.xcprivacy"):
            shutil.copy2(checks.ROOT / checks.SOURCE / filename, source / filename)
        shutil.copytree(checks.ROOT / checks.SOURCE / "Assets.xcassets", source / "Assets.xcassets")
        project = self.root / "LumenFocus/LumenFocus.xcodeproj/project.pbxproj"
        project.parent.mkdir()
        project.write_text("MARKETING_VERSION = 1.0; CURRENT_PROJECT_VERSION = 1;")
        self.tables = {"en": {"休息 %d 秒": "Rest %d seconds", "设置": "Settings"},
                       "zh-Hans": {"休息 %d 秒": "休息 %d 秒", "设置": "设置"}}
        for locale, table in self.tables.items():
            path = source / f"{locale}.lproj/Localizable.strings"
            path.parent.mkdir()
            path.write_text("\n".join(f'"{key}" = "{value}";' for key, value in table.items()))
        self.privacy = checks.read_plist(source / "PrivacyInfo.xcprivacy")
        self.entitlements = checks.read_plist(source / "LumenFocus.entitlements")
        self.app = self.root / "LumenFocus.app"
        self.info = {"CFBundleIdentifier": checks.BUNDLE_ID, "CFBundlePackageType": "APPL",
                     "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1", "LSUIElement": True,
                     "LSMinimumSystemVersion": "13.0", "CFBundleExecutable": "LumenFocus",
                     "LSApplicationCategoryType": "public.app-category.healthcare-fitness"}
        write_plist(self.app / "Contents/Info.plist", self.info)
        self.executable = self.app / "Contents/MacOS/LumenFocus"
        self.executable.parent.mkdir()
        self.executable.write_bytes(binary())
        self.executable.chmod(0o755)
        self.resources = self.app / "Contents/Resources"
        self.resources.mkdir()
        for filename in ("AppIcon.icns", "Assets.car"):
            (self.resources / filename).write_bytes(b"fixture")
        write_plist(self.resources / "PrivacyInfo.xcprivacy", self.privacy)
        for locale, table in self.tables.items():
            write_plist(self.resources / f"{locale}.lproj/Localizable.strings", table)

    def validate(self):
        return checks.validate_app(self.app, self.tables, self.privacy, "1.0", "1")

    def test_complete_fixture_and_binary_strings_pass(self):
        checks.validate_source(self.root)
        _, report = self.validate()
        self.assertEqual(set(report["architectures"]), {"arm64", "x86_64"})
        self.assertIn("Contents/Resources/PrivacyInfo.xcprivacy", report["sha256"])

    def test_missing_app_fails_and_report_never_claims_distribution_ready(self):
        report = self.root / "failed.json"
        with contextlib.redirect_stderr(io.StringIO()):
            result = checks.main(["--root", str(self.root), "--report", str(report)])
        self.assertEqual(result, 1)
        self.assertFalse(json.loads(report.read_text())["distributionReady"])

    def test_version_override_must_match_the_product(self):
        self.assertEqual(checks.expected_versions(self.root, "2.1", "42"), ("2.1", "42"))
        with self.assertRaisesRegex(checks.ValidationError, "CFBundleShortVersionString"):
            checks.validate_app(self.app, self.tables, self.privacy, "2.1", "42")

    def test_source_version_must_use_build_variables(self):
        path = self.root / checks.SOURCE / "Info.plist"
        value = checks.read_plist(path)
        value["CFBundleVersion"] = "1"
        write_plist(path, value)
        with self.assertRaisesRegex(checks.ValidationError, "CURRENT_PROJECT_VERSION"):
            checks.validate_source(self.root)

    def test_localization_missing_duplicate_and_bad_syntax_fail(self):
        path = self.root / checks.SOURCE / "en.lproj/Localizable.strings"
        for content, expected in [('"设置" = "Settings";', "keys differ"),
                                  ('"设置" = "One"; "设置" = "Two";', "duplicate"),
                                  ('"设置" = "Settings"', "incomplete")]:
            with self.subTest(content=content):
                path.write_text(content)
                with self.assertRaisesRegex(checks.ValidationError, expected):
                    checks.validate_source(self.root)

    def test_placeholder_positions_types_counts_and_escaped_percent(self):
        self.assertEqual(checks.placeholders("%@ %d %%"), checks.placeholders("%2$d %1$@ %%"))
        self.assertNotEqual(checks.placeholders("%@ %d"), checks.placeholders("%d %@"))
        self.assertNotEqual(checks.placeholders("%d %d"), checks.placeholders("%d"))
        self.assertNotEqual(checks.placeholders("%ld"), checks.placeholders("%d"))
        with self.assertRaises(checks.ValidationError):
            checks.placeholders("%*d")  # Unsupported dynamic widths must fail, never be silently ignored.
        path = self.root / checks.SOURCE / "en.lproj/Localizable.strings"
        path.write_text('"设置" = "Settings"; "休息 %d 秒" = "Rest %@ seconds";')
        with self.assertRaisesRegex(checks.ValidationError, "format arguments"):
            checks.validate_source(self.root)

    def test_missing_literal_lookup_fails(self):
        (self.root / checks.SOURCE / "Fixture.swift").write_text('let label = L("没有翻译")')
        with self.assertRaisesRegex(checks.ValidationError, "missing literal"):
            checks.validate_source(self.root)

    def test_wrong_bundle_identity_ui_element_version_and_minimum_os_fail(self):
        for key, value in (("CFBundleIdentifier", "other.app"), ("LSUIElement", False),
                           ("CFBundleVersion", "$(CURRENT_PROJECT_VERSION)"), ("LSMinimumSystemVersion", "14.0")):
            with self.subTest(key=key):
                write_plist(self.app / "Contents/Info.plist", {**self.info, key: value})
                with self.assertRaises(checks.ValidationError):
                    self.validate()

    def test_missing_architecture_high_binary_os_and_malformed_macho_fail(self):
        for data in (binary((0x0100000C,)), binary(minimum=14 << 16), b"not Mach-O", binary()[:60]):
            with self.subTest(data=data[:8]):
                self.executable.write_bytes(data)
                with self.assertRaises((checks.ValidationError, struct.error)):
                    self.validate()

    def test_missing_resource_and_changed_privacy_fail(self):
        (self.resources / "Assets.car").unlink()
        with self.assertRaisesRegex(checks.ValidationError, "core resource"):
            self.validate()
        (self.resources / "Assets.car").write_bytes(b"fixture")
        write_plist(self.resources / "PrivacyInfo.xcprivacy", {**self.privacy, "NSPrivacyTracking": True})
        with self.assertRaisesRegex(checks.ValidationError, "privacy manifest"):
            self.validate()

    def test_stale_bundled_translation_fails(self):
        write_plist(self.resources / "en.lproj/Localizable.strings", {**self.tables["en"], "设置": "Old settings"})
        with self.assertRaisesRegex(checks.ValidationError, "differs from source"):
            self.validate()

    def test_archive_metadata_and_path_are_checked(self):
        archive = self.root / "LumenFocus.xcarchive"
        destination = archive / "Products/Applications/LumenFocus.app"
        destination.parent.mkdir(parents=True)
        shutil.copytree(self.app, destination)
        properties = {key: self.info[key] for key in ("CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString")}
        properties["ApplicationPath"] = "Applications/LumenFocus.app"
        write_plist(archive / "Info.plist", {"ArchiveVersion": 2, "ApplicationProperties": properties})
        _, report = checks.validate_app(archive, self.tables, self.privacy, "1.0", "1")
        self.assertTrue(report["archiveMetadataChecked"])
        properties["CFBundleVersion"] = "2"
        write_plist(archive / "Info.plist", {"ArchiveVersion": 2, "ApplicationProperties": properties})
        with self.assertRaisesRegex(checks.ValidationError, "Archive CFBundleVersion"):
            checks.validate_app(archive, self.tables, self.privacy, "1.0", "1")
        properties["ApplicationPath"] = "../../LumenFocus.app"
        write_plist(archive / "Info.plist", {"ArchiveVersion": 2, "ApplicationProperties": properties})
        with self.assertRaisesRegex(checks.ValidationError, "ApplicationPath"):
            checks.resolve_product(archive)

    def test_unsigned_and_development_signatures_cannot_pass_store_gate(self):
        for authority in ("", "Authority=Apple Development: Test\n", "Authority=Developer ID Application: Test\n",
                          "Authority=3rd Party Mac Developer Installer: Test\n"):
            def runner(arguments):
                return "", authority + "TeamIdentifier=ABCDEFGHIJ\n"
            with self.subTest(authority=authority), self.assertRaisesRegex(checks.ValidationError, "Apple Distribution"):
                checks.app_store_preflight(self.app, self.entitlements, "ABCDEFGHIJ", runner)

    def test_store_gate_checks_team_and_release_entitlements(self):
        signed = dict(self.entitlements)
        def runner(arguments):
            if "--entitlements" in arguments:
                return plistlib.dumps(signed).decode(), ""
            return "", "Authority=Apple Distribution: Test (ABCDEFGHIJ)\nTeamIdentifier=ABCDEFGHIJ\n"
        report = checks.app_store_preflight(self.app, self.entitlements, "ABCDEFGHIJ", runner)
        self.assertEqual(report["status"], "passed-local-signature-checks")
        with self.assertRaisesRegex(checks.ValidationError, "TeamIdentifier"):
            checks.app_store_preflight(self.app, self.entitlements, "ZZZZZZZZZZ", runner)
        signed["com.apple.security.get-task-allow"] = True
        with self.assertRaisesRegex(checks.ValidationError, "debugger"):
            checks.app_store_preflight(self.app, self.entitlements, "ABCDEFGHIJ", runner)
        signed.pop("com.apple.security.get-task-allow")
        signed["com.apple.security.network.client"] = True
        with self.assertRaisesRegex(checks.ValidationError, "Unexpected signed"):
            checks.app_store_preflight(self.app, self.entitlements, "ABCDEFGHIJ", runner)

    def test_mac_app_distribution_legacy_leaf_name_is_accepted(self):
        calls = []
        def runner(arguments):
            calls.append(arguments)
            if "--entitlements" in arguments:
                return plistlib.dumps(self.entitlements).decode(), ""
            return "", "Authority=3rd Party Mac Developer Application: Test (ABCDEFGHIJ)\nTeamIdentifier=ABCDEFGHIJ\n"
        result = checks.app_store_preflight(self.app, self.entitlements, "ABCDEFGHIJ", runner)
        self.assertEqual(result["status"], "passed-local-signature-checks")
        self.assertIn("-R=anchor apple generic", calls[0])
        with self.assertRaisesRegex(checks.ValidationError, "TeamIdentifier"):
            checks.app_store_preflight(self.app, self.entitlements, "ZZZZZZZZZZ", runner)

    @unittest.skipUnless(shutil.which("ditto"), "Packaging fixture needs macOS ditto")
    def test_package_contains_report_checksums_and_refuses_overwrite(self):
        # The package CLI validates against this checkout, so use its translations in the fake app.
        for locale in checks.LOCALES:
            source = checks.ROOT / checks.SOURCE / f"{locale}.lproj/Localizable.strings"
            shutil.copy2(source, self.resources / f"{locale}.lproj/Localizable.strings")
        output = self.root / "artifacts"
        args = [sys.executable, str(Path(__file__).with_name("package-unsigned.py")),
                "--app", str(self.app), "--output", str(output), "--version", "1.0", "--build", "1"]
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        archives = list(output.glob("*.zip"))
        self.assertEqual(len(archives), 1)
        self.assertIn("unsigned-not-for-distribution", archives[0].name)
        self.assertTrue(archives[0].with_suffix(".zip.sha256").is_file())
        with zipfile.ZipFile(archives[0]) as archive:
            report_name = next(name for name in archive.namelist() if name.endswith("/validation.json"))
            report = json.loads(archive.read(report_name))
            self.assertEqual(report["status"], "passed")
            self.assertFalse(report["distributionReady"])
            self.assertEqual(report["appStorePreflight"]["status"], "not-run")
        original = archives[0].read_bytes()
        result = subprocess.run(args, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to replace", result.stderr)
        self.assertEqual(archives[0].read_bytes(), original)

    @unittest.skipUnless(shutil.which("ditto"), "Packaging fixture needs macOS ditto")
    def test_failed_validation_does_not_create_zip(self):
        (self.resources / "Assets.car").unlink()
        output = self.root / "artifacts"
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("package-unsigned.py")),
                                 "--app", str(self.app), "--output", str(output)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list(output.glob("*.zip")), [])


if __name__ == "__main__":
    unittest.main()
