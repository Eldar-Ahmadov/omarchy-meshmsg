# Meshmsg Chat for Omarchy

An Omarchy bar widget and chat panel backed by the local [`meshmsg`](https://github.com/Eldar-Ahmadov/meshmsg) daemon.

## Features

- live status and peer count
- animated status surface with daemon, endpoint, topic, invite, bootstrap, and identity details
- smoothly animated left, center, or right panel placement and 25%, 40%, or 50% screen-width sizing from the status/settings surface
- keyboard shortcuts: `Ctrl+D` toggles private/group chat, `Ctrl+Delete` deletes the focused group message, `Ctrl+O` picks a file, `Ctrl+Shift+O` picks a folder, `Ctrl+Shift+V` toggles clipboard/chat, `Ctrl+S` toggles settings/chat, `C` copies the invite, and `Q` opens its QR code
- a separate peer-list/private-chat surface with authoritative protocol-v3 peer discovery, alias-only peer selection, per-conversation text search, and a compact 25% drill-in layout
- latest-first incoming and outgoing chat messages, showing peer aliases with node-ID fallback, with hover actions to copy or delete individual messages
- explicit file and folder-snapshot sharing with inline transfer cards and progress
- collision-safe downloads to the XDG Downloads directory, with optional destination selection
- crash-isolated portal file chooser, kept outside the long-running Quickshell process
- completed-download actions to open content, show it in Files, or copy its local path
- unread counter for incoming messages and attachment offers
- daemon start/stop controls
- join an existing chat using an invite capability
- copy the stored invite or display it as a scannable QR code
- bounded in-memory message and attachment history (not persisted by the plugin)

Private messaging is text-only in the panel: it has no attachment controls, offline delivery, durable storage, or read receipts. Meshmsg sends it over a separately encrypted, authenticated direct connection; a success acknowledges only acceptance by the recipient daemon. The peer list follows the authoritative protocol-v3 peer directory and distinguishes online and expired/offline entries. Discovered peers are selected by their advertised alias, while canonical keys remain the internal conversation identity. Advertised aliases are explicitly untrusted display labels.

The plugin uses meshmsg's current equal-peer command family, including `share` and `download --offer-stdin`. Attachment offers and transfer state remain in memory, so restarting the shell can discard undownloaded offers and in-progress UI state even though daemon-pinned blob data persists.

Starting the daemon installs and enables a persistent systemd user unit at `~/.config/systemd/user/meshmsg.service`. The unit starts again after reboot when the user session starts and resolves the supported meshmsg binary on every launch, so binary upgrades do not leave a stale `ExecStart` path. An existing user-managed persistent `meshmsg.service` is respected and never overwritten.

## Security

Broadcast messages and attachment offers are **plaintext** to everyone with the topic invite. Direct messages use a separately encrypted, authenticated connection, but have no offline delivery, durable storage, or read receipt. Shared attachment offers are reusable capabilities; their pinned data can be managed with meshmsg's `offers` commands. Downloads are always user-initiated. The plugin passes invites through `join --token-stdin` and attachment offers through `download --offer-stdin`, keeping both out of process arguments and shell history.

## Requirements

- meshmsg v0.1.22 or newer (strict local IPC protocol v3), preferably installed at `~/.local/bin/meshmsg`
- Python, `fd`, `fzf`, and `xdg-terminal-exec` for the terminal attachment picker
- a systemd user session
- initialized or joined meshmsg state before starting, or an invite entered in the panel

Install the latest verified release with the upstream installer:

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Eldar-Ahmadov/meshmsg/main/install.sh | bash
```

The plugin checks the installed binary for attachment commands and secure `download --offer-stdin` input. It requires meshmsg's strict protocol-v3 responses and events; older local contract families are intentionally not accepted. Attachment selection runs as an `fd` + `fzf` fuzzy finder in the configured terminal; picker failures therefore report an error without taking down the Omarchy shell.

## Persistent daemon

Clicking **Start** in the panel installs, enables, and starts the user service. You can manage it directly with:

```sh
systemctl --user status meshmsg.service
systemctl --user restart meshmsg.service
journalctl --user -u meshmsg.service -f
```

The enabled user unit starts at login after a reboot. Running it before login or after logout additionally requires user lingering, which is a separate administrator-controlled setting.
