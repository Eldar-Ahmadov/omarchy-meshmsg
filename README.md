# Meshmsg Chat for Omarchy

An Omarchy bar widget and chat panel backed by the local [`meshmsg`](https://github.com/Eldar-Ahmadov/meshmsg) daemon.

## Features

- live status and peer count
- incoming and outgoing chat messages
- unread counter in the bar
- daemon start/stop controls
- join an existing chat using an invite capability
- bounded in-memory message history (not persisted by the plugin)

The plugin uses `meshmsg --json listen`, `status`, and `send`. Starting the daemon respects an existing `meshmsg.service`; otherwise it creates a supervised transient systemd user unit.

## Security

Meshmsg is currently a trusted **plaintext** swarm. Anyone with an invite can read and send messages. The join form masks the invite and passes it to `meshmsg join --token-stdin`, keeping it out of process arguments and shell history.

## Requirements

- `meshmsg` on `PATH`
- a systemd user session
- initialized or joined meshmsg state before starting, or an invite entered in the panel
