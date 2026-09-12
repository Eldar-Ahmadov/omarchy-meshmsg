#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Security invariants that must remain obvious in the backend.
grep -q '"send", "--to", to, "--message-stdin"' "$ROOT/Service.qml"
! grep -q 'sendMessage(.*recipient' "$ROOT/Service.qml"
grep -q 'keys !== currentExpected' "$ROOT/Service.qml"
grep -q 'privateSendAvailable' "$ROOT/Service.qml"
grep -q 'privateMessageAccepted(requested, value.to)' "$ROOT/Service.qml"

ln -s "$ROOT" "$TMP/Plugin"
cat >"$TMP/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "Plugin" as Plugin
ShellRoot {
  Plugin.Service { id: service; settings: ({ maxPrivateMessages: 20, maxConversations: 5, maxKnownPeers: 10, refreshIntervalSec: 60 }) }
  function check(ok, message) { if (!ok) throw new Error(message) }
  Component.onCompleted: {
    var a = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    var b = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    service.parseStatus('{"type":"status","schema_version":1,"request_id":"11111111111111111111111111111111","running":true,"peer":"' + b + '","alias":"build-node","alias_enabled":true,"captured_hostname":"host","custom_alias":"build-node","advertised_aliases":2,"max_attachment_bytes":4294967296,"ipc_capabilities":["typed_contracts_v1","private_send_v2","peer_directory_v2"]}')
    check(service.alias === "build-node" && service.aliasEnabled, "alias status was not parsed")
    check(service.privateSendAvailable && service.advertisedAliases === 2, "capability status was not parsed")
    check(service.maxAttachmentBytes === 4294967296, "attachment limit was not parsed")
    service.ipcCapabilities = ["typed_contracts_v1", "private_send_v2", "peer_directory_v2"]
    check(service.peerDirectoryAvailable, "peer directory capability was not exposed")
    check(service.applyPeersSnapshot({ type: "peers_snapshot", schema_version: 1, generated_at_ms: 9,
      self: { public_key: b, alias: "self", online: true }, peers: [
        { public_key: a, alias: "alice", online: true, last_seen_ms: 8, expires_at_ms: 100 }
      ] }), "valid peer snapshot was rejected")
    check(service.knownPeers.length === 1 && service.knownPeers[0].alias === "alice" && service.knownPeers[0].online, "peer snapshot was not modeled")
    service.handleEvent('{"type":"peer_updated","schema_version":1,"peer":{"public_key":"' + a + '","alias":"alice-2","online":true,"last_seen_ms":9,"expires_at_ms":101}}')
    check(service.knownPeers[0].alias === "alice-2", "peer update was not applied")
    var event = '{"type":"private_message","schema_version":1,"private":true,"from":"' + a + '","message_id":"0123456789abcdef0123456789abcdef","timestamp_ms":10,"body":"secret","acceptance_acknowledged":true,"durable":false,"read":false}'
    service.handleEvent(event)
    service.handleEvent(event)
    check(service.privateMessages.length === 1, "private message was not deduplicated")
    check(service.messages.length === 0, "private message leaked into broadcast timeline")
    check(service.conversations.length === 1 && service.conversations[0].unreadCount === 1, "conversation unread state is wrong")
    check(service.knownPeers.length === 1 && service.knownPeers[0].peer === a, "known peer was not modeled")
    check(service.markConversationRead(a) && service.privateUnreadCount === 0, "conversation could not be marked read")
    service.handleEvent('{"type":"private_message","schema_version":1,"private":true,"from":"' + a + '","message_id":"fedcba9876543210fedcba9876543210","timestamp_ms":11,"body":"bad","acceptance_acknowledged":false,"durable":false,"read":false}')
    check(service.privateMessages.length === 1, "invalid private event was accepted")
    service.ipcCapabilities = []
    service.running = true
    check(!service.sendPrivateMessage(a, "must not broadcast"), "private send was not capability gated")
    console.log("PRIVATE_SERVICE_TEST_PASS")
  }
}
QML
set +e
HOME="$TMP" timeout 5 qs -p "$TMP" --no-color >"$TMP/test.log" 2>&1
status=$?
set -e
[[ $status -eq 0 || $status -eq 124 ]]
grep -q PRIVATE_SERVICE_TEST_PASS "$TMP/test.log"
! grep -q 'Error:' "$TMP/test.log"
echo 'private messaging backend tests: PASS'
