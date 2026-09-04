#!/usr/bin/env python3
"""Crash-isolated terminal attachment picker using fd and fzf."""

from __future__ import annotations

import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

CANCELLED = 2
FAILED = 1
SUCCESS = 0
INTERACTION_TIMEOUT_SECONDS = 300

MODES = {
    "share-file": ("Select a file to share", "file"),
    "share-folder": ("Select a folder to share", "directory"),
    "save-folder": ("Select a download folder", "directory"),
}


def canonical_path(path: str, expected_type: str) -> str:
    if not isinstance(path, str) or "\0" in path or "\n" in path or "\r" in path:
        raise ValueError("the picker returned an invalid path")
    value = os.path.realpath(path)
    if not os.path.isabs(value):
        raise ValueError("the picker returned a relative path")
    if expected_type == "file" and not os.path.isfile(value):
        raise ValueError("the selected location is not a regular file")
    if expected_type == "directory" and not os.path.isdir(value):
        raise ValueError("the selected location is not a directory")
    return value


def picker_commands(mode: str, root: str, recursive: bool = False) -> tuple[list[str], list[str]]:
    title, expected_type = MODES[mode]
    fd_command = [
        "fd", "--absolute-path", "--color=never", "--hidden", "--print0",
        "--exclude=.git", "--type=d",
    ]
    if expected_type == "file":
        fd_command.append("--type=f")
    if not recursive:
        fd_command.append("--max-depth=1")
    fd_command.extend([".", root])
    action = "Enter open/select file" if expected_type == "file" else "Enter open · Alt+Enter select folder"
    scope = "recursive" if recursive else "this folder"
    fzf_command = [
        "fzf", "--read0", "--print0", "--layout=reverse", "--border",
        "--height=100%", "--scheme=path", "--expect=alt-enter,ctrl-f",
        f"--prompt={title} › ",
        f"--header={root} · {scope} · {action} · Ctrl+F toggle recursive · Esc cancel",
    ]
    return fd_command, fzf_command


def choose_in_terminal(mode: str, start: str) -> tuple[int, str]:
    expected_type = MODES[mode][1]
    current = os.path.realpath(start)
    recursive = False
    while True:
        fd_command, fzf_command = picker_commands(mode, current, recursive)
        scan = subprocess.run(fd_command, stdout=subprocess.PIPE)
        if scan.returncode != 0:
            raise RuntimeError(f"fd could not read {current}")
        candidates = scan.stdout
        parent = os.path.dirname(current)
        if parent != current:
            candidates = os.fsencode(parent) + b"\0" + candidates
        if expected_type == "directory":
            candidates = os.fsencode(current) + b"\0" + candidates
        picker = subprocess.run(fzf_command, input=candidates, stdout=subprocess.PIPE)
        if picker.returncode in (1, 130):
            return CANCELLED, ""
        if picker.returncode != SUCCESS:
            raise RuntimeError(f"fzf exited with status {picker.returncode}")
        fields = picker.stdout.split(b"\0")
        key = os.fsdecode(fields[0]) if fields else ""
        selected = os.fsdecode(fields[1]) if len(fields) > 1 else ""
        if key == "ctrl-f":
            recursive = not recursive
            continue
        path = canonical_path(selected, "directory" if os.path.isdir(selected) else "file")
        if expected_type == "directory" and key == "alt-enter":
            return SUCCESS, canonical_path(path, "directory")
        if os.path.isdir(path):
            current = path
            recursive = False
            continue
        if expected_type == "file":
            return SUCCESS, canonical_path(path, "file")


def write_status(directory: str, code: int, result: bytes = b"", error: str = "") -> None:
    base = Path(directory)
    if result:
        (base / "result").write_bytes(result)
    if error:
        (base / "error").write_text(error, encoding="utf-8")
    temporary = base / "status.tmp"
    temporary.write_text(str(code), encoding="ascii")
    temporary.replace(base / "status")


def terminal_session(mode: str, directory: str) -> int:
    try:
        root = os.path.realpath(os.environ.get("HOME", "/"))
        code, path = choose_in_terminal(mode, root)
        if code == SUCCESS:
            write_status(directory, SUCCESS, os.fsencode(path))
        else:
            write_status(directory, CANCELLED)
        return code
    except Exception as error:
        write_status(directory, FAILED, error=f"could not run the terminal picker: {error}")
        return FAILED


def run_picker(mode: str) -> int:
    for command in ("xdg-terminal-exec", "fd", "fzf"):
        if shutil.which(command) is None:
            print(f"required picker command is not installed: {command}", file=sys.stderr)
            return FAILED

    cancelled = False

    def stop(_signum: int, _frame: object) -> None:
        nonlocal cancelled
        cancelled = True

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    with tempfile.TemporaryDirectory(prefix="meshmsg-picker-") as directory:
        os.chmod(directory, 0o700)
        title = MODES[mode][0]
        try:
            launcher = subprocess.Popen([
                "xdg-terminal-exec", f"--title=Meshmsg — {title}", "--",
                sys.executable, os.path.realpath(__file__),
                "--terminal-session", mode, directory,
            ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError as error:
            print(f"could not open the terminal picker: {error}", file=sys.stderr)
            return FAILED

        status_path = Path(directory) / "status"
        deadline = time.monotonic() + INTERACTION_TIMEOUT_SECONDS
        while not status_path.exists():
            if cancelled:
                launcher.terminate()
                return CANCELLED
            if time.monotonic() >= deadline:
                launcher.terminate()
                print("attachment picker timed out", file=sys.stderr)
                return FAILED
            launcher_code = launcher.poll()
            if launcher_code not in (None, 0):
                print(f"terminal picker exited with status {launcher_code}", file=sys.stderr)
                return FAILED
            time.sleep(0.05)

        code = int(status_path.read_text(encoding="ascii"))
        if code == SUCCESS:
            try:
                selected = os.fsdecode((Path(directory) / "result").read_bytes())
                print(canonical_path(selected, MODES[mode][1]))
            except (OSError, ValueError) as error:
                print(str(error), file=sys.stderr)
                return FAILED
        elif code == FAILED:
            error_path = Path(directory) / "error"
            message = error_path.read_text(encoding="utf-8") if error_path.exists() else "attachment picker failed"
            print(message, file=sys.stderr)
        return code


def main(argv: list[str]) -> int:
    if len(argv) == 4 and argv[1] == "--terminal-session" and argv[2] in MODES:
        return terminal_session(argv[2], argv[3])
    if len(argv) != 2 or argv[1] not in MODES:
        print("usage: attachment-picker.py {share-file|share-folder|save-folder}", file=sys.stderr)
        return FAILED
    return run_picker(argv[1])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
