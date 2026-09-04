#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-meshmsg-tests.XXXXXX")
cleanup() { rm -rf -- "$TMP"; }
trap cleanup EXIT

if grep -Eq 'QtQuick\.Dialogs|(^|[^A-Za-z])(FileDialog|FolderDialog)[[:space:]]*\{' "$ROOT/Panel.qml"; then
  echo 'Panel.qml reintroduced an in-process Qt file dialog' >&2
  exit 1
fi
python3 "$ROOT/tests/test_attachment_picker.py"
if "$ROOT/attachment-picker.py" unsupported-mode >"$TMP/picker.out" 2>"$TMP/picker.err"; then
  echo 'picker accepted an unsupported mode' >&2
  exit 1
fi
[[ ! -s "$TMP/picker.out" ]]
grep -q 'usage: attachment-picker.py' "$TMP/picker.err"
set +e
DBUS_SESSION_BUS_ADDRESS="unix:path=$TMP/missing-bus" "$ROOT/attachment-picker.py" share-file >"$TMP/picker.out" 2>"$TMP/picker.err"
picker_status=$?
set -e
[[ $picker_status -eq 1 && ! -s "$TMP/picker.out" ]]
grep -q 'could not open the attachment picker' "$TMP/picker.err"

mkdir -p "$TMP/bin" "$TMP/downloads" "$TMP/custom" "$TMP/custom folder "
cat >"$TMP/bin/xdg-user-dir" <<EOF
#!/bin/sh
printf '%s\n' '$TMP/downloads'
EOF
chmod +x "$TMP/bin/xdg-user-dir"

PATH="$TMP/bin:$PATH" HOME="$TMP" "$ROOT/attachment-destination.sh" file 'report.final.pdf' >"$TMP/first"
[[ $(<"$TMP/first") == "$TMP/downloads/Meshmsg/report.final.pdf" ]]
touch -- "$(<"$TMP/first")"
PATH="$TMP/bin:$PATH" HOME="$TMP" "$ROOT/attachment-destination.sh" file 'report.final.pdf' >"$TMP/second"
[[ $(<"$TMP/second") == "$TMP/downloads/Meshmsg/report.final (2).pdf" ]]
mkdir -- "$TMP/downloads/Meshmsg/results"
PATH="$TMP/bin:$PATH" HOME="$TMP" "$ROOT/attachment-destination.sh" directory_tar_v1 'results.tar' >"$TMP/directory"
[[ $(<"$TMP/directory") == "$TMP/downloads/Meshmsg/results (2)" ]]
[[ $("$ROOT/attachment-destination.sh" file 'snow ❄.txt' "$TMP/custom") == "$TMP/custom/snow ❄.txt" ]]
[[ $("$ROOT/attachment-destination.sh" file 'space.txt' "$TMP/custom folder ") == "$TMP/custom folder /space.txt" ]]
if "$ROOT/attachment-destination.sh" file '../unsafe' "$TMP/custom" >/dev/null 2>&1; then
  echo 'unsafe attachment name was accepted' >&2
  exit 1
fi

mkdir -p "$TMP/fakehome/.local/bin"
cat >"$TMP/fakehome/.local/bin/meshmsg" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == download ]]; then
  echo 'Usage: meshmsg download --output PATH'
else
  printf '  %s  command\n' daemon init join invite send listen status stop share download
fi
EOF
chmod +x "$TMP/fakehome/.local/bin/meshmsg"
if HOME="$TMP/fakehome" PATH="$TMP/fakehome/.local/bin:/usr/bin" "$ROOT/resolve-meshmsg.sh" >/dev/null 2>&1; then
  echo 'resolver accepted meshmsg without --offer-stdin' >&2
  exit 1
fi
cat >"$TMP/fakehome/.local/bin/meshmsg" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == download ]]; then
  echo 'Usage: meshmsg download --offer-stdin --output PATH'
else
  printf '  %s  command\n' daemon init join invite send listen status stop share download
fi
EOF
[[ $(HOME="$TMP/fakehome" PATH="$TMP/fakehome/.local/bin:/usr/bin" "$ROOT/resolve-meshmsg.sh") == "$TMP/fakehome/.local/bin/meshmsg" ]]

ln -s /usr/share/omarchy/shell/Commons "$TMP/Commons"
ln -s /usr/share/omarchy/shell/Ui "$TMP/Ui"
ln -s "$ROOT" "$TMP/Plugin"
cat >"$TMP/shell.qml" <<'EOF'
import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: testRoot
  property int incomingCount: 0

  Plugin.Service {
    id: service
    settings: ({ maxMessages: 20, refreshIntervalSec: 60 })
  }

  Connections {
    target: service
    function onIncomingActivity() { testRoot.incomingCount += 1 }
  }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  Component.onCompleted: {
    service.handleEvent('{"type":"message","from":"peer","body":"hello","timestamp_ms":1}')
    service.handleEvent('{"type":"queued","from":"self","body":"sent"}')
    var offer = '{"type":"attachment_offer","schema_version":1,"from":"peer","timestamp_ms":2,"offer_id":"0123456789abcdef0123456789abcdef","kind":"file","name":"report.pdf","size":1234,"offer":"signed-secret"}'
    service.handleEvent(offer)
    service.handleEvent(offer)
    check(service.messages.length === 3, "offer was not deduplicated")
    check(incomingCount === 2, "incoming activity counted outgoing or duplicate events")
    check(service.messages[2].state === "offered", "offer state is wrong")
    var collidingOffer = '{"type":"attachment_offer","schema_version":1,"from":"other-peer","timestamp_ms":3,"offer_id":"0123456789abcdef0123456789abcdef","kind":"file","name":"other.pdf","size":456,"offer":"other-signed-secret"}'
    service.handleEvent(collidingOffer)
    check(service.messages.length === 4, "offers from different providers were incorrectly deduplicated")
    check(service.messages[2].id !== service.messages[3].id, "provider-scoped offers shared an identity")
    service.replaceTimelineItem(2, { state: "queued", outputPath: "/tmp/report.pdf" })
    service._activeAttachmentId = service.messages[2].id
    service._activeAttachmentOperation = "download"
    service._activeAttachmentOutput = "/tmp/report.pdf"
    service.handleEvent('{"type":"download_started","schema_version":1,"output":"/tmp/report.pdf"}')
    check(service.messages[2].state === "preparing_download", "started download did not update the active card")
    service.handleEvent('{"type":"download_progress","schema_version":1,"received_bytes":100,"total_bytes":1234,"output":"/tmp/report.pdf"}')
    check(service.messages[2].state === "downloading", "progress did not update the active card")
    service.handleEvent('{"type":"download_complete","schema_version":1,"offer_id":"0123456789abcdef0123456789abcdef","kind":"file","name":"report.pdf","size":1234,"from":"peer","output":"/tmp/report.pdf"}')
    check(service.messages[2].state === "complete", "completion did not update the active card")
    service._activeAttachmentId = ""
    service._activeAttachmentOperation = ""
    service._activeAttachmentOutput = ""
    service.handleEvent('{"type":"download_started","schema_version":1,"output":"/tmp/report.pdf"}')
    check(service.messages[2].state === "complete", "unrelated start event regressed a completed card")
    service.handleEvent(offer)
    check(service.messages[2].state === "complete", "duplicate offer regressed completed state")
    service.replaceTimelineItem(3, { state: "queued", outputPath: "/tmp/report.pdf" })
    service._activeAttachmentId = service.messages[3].id
    service._activeAttachmentOperation = "download"
    service._activeAttachmentOutput = "/tmp/report.pdf"
    service.handleEvent('{"type":"download_progress","schema_version":1,"received_bytes":50,"total_bytes":456,"output":"/tmp/report.pdf"}')
    check(service.messages[2].state === "complete", "progress regressed an older card sharing the output path")
    check(service.messages[3].state === "downloading", "progress did not prefer the active card")
    service.handleEvent('{"type":"attachment_offer","schema_version":1,"from":"peer","offer_id":"fedcba9876543210fedcba9876543210","kind":"file","name":"../unsafe","size":1,"offer":"DO_NOT_LOG_THIS_CAPABILITY"}')
    check(service.messages.length === 4, "unsafe offer became actionable")
    service.handleEvent('{"type":"attachment_offer","offer":"DO_NOT_LOG_THIS_MALFORMED_CAPABILITY"')
    for (var i = 0; i < 25; i++)
      service.handleEvent('{"type":"message","from":"peer","body":"bounded-' + i + '","timestamp_ms":' + (10 + i) + '}')
    check(service.messages.length === 20, "timeline did not stay bounded")
    check(incomingCount === 28, "incoming activity stopped at the timeline cap")
    console.log("ATTACHMENT_SERVICE_TEST_PASS")
  }
}
EOF

set +e
HOME="$TMP" timeout 5 qs -p "$TMP" --no-color >"$TMP/service.log" 2>&1
status=$?
set -e
[[ $status -eq 0 || $status -eq 124 ]]
grep -q 'ATTACHMENT_SERVICE_TEST_PASS' "$TMP/service.log"
! grep -q 'DO_NOT_LOG_THIS' "$TMP/service.log"
! grep -q 'Error:' "$TMP/service.log"

mkdir -p "$TMP/process-config" "$TMP/.config/omarchy/plugins/eldar.meshmsg"
ln -s /usr/share/omarchy/shell/Commons "$TMP/process-config/Commons"
ln -s /usr/share/omarchy/shell/Ui "$TMP/process-config/Ui"
ln -s "$ROOT" "$TMP/process-config/Plugin"
cp "$ROOT/attachment-destination.sh" "$TMP/.config/omarchy/plugins/eldar.meshmsg/attachment-destination.sh"
printf payload >"$TMP/source.txt"
cat >"$TMP/fake-meshmsg" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%q ' "$@" >"${TEST_ARGS:?}"
printf '\n' >>"$TEST_ARGS"
[[ ${1:-} == --json ]]
case ${2:-} in
  share)
    printf '%s\n' '{"type":"attachment_shared","schema_version":1,"from":"self","offer_id":"11111111111111111111111111111111","kind":"file","name":"source.txt","size":7,"ticket":"ticket","offer":"outgoing-capability","delivery_acknowledged":false}'
    ;;
  download)
    token=$(cat)
    printf '%s' "$token" >"${TEST_STDIN:?}"
    output=
    while (($#)); do
      if [[ $1 == --output ]]; then output=$2; break; fi
      shift
    done
    printf '{"type":"download_complete","schema_version":1,"offer_id":"22222222222222222222222222222222","kind":"file","name":"received.txt","size":9,"from":"peer","output":"%s"}\n' "$output"
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TMP/fake-meshmsg"
cat >"$TMP/process-config/shell.qml" <<EOF
import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: testRoot
  property int stage: 0

  Plugin.Service { id: service; settings: ({ maxMessages: 20, refreshIntervalSec: 60 }) }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  Connections {
    target: service
    function onAttachmentBusyChanged() {
      if (service.attachmentBusy) return
      if (testRoot.stage === 1) {
        check(service.messages.length === 1 && service.messages[0].state === "shared", "share process did not complete")
        service.handleEvent('{"type":"attachment_offer","schema_version":1,"from":"peer","timestamp_ms":2,"offer_id":"22222222222222222222222222222222","kind":"file","name":"received.txt","size":9,"offer":"signed-input-capability"}')
        testRoot.stage = 2
        check(service.prepareDownload(service.messages[1].id, "$TMP/custom"), "download did not start")
      } else if (testRoot.stage === 2) {
        check(service.messages.length === 2 && service.messages[1].state === "complete", "download process did not complete")
        console.log("ATTACHMENT_PROCESS_TEST_PASS")
        testRoot.stage = 3
      }
    }
  }

  Timer {
    interval: 100
    running: true
    repeat: false
    onTriggered: {
      service.binaryPath = "$TMP/fake-meshmsg"
      service.installed = true
      service.running = true
      testRoot.stage = 1
      check(service.shareAttachment("$TMP/source.txt", "source.txt", "file"), "share did not start")
    }
  }
}
EOF

set +e
HOME="$TMP" TEST_ARGS="$TMP/args" TEST_STDIN="$TMP/stdin" timeout 5 qs -p "$TMP/process-config" --no-color >"$TMP/process.log" 2>&1
status=$?
set -e
[[ $status -eq 0 || $status -eq 124 ]]
grep -q 'ATTACHMENT_PROCESS_TEST_PASS' "$TMP/process.log"
[[ $(<"$TMP/stdin") == 'signed-input-capability' ]]
! grep -q 'signed-input-capability' "$TMP/args"
! grep -q 'signed-input-capability' "$TMP/process.log"
grep -q -- '--offer-stdin' "$TMP/args"

PICKED_FILE="$TMP/"'$(touch PWNED); snow ❄ 100% '
PICKED_DIR="$TMP/save folder ❄"
touch -- "$PICKED_FILE"
mkdir -- "$PICKED_DIR"
cat >"$TMP/.config/omarchy/plugins/eldar.meshmsg/attachment-picker.py" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
count=0
[[ ! -f ${TEST_PICKER_COUNT:?} ]] || count=$(<"$TEST_PICKER_COUNT")
count=$((count + 1))
printf '%s\n' "$count" >"$TEST_PICKER_COUNT"
printf '%s\n' "${1:-}" >>"${TEST_PICKER_ARGS:?}"
case $count in
  1) printf '%s\n' "${TEST_PICKER_FILE:?}" ;;
  2) exit 2 ;;
  3) echo 'portal backend failed' >&2; exit 1 ;;
  4) printf '%s\n' "${TEST_PICKER_DIR:?}" ;;
  5) kill -ABRT $$ ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$TMP/.config/omarchy/plugins/eldar.meshmsg/attachment-picker.py"
cat >"$TMP/process-config/picker-shell.qml" <<'EOF'
import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
  id: testRoot
  property int stage: 0
  property string preservedDraft: ""

  Plugin.Panel { id: panel }

  function check(condition, message) {
    if (!condition) throw new Error(message)
  }

  Timer {
    interval: 100
    running: true
    repeat: true
    onTriggered: {
      if (panel.attachmentPickerBusy) return
      if (testRoot.stage === 0) {
        testRoot.stage = 1
        check(panel.startAttachmentPicker("share-file", ""), "file picker did not start")
      } else if (testRoot.stage === 1 && panel.attachmentDraft !== null) {
        check(panel.attachmentDraft.path === Quickshell.env("TEST_PICKER_FILE"), "selected file path was corrupted")
        testRoot.preservedDraft = panel.attachmentDraft.path
        testRoot.stage = 2
        check(panel.startAttachmentPicker("share-folder", ""), "folder picker cancellation did not start")
      } else if (testRoot.stage === 2) {
        check(panel.attachmentDraft.path === testRoot.preservedDraft, "cancellation changed the draft")
        check(panel.attachmentPickerError === "", "cancellation surfaced an error")
        testRoot.stage = 3
        check(panel.startAttachmentPicker("share-folder", ""), "folder picker error did not start")
      } else if (testRoot.stage === 3 && panel.attachmentPickerError !== "") {
        check(panel.attachmentPickerError.indexOf("portal backend failed") !== -1, "picker error was not surfaced")
        check(panel.attachmentDraft.path === testRoot.preservedDraft, "picker error changed the draft")
        testRoot.stage = 4
        check(panel.startAttachmentPicker("save-folder", "missing-item"), "save-folder picker did not start")
      } else if (testRoot.stage === 4 && panel.attachmentPickerError !== "") {
        check(panel.attachmentPickerError.indexOf("no longer available") !== -1, "failed save-folder handoff was silent")
        testRoot.stage = 5
        check(panel.startAttachmentPicker("share-file", ""), "crashing picker did not start")
      } else if (testRoot.stage === 5 && panel.attachmentPickerError !== "") {
        check(!panel.attachmentPickerBusy, "picker crash left the panel busy")
        check(panel._attachmentPickerMode === "", "picker mode was not cleared")
        check(panel.pendingDownloadAttachmentId === "", "pending download ID was not cleared")
        check(panel.attachmentDraft.path === testRoot.preservedDraft, "picker crash changed the draft")
        console.log("ATTACHMENT_PICKER_PROCESS_TEST_PASS")
        testRoot.stage = 6
        Qt.quit()
      }
    }
  }
}
EOF
set +e
rm -f "$ROOT/PWNED" "$TMP/PWNED"
HOME="$TMP" TEST_PICKER_COUNT="$TMP/picker-count" TEST_PICKER_ARGS="$TMP/picker-args" \
  TEST_PICKER_FILE="$PICKED_FILE" TEST_PICKER_DIR="$PICKED_DIR" \
  timeout 12 qs -p "$TMP/process-config/picker-shell.qml" --no-color >"$TMP/picker-process.log" 2>&1
status=$?
set -e
[[ $status -eq 0 ]]
grep -q 'ATTACHMENT_PICKER_PROCESS_TEST_PASS' "$TMP/picker-process.log"
[[ ! -e "$ROOT/PWNED" && ! -e "$TMP/PWNED" ]]
[[ $(wc -l <"$TMP/picker-args") -eq 5 ]]
[[ $(sed -n '1p' "$TMP/picker-args") == share-file ]]
[[ $(sed -n '2p' "$TMP/picker-args") == share-folder ]]
[[ $(sed -n '3p' "$TMP/picker-args") == share-folder ]]
[[ $(sed -n '4p' "$TMP/picker-args") == save-folder ]]
[[ $(sed -n '5p' "$TMP/picker-args") == share-file ]]
! grep -q "$PICKED_FILE" "$TMP/picker-args"

echo 'attachment helpers, events, transfers, and crash-isolated picker tests: PASS'
