# Meshmsg Chat for Omarchy

An Omarchy bar widget and chat panel backed by the local [`meshmsg`](https://github.com/Eldar-Ahmadov/meshmsg) daemon.

## Features

- live status and peer count
- animated status surface with daemon, endpoint, topic, invite, bootstrap, identity, and IPC details
- keyboard shortcuts: `Tab` toggles clipboard/chat, `Ctrl+S` toggles settings/chat, `C` copies the invite, and `Q` opens its QR code
- incoming and outgoing chat messages
- unread counter in the bar
- daemon start/stop controls
- join an existing chat using an invite capability
- copy the stored invite or display it as a scannable QR code
- bounded in-memory message history (not persisted by the plugin)

The plugin uses the current top-level meshmsg commands (`daemon`, `join`, `listen`, `status`, `send`, and `stop`). It is compatible with meshmsg's equal-peer model introduced in v0.1.4; there is no seed/member service distinction.

Starting the daemon installs and enables a persistent systemd user unit at `~/.config/systemd/user/meshmsg.service`. The unit starts again after reboot when the user session starts and resolves the supported meshmsg binary on every launch, so binary upgrades do not leave a stale `ExecStart` path. An existing user-managed persistent `meshmsg.service` is respected and never overwritten.

## Security

Meshmsg is currently a trusted **plaintext** swarm. Anyone with an invite can read and send messages. The join form masks the invite and passes it to `meshmsg join --token-stdin`, keeping it out of process arguments and shell history.

## Requirements

- meshmsg v0.1.4 or newer, preferably installed at `~/.local/bin/meshmsg`
- a systemd user session
- initialized or joined meshmsg state before starting, or an invite entered in the panel

Install the latest verified release with the upstream installer:

```sh
curl --proto '=https' --tlsv1.2 -fsSL https://raw.githubusercontent.com/Eldar-Ahmadov/meshmsg/main/install.sh | bash
```

Meshmsg v0.1.4 intentionally breaks compatibility with earlier state and invite formats. Reinitialize with `meshmsg init` or join again after upgrading; old state is not migrated.

## Persistent daemon

Clicking **Start** in the panel installs, enables, and starts the user service. You can manage it directly with:

```sh
systemctl --user status meshmsg.service
systemctl --user restart meshmsg.service
journalctl --user -u meshmsg.service -f
```

The enabled user unit starts at login after a reboot. Running it before login or after logout additionally requires user lingering, which is a separate administrator-controlled setting.
