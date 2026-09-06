#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UI="$ROOT/PrivateMessaging.qml"
PANEL="$ROOT/Panel.qml"

# Private messaging stays a separate, capability-gated text surface.
grep -q 'privateSendAvailable' "$UI"
grep -q 'sendPrivateMessage' "$UI"
grep -q 'Peer alias or canonical node ID' "$UI"
grep -q 'Aliases are resolved by meshmsg' "$UI"
grep -q 'onPrivateMessageAccepted' "$UI"
grep -q 'peerDirectoryAvailable' "$UI"
grep -q 'knownPeers' "$UI"
grep -q 'placeholderText: "Search peers"' "$UI"
grep -q 'parent.width \* 0.46' "$UI"
grep -q 'Layout.preferredWidth: 1' "$UI"
! grep -q 'UNTRUSTED ALIAS' "$UI"
grep -q 'resolved canonical node ID remains the conversation identity' "$UI"
grep -q 'text: root.peerQuery !== "" ? "No matches" : "No peers"' "$UI"
grep -q 'modelData.online' "$UI"
grep -q 'Text only' "$UI"
! grep -Eq 'attachment|delivered|delivery|read receipt|end-to-end' "$UI"

# Entry points, compact drill-in, help, navigation, and IPC remain discoverable.
grep -q 'sequence: "Ctrl+D"' "$PANEL"
grep -q 'function privateMessages()' "$PANEL"
grep -q 'compact: root.panelWidthPercent === 25' "$PANEL"
grep -q 'root.compact && root.detailOpen' "$UI"
grep -q 'moveSelection' "$UI"
grep -q 'unreadCount' "$UI"

echo 'private messaging UI tests: PASS'
