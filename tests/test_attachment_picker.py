#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("attachment_picker", ROOT / "attachment-picker.py")
assert SPEC and SPEC.loader
picker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(picker)


class AttachmentPickerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="meshmsg-picker-")
        self.root = Path(self.temp.name)
        self.file = self.root / "report 100% ❄.txt"
        self.file.write_text("payload", encoding="utf-8")
        self.folder = self.root / "folder with spaces ❄"
        self.folder.mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_decodes_and_canonicalizes_local_file_uris(self) -> None:
        expected = os.path.realpath(self.file)
        self.assertEqual(picker.canonical_path_from_uri(self.file.as_uri(), "file"), expected)
        localhost = "file://localhost" + self.file.as_uri()[7:]
        self.assertEqual(picker.canonical_path_from_uri(localhost, "file"), expected)

    def test_canonicalizes_symlinks(self) -> None:
        link = self.root / "linked report"
        link.symlink_to(self.file)
        self.assertEqual(
            picker.canonical_path_from_uri(link.as_uri(), "file"),
            os.path.realpath(self.file),
        )

    def test_validates_selected_type(self) -> None:
        with self.assertRaisesRegex(ValueError, "not a regular file"):
            picker.canonical_path_from_uri(self.folder.as_uri(), "file")
        with self.assertRaisesRegex(ValueError, "not a directory"):
            picker.canonical_path_from_uri(self.file.as_uri(), "directory")
        self.assertEqual(
            picker.canonical_path_from_uri(self.folder.as_uri(), "directory"),
            os.path.realpath(self.folder),
        )

    def test_rejects_remote_non_file_relative_nul_and_invalid_escape_uris(self) -> None:
        rejected = [
            "https://example.test/report.txt",
            "file://remote-host/tmp/report.txt",
            "file:relative.txt",
            "file:///tmp/bad%00name",
            "file:///tmp/bad%ZZname",
        ]
        for uri in rejected:
            with self.subTest(uri=uri), self.assertRaises(ValueError):
                picker.canonical_path_from_uri(uri, "file")

    def test_response_contract(self) -> None:
        self.assertEqual(picker.selected_path(1, {}, "file"), (picker.CANCELLED, ""))
        self.assertEqual(
            picker.selected_path(0, {"uris": [self.file.as_uri()]}, "file"),
            (picker.SUCCESS, os.path.realpath(self.file)),
        )
        for results in ({}, {"uris": []}, {"uris": [self.file.as_uri(), self.file.as_uri()]}, {"uris": "bad"}):
            with self.subTest(results=results), self.assertRaises(ValueError):
                picker.selected_path(0, results, "file")
        with self.assertRaises(RuntimeError):
            picker.selected_path(2, {}, "file")

    def test_response_path_filtering_and_early_rewritten_handle_buffer(self) -> None:
        portal = picker.PortalPicker("share-file")
        portal.predicted_path = "/request/predicted"
        portal.on_response_signal(1, {}, signal_path="/request/unrelated")
        self.assertFalse(portal.done)
        self.assertIn("/request/unrelated", portal.pending_responses)

        portal.returned_path = "/request/rewritten"
        portal.on_response_signal(1, {}, signal_path="/request/unrelated")
        self.assertFalse(portal.done)
        portal.on_response_signal(1, {}, signal_path="/request/rewritten")
        self.assertTrue(portal.done)
        self.assertEqual(portal.exit_code, picker.CANCELLED)

    def test_predicted_response_is_accepted_immediately(self) -> None:
        portal = picker.PortalPicker("share-file")
        portal.predicted_path = "/request/predicted"
        portal.on_response_signal(1, {}, signal_path="/request/predicted")
        self.assertTrue(portal.done)
        self.assertEqual(portal.exit_code, picker.CANCELLED)

    def test_portal_disappearance_finishes_with_an_error(self) -> None:
        portal = picker.PortalPicker("share-file")
        portal.on_portal_owner_changed(picker.PORTAL_BUS, ":1.42", "")
        self.assertTrue(portal.done)
        self.assertEqual(portal.exit_code, picker.FAILED)
        self.assertIn("stopped unexpectedly", portal.error)

    def test_timeout_finishes_without_a_live_request(self) -> None:
        portal = picker.PortalPicker("share-folder")
        self.assertFalse(portal.on_timeout())
        self.assertTrue(portal.done)
        self.assertEqual(portal.exit_code, picker.FAILED)
        self.assertIn("timed out", portal.error)


if __name__ == "__main__":
    unittest.main()
