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
        self.temp = tempfile.TemporaryDirectory(prefix="meshmsg-picker-test-")
        self.root = Path(self.temp.name)
        self.file = self.root / "report 100% ❄.txt"
        self.file.write_text("payload", encoding="utf-8")
        self.folder = self.root / "folder with spaces ❄"
        self.folder.mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_canonicalizes_valid_paths(self) -> None:
        self.assertEqual(picker.canonical_path(str(self.file), "file"), os.path.realpath(self.file))
        self.assertEqual(picker.canonical_path(str(self.folder), "directory"), os.path.realpath(self.folder))

    def test_canonicalizes_symlinks(self) -> None:
        link = self.root / "linked report"
        link.symlink_to(self.file)
        self.assertEqual(picker.canonical_path(str(link), "file"), os.path.realpath(self.file))

    def test_validates_selected_type(self) -> None:
        with self.assertRaisesRegex(ValueError, "not a regular file"):
            picker.canonical_path(str(self.folder), "file")
        with self.assertRaisesRegex(ValueError, "not a directory"):
            picker.canonical_path(str(self.file), "directory")

    def test_rejects_relative_and_line_break_paths(self) -> None:
        for path in ("relative.txt", "/tmp/bad\nname", "/tmp/bad\rname", "/tmp/bad\0name"):
            with self.subTest(path=path), self.assertRaises(ValueError):
                picker.canonical_path(path, "file")

    def test_commands_use_nul_delimited_absolute_results(self) -> None:
        fd_command, fzf_command = picker.picker_commands("share-file", "/home/test")
        self.assertIn("--absolute-path", fd_command)
        self.assertIn("--type=f", fd_command)
        self.assertEqual(fd_command[-1], "/home/test")
        self.assertIn("--read0", fzf_command)
        self.assertIn("--print0", fzf_command)

    def test_folder_modes_only_list_directories(self) -> None:
        for mode in ("share-folder", "save-folder"):
            with self.subTest(mode=mode):
                fd_command, _ = picker.picker_commands(mode, "/home/test")
                self.assertIn("--type=d", fd_command)

    def test_status_is_published_after_payload(self) -> None:
        picker.write_status(str(self.root), picker.SUCCESS, b"/tmp/example")
        self.assertEqual((self.root / "result").read_bytes(), b"/tmp/example")
        self.assertEqual((self.root / "status").read_text(encoding="ascii"), "0")
        self.assertFalse((self.root / "status.tmp").exists())


if __name__ == "__main__":
    unittest.main()
