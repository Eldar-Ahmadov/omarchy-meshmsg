#!/usr/bin/env python3
"""Crash-isolated attachment picker backed by the desktop portal."""

from __future__ import annotations

import os
import re
import secrets
import signal
import sys
from urllib.parse import unquote_to_bytes, urlsplit

CANCELLED = 2
FAILED = 1
SUCCESS = 0
PORTAL_BUS = "org.freedesktop.portal.Desktop"
PORTAL_PATH = "/org/freedesktop/portal/desktop"
FILE_CHOOSER_IFACE = "org.freedesktop.portal.FileChooser"
REQUEST_IFACE = "org.freedesktop.portal.Request"
INTERACTION_TIMEOUT_SECONDS = 300
_INVALID_ESCAPE = re.compile(r"%(?![0-9A-Fa-f]{2})")

MODES = {
    "share-file": ("Share a file", False, "file"),
    "share-folder": ("Share a folder snapshot", True, "directory"),
    "save-folder": ("Choose where to save the attachment", True, "directory"),
}


def canonical_path_from_uri(uri: str, expected_type: str) -> str:
    if not isinstance(uri, str) or _INVALID_ESCAPE.search(uri):
        raise ValueError("the chooser returned an invalid URI")
    parsed = urlsplit(uri)
    if parsed.scheme.casefold() != "file":
        raise ValueError("the chooser did not return a local file")
    if parsed.netloc and parsed.netloc.casefold() != "localhost":
        raise ValueError("remote file locations are not supported")
    if parsed.query or parsed.fragment:
        raise ValueError("the chooser returned an invalid local file URI")
    raw_path = unquote_to_bytes(parsed.path)
    if b"\0" in raw_path:
        raise ValueError("the selected path contains an invalid character")
    path = os.fsdecode(raw_path)
    if "\n" in path or "\r" in path:
        raise ValueError("paths containing line breaks are not supported")
    if not os.path.isabs(path):
        raise ValueError("the chooser returned a relative path")
    path = os.path.realpath(path)
    if not os.path.isabs(path):
        raise ValueError("the chooser returned an invalid path")
    if expected_type == "file" and not os.path.isfile(path):
        raise ValueError("the selected location is not a regular file")
    if expected_type == "directory" and not os.path.isdir(path):
        raise ValueError("the selected location is not a directory")
    return path


def selected_path(response: int, results: object, expected_type: str) -> tuple[int, str]:
    code = int(response)
    if code == 1:
        return CANCELLED, ""
    if code != 0:
        raise RuntimeError("the file chooser closed without a selection")
    if not hasattr(results, "get"):
        raise ValueError("the chooser returned malformed results")
    uris = results.get("uris")
    if not isinstance(uris, (list, tuple)) or len(uris) != 1:
        raise ValueError("the chooser did not return exactly one selection")
    return SUCCESS, canonical_path_from_uri(str(uris[0]), expected_type)


class PortalPicker:
    def __init__(self, mode: str) -> None:
        title, directory, expected_type = MODES[mode]
        self.title = title
        self.directory = directory
        self.expected_type = expected_type
        self.exit_code = FAILED
        self.path = ""
        self.error = ""
        self.loop = None
        self.bus = None
        self.request_path = ""
        self.predicted_path = ""
        self.returned_path = ""
        self.pending_responses: dict[str, tuple[object, object]] = {}
        self.matches: list[object] = []
        self.done = False

    def finish(self, code: int, path: str = "", error: str = "") -> None:
        if self.done:
            return
        self.done = True
        self.exit_code = code
        self.path = path
        self.error = error
        if self.loop is not None:
            self.loop.quit()

    def close_request(self) -> None:
        if self.bus is None or not self.request_path:
            return
        try:
            import dbus

            request = dbus.Interface(
                self.bus.get_object(PORTAL_BUS, self.request_path), REQUEST_IFACE
            )
            request.Close(timeout=2)
        except Exception:
            pass

    def on_response(self, response: object, results: object) -> None:
        try:
            code, path = selected_path(int(response), results, self.expected_type)
            self.finish(code, path)
        except (RuntimeError, ValueError) as error:
            self.finish(FAILED, error=str(error))

    def on_response_signal(
        self,
        response: object,
        results: object,
        signal_path: object | None = None,
    ) -> None:
        path = str(signal_path or "")
        if path == self.predicted_path or (self.returned_path and path == self.returned_path):
            self.on_response(response, results)
        elif not self.returned_path and path and len(self.pending_responses) < 4:
            # A conforming portal uses the predicted handle. Buffer an early
            # response from a rewritten handle until OpenFile returns it.
            self.pending_responses[path] = (response, results)

    def on_timeout(self) -> bool:
        self.close_request()
        self.finish(FAILED, error="attachment picker timed out")
        return False

    def on_signal(self, *_args: object) -> bool:
        self.close_request()
        self.finish(CANCELLED)
        return False

    def on_portal_owner_changed(self, _name: object, old_owner: object, new_owner: object) -> None:
        if str(old_owner) and not str(new_owner):
            self.finish(FAILED, error="the desktop file chooser stopped unexpectedly")

    def run(self) -> int:
        try:
            import dbus
            from dbus.mainloop.glib import DBusGMainLoop
            from gi.repository import GLib

            DBusGMainLoop(set_as_default=True)
            self.bus = dbus.SessionBus()
            self.loop = GLib.MainLoop()
            sender = self.bus.get_unique_name().lstrip(":").replace(".", "_")
            token = "meshmsg_" + secrets.token_hex(12)
            predicted = f"{PORTAL_PATH}/request/{sender}/{token}"
            self.predicted_path = predicted
            self.request_path = predicted
            # Subscribe before OpenFile and include the signal path. A broad,
            # portal-owner-filtered receiver also catches an early response if
            # the backend rewrites handle_token and returns another path.
            self.matches.append(
                self.bus.add_signal_receiver(
                    self.on_response_signal,
                    signal_name="Response",
                    dbus_interface=REQUEST_IFACE,
                    bus_name=PORTAL_BUS,
                    path_keyword="signal_path",
                )
            )
            self.matches.append(
                self.bus.add_signal_receiver(
                    self.on_portal_owner_changed,
                    signal_name="NameOwnerChanged",
                    dbus_interface="org.freedesktop.DBus",
                    bus_name="org.freedesktop.DBus",
                    path="/org/freedesktop/DBus",
                    arg0=PORTAL_BUS,
                )
            )
            chooser = dbus.Interface(
                self.bus.get_object(PORTAL_BUS, PORTAL_PATH), FILE_CHOOSER_IFACE
            )
            options = dbus.Dictionary(
                {
                    "handle_token": dbus.String(token),
                    "modal": dbus.Boolean(False),
                    "multiple": dbus.Boolean(False),
                    "directory": dbus.Boolean(self.directory),
                    "accept_label": dbus.String("Select"),
                },
                signature="sv",
            )
            returned = str(chooser.OpenFile("", self.title, options, timeout=15))
            self.returned_path = returned
            self.request_path = returned
            pending = self.pending_responses.pop(returned, None)
            self.pending_responses.clear()
            if pending is not None and not self.done:
                self.on_response(*pending)
            if not self.done:
                GLib.timeout_add_seconds(INTERACTION_TIMEOUT_SECONDS, self.on_timeout)
                GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self.on_signal)
                GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self.on_signal)
                self.loop.run()
        except Exception as error:
            self.finish(FAILED, error=f"could not open the attachment picker: {error}")
        finally:
            for match in self.matches:
                try:
                    match.remove()
                except Exception:
                    pass
        if self.exit_code == SUCCESS:
            sys.stdout.write(self.path + "\n")
        elif self.exit_code == FAILED:
            print(self.error or "attachment picker failed", file=sys.stderr)
        return self.exit_code


def main(argv: list[str]) -> int:
    if len(argv) != 2 or argv[1] not in MODES:
        print("usage: attachment-picker.py {share-file|share-folder|save-folder}", file=sys.stderr)
        return FAILED
    return PortalPicker(argv[1]).run()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
