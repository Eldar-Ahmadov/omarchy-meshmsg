# Meshmsg Chat for Omarchy

An Omarchy bar widget and chat panel backed by the local [`meshmsg`](https://github.com/Eldar-Ahmadov/meshmsg) daemon.

## Features

- live status and peer count
- animated status surface with daemon, endpoint, topic, invite, bootstrap, identity, and IPC details
- keyboard shortcuts: `Ctrl+O` opens attachment choices, `Ctrl+Shift+V` toggles clipboard/chat, `Ctrl+S` toggles settings/chat, `C` copies the invite, and `Q` opens its QR code
- incoming and outgoing chat messages
- explicit file and folder-snapshot sharing with inline transfer cards and progress
- collision-safe downloads to the XDG Downloads directory, with optional destination selection
- crash-isolated portal file chooser, kept outside the long-running Quickshell process
- completed-download actions to open content, show it in Files, or copy its local path
- unread counter for incoming messages and attachment offers
- daemon start/stop controls
- join an existing chat using an invite capability
- copy the stored invite or display it as a scannable QR code
- bounded in-memory message and attachment history (not persisted by the plugin)

The plugin uses meshmsg's current equal-peer command family, including `share` and `download --offer-stdin`. Attachment offers and transfer state remain in memory, so restarting the shell can discard undownloaded offers and in-progress UI state even though daemon-pinned blob data persists.

Starting the daemon installs and enables a persistent systemd user unit at `~/.config/systemd/user/meshmsg.service`. The unit starts again after reboot when the user session starts and resolves the supported meshmsg binary on every launch, so binary upgrades do not leave a stale `ExecStart` path. An existing user-managed persistent `meshmsg.service` is respected and never overwritten.

## Security

Meshmsg is currently a trusted **plaintext** swarm. Anyone with an invite can read messages and attachment offers and can send both. Shared attachment offers are reusable capabilities and currently cannot be revoked. Downloads are always user-initiated. The plugin passes invites through `join --token-stdin` and attachment offers through `download --offer-stdin`, keeping both out of process arguments and shell history.

## Requirements

- meshmsg v0.1.9 or newer, preferably installed at `~/.local/bin/meshmsg`
- Python with `dbus-python` and PyGObject, plus an XDG desktop portal FileChooser backend
- a systemd user session
- initialized or joined meshmsg state before starting, or an invite entered in the panel

Install the latest verified release with the upstream installer:

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Eldar-Ahmadov/meshmsg/main/install.sh | bash
```

The plugin capability-checks the installed binary for v0.1.9's attachment commands and secure `download --offer-stdin` input. Older binaries are reported as unavailable. Attachment selection runs in a standalone Python D-Bus helper; a portal/backend failure therefore reports an error without taking down the Omarchy shell.

## Persistent daemon

Clicking **Start** in the panel installs, enables, and starts the user service. You can manage it directly with:

```sh
systemctl --user status meshmsg.service
systemctl --user restart meshmsg.service
journalctl --user -u meshmsg.service -f
```

The enabled user unit starts at login after a reboot. Running it before login or after logout additionally requires user lingering, which is a separate administrator-controlled setting.
