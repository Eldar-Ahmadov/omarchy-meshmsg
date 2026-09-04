import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property bool installed: false
  property string binaryPath: ""
  property string version: ""
  property bool running: false
  property bool endpointOnline: false
  property bool topicJoined: false
  property int neighbors: 0
  property bool advertisesSelf: false
  property bool hasInvite: false
  property int bootstrapPeerCount: 0
  property bool selfAdvertised: false
  property string peer: ""
  property string topic: ""
  property string localEndpoint: ""
  property double statusUpdatedAt: 0
  readonly property string stateDir: {
    var configured = Quickshell.env("MESHMSG_STATE_DIR")
    if (configured) return configured
    var dataHome = Quickshell.env("XDG_DATA_HOME")
    if (!dataHome) dataHome = Quickshell.env("HOME") + "/.local/share"
    return dataHome + "/meshmsg"
  }
  property string statusText: "Checking…"
  property string lastError: ""
  property string actionStatus: ""
  property var messages: []
  property bool starting: false
  property bool stopping: false
  property bool joining: false
  property bool sending: false
  property bool attachmentBusy: false
  property bool copyingInvite: false
  property bool inviteCopied: false
  property string inviteCopyError: ""

  signal incomingActivity()
  signal timelineItemAdded()

  property int _nextTimelineId: 1
  property var _attachmentOffers: ({})
  property string _activeAttachmentId: ""
  property string _activeAttachmentOperation: ""
  property string _activeAttachmentOutput: ""
  property string _downloadOffer: ""
  property string _destinationOutput: ""
  property string _destinationError: ""
  property string _attachmentOutput: ""
  property string _attachmentError: ""
  property string _joinToken: ""
  property string _inviteToken: ""
  property string _sendBody: ""
  property string _statusOutput: ""
  property string _statusError: ""
  property string _sendOutput: ""
  property string _sendError: ""
  property string _joinOutput: ""
  property string _joinError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _inviteOutput: ""
  property string _inviteError: ""

  readonly property int refreshIntervalSec: boundedInt("refreshIntervalSec", 5, 2, 60)
  readonly property int maxMessages: boundedInt("maxMessages", 100, 20, 500)
  readonly property bool busy: starting || stopping || joining || sending || attachmentBusy
  readonly property double maxAttachmentBytes: 1024 * 1024 * 1024

  function boundedInt(name, fallback, minimum, maximum) {
    var value = settings && settings[name] !== undefined ? parseInt(settings[name], 10) : fallback
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function cleanError(text, fallback) {
    var value = String(text || "").replace(/^error:\s*/i, "").replace(/\s+/g, " ").trim()
    if (value === "") value = fallback
    return value.length > 220 ? value.substring(0, 217) + "…" : value
  }

  function stripFinalLineEnding(text) {
    var value = String(text || "")
    if (value.endsWith("\n")) {
      value = value.substring(0, value.length - 1)
      if (value.endsWith("\r")) value = value.substring(0, value.length - 1)
    }
    return value
  }

  function shortPeer(value) {
    var text = String(value || "")
    return text.length > 12 ? text.substring(0, 8) + "…" + text.substring(text.length - 4) : text
  }

  function nextTimelineId(prefix) {
    return String(prefix || "item") + ":" + String(_nextTimelineId++)
  }

  function attachmentIndex(offerId, outputPath, timelineId, from) {
    var i
    var item
    if (timelineId) {
      for (i = 0; i < messages.length; i++) {
        item = messages[i] || {}
        if (String(item.itemKind || "") === "attachment"
            && String(item.id || "") === String(timelineId)) return i
      }
    }
    if (offerId) {
      for (i = 0; i < messages.length; i++) {
        item = messages[i] || {}
        if (String(item.itemKind || "") === "attachment"
            && String(item.offerId || "") === String(offerId)
            && (!from || String(item.from || "") === String(from))) return i
      }
    }
    if (outputPath) {
      for (i = 0; i < messages.length; i++) {
        item = messages[i] || {}
        if (String(item.itemKind || "") === "attachment"
            && String(item.outputPath || "") === String(outputPath)) return i
      }
    }
    return -1
  }

  function replaceTimelineItem(index, changes) {
    if (index < 0 || index >= messages.length) return false
    var next = messages.slice(0)
    var previous = next[index] || {}
    var replacement = {}
    for (var key in previous) replacement[key] = previous[key]
    for (var change in changes) replacement[change] = changes[change]
    next[index] = replacement
    messages = next
    return true
  }

  function validAttachment(event, requireOffer) {
    var kind = String(event.kind || "")
    var name = String(event.name || "")
    var offerId = String(event.offer_id || "")
    var size = Number(event.size)
    if (Number(event.schema_version) !== 1) return false
    if (kind !== "file" && kind !== "directory_tar_v1") return false
    if (!/^[0-9a-fA-F]{32}$/.test(offerId) || name === "" || name.length > 255 || !isFinite(size) || size < 0 || size > maxAttachmentBytes) return false
    if (/[\\\/<>:"|?*\x00-\x1f\x7f]/.test(name) || name === "." || name === ".." || /[. ]$/.test(name)) return false
    var stem = name.split(".")[0].toUpperCase()
    if (/^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$/.test(stem)) return false
    if (requireOffer && (String(event.offer || "") === "" || String(event.from || "") === "")) return false
    return true
  }

  function rememberOffer(timelineId, offer) {
    var next = {}
    for (var key in _attachmentOffers) next[key] = _attachmentOffers[key]
    next[String(timelineId)] = String(offer)
    _attachmentOffers = next
  }

  function forgetOffer(timelineId) {
    var id = String(timelineId || "")
    var next = {}
    for (var key in _attachmentOffers) {
      if (key !== id) next[key] = _attachmentOffers[key]
    }
    _attachmentOffers = next
  }

  function removeDuplicateAttachment(offerId, from, keepId) {
    var next = []
    var changed = false
    for (var i = 0; i < messages.length; i++) {
      var item = messages[i] || {}
      if (String(item.itemKind || "") === "attachment"
          && String(item.offerId || "") === String(offerId)
          && String(item.from || "") === String(from)
          && String(item.id || "") !== String(keepId)) {
        forgetOffer(item.id)
        changed = true
      } else {
        next.push(item)
      }
    }
    if (changed) messages = next
  }

  function upsertAttachment(event, direction, useActiveItem) {
    var incoming = direction === "incoming"
    if (!validAttachment(event, incoming)) return false
    var offerId = String(event.offer_id)
    var from = String(event.from || "")
    var activeId = !incoming && useActiveItem === true ? _activeAttachmentId : ""
    var stableId = "attachment:" + direction + ":" + from + ":" + offerId
    var index = attachmentIndex(offerId, "", activeId || stableId, from)
    var timestamp = Number(event.timestamp_ms || Date.now())
    if (!isFinite(timestamp) || timestamp <= 0) timestamp = Date.now()
    var existingState = index >= 0 ? String(messages[index].state || "") : ""
    var timelineId = index >= 0 ? String(messages[index].id || stableId) : stableId
    if (incoming && existingState !== "complete") rememberOffer(timelineId, event.offer)
    var changes = {
      itemKind: "attachment",
      offerId: offerId,
      direction: direction,
      outgoing: !incoming,
      from: from,
      name: String(event.name),
      attachmentKind: String(event.kind),
      size: Number(event.size),
      timestampMs: timestamp,
      state: incoming ? (existingState || "offered") : "shared",
      deliveryAcknowledged: event.delivery_acknowledged === true,
      error: ""
    }
    if (index >= 0) {
      replaceTimelineItem(index, changes)
      if (activeId !== "") removeDuplicateAttachment(offerId, from, timelineId)
    } else {
      changes.id = stableId
      appendMessage(changes)
      if (incoming) incomingActivity()
    }
    return true
  }

  function updateActiveAttachment(changes) {
    var index = attachmentIndex("", "", _activeAttachmentId)
    return replaceTimelineItem(index, changes)
  }

  function attachmentItem(id) {
    var index = attachmentIndex("", "", id)
    return index >= 0 ? messages[index] : null
  }

  function refresh() {
    if (statusProcess.running || !installed) return
    _statusOutput = ""
    _statusError = ""
    statusProcess.command = [binaryPath, "--json", "status"]
    statusProcess.running = true
  }

  function refreshAll() {
    if (whichProcess.running) return
    whichProcess.output = ""
    whichProcess.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/eldar.meshmsg/resolve-meshmsg.sh"]
    whichProcess.running = true
  }

  function refreshVersion() {
    if (versionProcess.running || !installed) return
    versionProcess.output = ""
    versionProcess.command = [binaryPath, "--version"]
    versionProcess.running = true
  }

  function setUnavailable(message) {
    running = false
    endpointOnline = false
    topicJoined = false
    neighbors = 0
    statusText = message || "Daemon stopped"
    if (listenProcess.running) listenProcess.running = false
  }

  function parseStatus(raw) {
    try {
      var value = JSON.parse(String(raw || "").trim())
      if (value.type !== "status") throw new Error("unexpected status response")
      running = value.running === true
      endpointOnline = value.endpoint_online === true
      topicJoined = value.topic_joined === true
      neighbors = Number(value.neighbors || 0)
      advertisesSelf = value.advertises_self === true
      hasInvite = value.has_invite === true
      bootstrapPeerCount = Number(value.bootstrap_peer_count || 0)
      selfAdvertised = value.self_advertised === true
      peer = String(value.peer || "")
      topic = String(value.topic || "")
      localEndpoint = String(value.local_endpoint || value.socket || "")
      statusUpdatedAt = Date.now()
      statusText = !endpointOnline ? "Connecting…" : (!topicJoined ? "Waiting for peers" : "Connected")
      lastError = ""
      starting = false
      stopping = false
      if (running && !listenProcess.running && !listenRestart.running) startListening()
    } catch (error) {
      setUnavailable("Status error")
      lastError = "Could not parse meshmsg status"
    }
  }

  function startListening() {
    if (!installed || !running || listenProcess.running) return
    listenProcess.command = [binaryPath, "--json", "listen"]
    listenProcess.running = true
  }

  function handleEvent(line, source) {
    var text = String(line || "").trim()
    if (text === "") return
    try {
      var event = JSON.parse(text)
      var type = String(event.type || "")
      if (type === "message" || type === "queued") {
        appendMessage({
          id: nextTimelineId("message"),
          itemKind: "text",
          type: type,
          from: String(event.from || ""),
          body: String(event.body || ""),
          timestampMs: Number(event.timestamp_ms || Date.now()),
          outgoing: type === "queued"
        })
        if (type === "message") incomingActivity()
      } else if (type === "attachment_offer") {
        upsertAttachment(event, "incoming", false)
      } else if (type === "attachment_shared") {
        upsertAttachment(event, "outgoing", source === "attachment_command")
      } else if (type === "download_started") {
        var startedOutput = String(event.output || "")
        if (_activeAttachmentOperation === "download"
            && startedOutput !== ""
            && startedOutput === _activeAttachmentOutput) {
          updateActiveAttachment({ state: "preparing_download", outputPath: startedOutput, error: "" })
        }
      } else if (type === "download_progress") {
        var progressOutput = String(event.output || "")
        var received = Number(event.received_bytes || 0)
        var total = Number(event.total_bytes || 0)
        if (_activeAttachmentOperation === "download"
            && progressOutput !== ""
            && progressOutput === _activeAttachmentOutput
            && isFinite(received) && isFinite(total) && received >= 0 && total >= 0) {
          updateActiveAttachment({
            state: "downloading",
            outputPath: progressOutput,
            receivedBytes: Math.min(received, total),
            totalBytes: total,
            error: ""
          })
        }
      } else if (type === "download_complete") {
        var completedOfferId = String(event.offer_id || "")
        var completedOutput = String(event.output || "")
        var completedFrom = String(event.from || "")
        var activeDownloadId = _activeAttachmentOperation === "download"
          && completedOutput === _activeAttachmentOutput ? _activeAttachmentId : ""
        var completedIndex = attachmentIndex(completedOfferId, completedOutput, activeDownloadId, completedFrom)
        if (Number(event.schema_version) === 1 && completedOutput !== "" && completedIndex >= 0) {
          var finalOfferId = completedOfferId || String(messages[completedIndex].offerId || "")
          var completedTimelineId = String(messages[completedIndex].id || "")
          replaceTimelineItem(completedIndex, {
            offerId: finalOfferId,
            state: "complete",
            outputPath: completedOutput,
            receivedBytes: Number(event.size || messages[completedIndex].size || 0),
            totalBytes: Number(event.size || messages[completedIndex].size || 0),
            error: ""
          })
          forgetOffer(completedTimelineId)
        }
      } else if (type === "peer_up" || type === "peer_down") {
        refreshSoon.restart()
      } else if (type === "lagged" || type === "error") {
        lastError = cleanError(event.message, type === "lagged" ? "Some messages were missed" : "Meshmsg event error")
      }
    } catch (error) {
      // Never log the raw line: malformed attachment events may contain a reusable capability.
      console.warn("meshmsg: ignored invalid event")
    }
  }

  function appendMessage(message) {
    var next = messages.slice(0)
    next.push(message)
    while (next.length > maxMessages) {
      var removeIndex = 0
      if (_activeAttachmentId !== "" && String(next[0].id || "") === _activeAttachmentId) {
        removeIndex = -1
        for (var i = 1; i < next.length; i++) {
          if (String(next[i].id || "") !== _activeAttachmentId) {
            removeIndex = i
            break
          }
        }
        if (removeIndex < 0) break
      }
      var removed = next[removeIndex] || {}
      if (String(removed.itemKind || "") === "attachment") forgetOffer(removed.id)
      next.splice(removeIndex, 1)
    }
    messages = next
    timelineItemAdded()
  }

  function sendMessage(body) {
    var text = String(body || "").trim()
    if (!running || sending || text === "") return false
    _sendOutput = ""
    _sendError = ""
    _sendBody = text
    sending = true
    sendProcess.stdinEnabled = true
    sendProcess.command = [binaryPath, "--json", "send", "--message-stdin"]
    sendProcess.running = true
    return true
  }

  function shareAttachment(path, displayName, kind) {
    var source = String(path || "")
    var name = String(displayName || "")
    var attachmentKind = String(kind || "")
    if (!running || attachmentBusy || source === "" || name === "") return false
    if (attachmentKind !== "file" && attachmentKind !== "directory_tar_v1") return false
    _activeAttachmentId = nextTimelineId("attachment-local")
    _activeAttachmentOperation = "share"
    _activeAttachmentOutput = ""
    _attachmentOutput = ""
    _attachmentError = ""
    attachmentBusy = true
    appendMessage({
      id: _activeAttachmentId,
      itemKind: "attachment",
      offerId: "",
      direction: "outgoing",
      outgoing: true,
      from: peer,
      name: name,
      attachmentKind: attachmentKind,
      size: 0,
      timestampMs: Date.now(),
      state: "sharing",
      sourcePath: source,
      deliveryAcknowledged: false,
      error: ""
    })
    attachmentProcess.stdinEnabled = false
    attachmentProcess.command = [binaryPath, "--json", "share", source]
    attachmentProcess.running = true
    return true
  }

  function prepareDownload(timelineId, parentDirectory) {
    var id = String(timelineId || "")
    var token = String(_attachmentOffers[id] || "")
    var index = attachmentIndex("", "", id)
    if (!running || attachmentBusy || index < 0 || token === "") return false
    var item = messages[index] || {}
    if (String(item.attachmentKind || "") !== "file" && String(item.attachmentKind || "") !== "directory_tar_v1") return false
    _activeAttachmentId = String(item.id || "")
    _activeAttachmentOperation = "download"
    _activeAttachmentOutput = ""
    _downloadOffer = token
    _destinationOutput = ""
    _destinationError = ""
    _attachmentOutput = ""
    _attachmentError = ""
    attachmentBusy = true
    replaceTimelineItem(index, {
      state: "preparing_download",
      error: "",
      receivedBytes: 0,
      totalBytes: Number(item.size || 0),
      destinationParent: String(parentDirectory || "")
    })
    var command = [
      Quickshell.env("HOME") + "/.config/omarchy/plugins/eldar.meshmsg/attachment-destination.sh",
      String(item.attachmentKind),
      String(item.name)
    ]
    var parent = String(parentDirectory || "")
    if (parent !== "") command.push(parent)
    destinationProcess.command = command
    destinationProcess.running = true
    return true
  }

  function retryAttachment(timelineId) {
    var item = attachmentItem(timelineId)
    if (!item || attachmentBusy) return false
    if (String(item.direction || "") === "incoming")
      return prepareDownload(item.id, String(item.destinationParent || ""))
    var source = String(item.sourcePath || "")
    if (!running || source === "") return false
    _activeAttachmentId = String(item.id || "")
    _activeAttachmentOperation = "share"
    _activeAttachmentOutput = ""
    _attachmentOutput = ""
    _attachmentError = ""
    attachmentBusy = true
    updateActiveAttachment({ state: "sharing", error: "", timestampMs: Date.now() })
    attachmentProcess.stdinEnabled = false
    attachmentProcess.command = [binaryPath, "--json", "share", source]
    attachmentProcess.running = true
    return true
  }

  function failActiveAttachment(message) {
    var index = attachmentIndex("", "", _activeAttachmentId)
    if (index >= 0 && String(messages[index].state || "") !== "complete")
      replaceTimelineItem(index, { state: "failed", error: cleanError(message, "Attachment operation failed") })
    _downloadOffer = ""
    _activeAttachmentOutput = ""
    _activeAttachmentOperation = ""
    _activeAttachmentId = ""
    attachmentBusy = false
  }

  function finishActiveAttachment() {
    _downloadOffer = ""
    _activeAttachmentOutput = ""
    _activeAttachmentOperation = ""
    _activeAttachmentId = ""
    attachmentBusy = false
  }

  function startDaemon() {
    if (!installed || running || starting) return
    _actionOutput = ""
    _actionError = ""
    lastError = ""
    actionStatus = "Starting daemon…"
    starting = true
    startProcess.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/eldar.meshmsg/start-daemon.sh"]
    startProcess.running = true
  }

  function stopDaemon() {
    if (!running || stopping) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = "Stopping daemon…"
    stopping = true
    stopProcess.command = [binaryPath, "--json", "stop"]
    stopProcess.running = true
  }

  function joinChat(token, replaceExisting) {
    var value = String(token || "").trim()
    if (!installed || running || joining || value === "") return false
    _joinOutput = ""
    _joinError = ""
    _joinToken = value
    lastError = ""
    actionStatus = "Joining chat…"
    joining = true
    var command = [binaryPath, "--json", "join", "--token-stdin"]
    if (replaceExisting === true) command.push("--force")
    joinProcess.stdinEnabled = true
    joinProcess.command = command
    joinProcess.running = true
    return true
  }

  function copyInvite() {
    if (!installed || !hasInvite || copyingInvite) return false
    _inviteOutput = ""
    _inviteError = ""
    inviteCopyError = ""
    inviteCopied = false
    copyingInvite = true
    inviteProcess.command = [binaryPath, "--json", "invite"]
    inviteProcess.running = true
    return true
  }

  function clearMessages() {
    messages = []
    _attachmentOffers = ({})
  }

  Component.onCompleted: root.refreshAll()

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: root.installed
    onTriggered: root.refresh()
  }

  Timer {
    id: refreshSoon
    interval: 700
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: listenRestart
    interval: 1800
    repeat: false
    onTriggered: if (root.running) root.startListening()
  }

  Timer {
    id: actionClear
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: inviteCopiedClear
    interval: 1500
    repeat: false
    onTriggered: root.inviteCopied = false
  }

  Process {
    id: whichProcess
    property string output: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: whichProcess.output = String(text || "").trim() }
    onExited: function(exitCode) {
      root.binaryPath = exitCode === 0 ? whichProcess.output : ""
      root.installed = root.binaryPath !== ""
      if (root.installed) {
        root.refreshVersion()
        root.refresh()
      } else {
        root.version = ""
        root.setUnavailable("Not installed")
      }
    }
  }

  Process {
    id: versionProcess
    property string output: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: versionProcess.output = String(text || "").trim() }
    onExited: function(exitCode) {
      root.version = exitCode === 0
        ? versionProcess.output.replace(/^meshmsg\s+/i, "")
        : ""
    }
  }

  Process {
    id: statusProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      if (exitCode === 0) root.parseStatus(root._statusOutput)
      else {
        root.setUnavailable("Daemon stopped")
        if (!root.starting && !root.stopping) root.lastError = ""
      }
    }
  }

  Process {
    id: listenProcess
    stdout: SplitParser { onRead: function(line) { root.handleEvent(line, "listener") } }
    stderr: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (value !== "" && root.running) root.lastError = root.cleanError(value, "Listener stopped")
      }
    }
    onExited: function(exitCode) {
      if (root.running) listenRestart.restart()
    }
  }

  Process {
    id: sendProcess
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._sendOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._sendError = text }
    onStarted: {
      write(root._sendBody)
      root._sendBody = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      root._sendBody = ""
      root.sending = false
      if (exitCode !== 0) root.lastError = root.cleanError(root._sendError || root._sendOutput, "Could not send message")
      else root.lastError = ""
    }
  }

  Process {
    id: destinationProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._destinationOutput = root.stripFinalLineEnding(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._destinationError = text }
    onExited: function(exitCode) {
      if (exitCode !== 0 || root._destinationOutput === "") {
        root.failActiveAttachment(root._destinationError || "Could not choose a download destination")
        return
      }
      root._activeAttachmentOutput = root._destinationOutput
      root.updateActiveAttachment({
        state: "queued",
        outputPath: root._activeAttachmentOutput,
        receivedBytes: 0,
        error: ""
      })
      attachmentProcess.stdinEnabled = true
      attachmentProcess.command = [
        root.binaryPath,
        "--json",
        "download",
        "--offer-stdin",
        "--output",
        root._activeAttachmentOutput
      ]
      attachmentProcess.running = true
    }
  }

  Process {
    id: attachmentProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._attachmentOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._attachmentError = text }
    onStarted: {
      if (root._activeAttachmentOperation === "download") {
        write(root._downloadOffer)
        root._downloadOffer = ""
        stdinEnabled = false
      }
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      var output = String(root._attachmentOutput || "").trim()
      if (exitCode === 0 && output !== "") root.handleEvent(output, "attachment_command")
      var activeItem = root.attachmentItem(root._activeAttachmentId)
      var state = String(activeItem && activeItem.state || "")
      var expectedState = root._activeAttachmentOperation === "share" ? "shared" : "complete"
      if (exitCode !== 0) {
        root.failActiveAttachment(root._attachmentError || root._attachmentOutput)
      } else if (state !== expectedState) {
        root.failActiveAttachment("Could not parse the attachment response")
      } else {
        root.finishActiveAttachment()
      }
      root._attachmentOutput = ""
      root._attachmentError = ""
    }
  }

  Process {
    id: startProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.starting = false
        root.actionStatus = ""
        root.lastError = root.cleanError(root._actionError || root._actionOutput, "Could not start daemon")
      } else {
        root.actionStatus = "Daemon starting…"
        actionClear.restart()
        refreshSoon.restart()
      }
    }
  }

  Process {
    id: stopProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      root.stopping = false
      if (exitCode !== 0) root.lastError = root.cleanError(root._actionError || root._actionOutput, "Could not stop daemon")
      else {
        root.lastError = ""
        root.actionStatus = "Daemon stopped"
        root.setUnavailable("Daemon stopped")
        actionClear.restart()
      }
    }
  }

  Process {
    id: inviteProcess
    stdout: SplitParser { onRead: function(line) { root._inviteOutput = String(line || "") } }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._inviteError = text }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.copyingInvite = false
        root.inviteCopyError = root.cleanError(root._inviteError || root._inviteOutput, "Could not read invite")
        return
      }
      try {
        var value = JSON.parse(String(root._inviteOutput || "").trim())
        var token = String(value.token || "")
        if (value.type !== "invite" || token === "") throw new Error("missing invite token")
        root._inviteOutput = ""
        root._inviteToken = token
        clipboardProcess.stdinEnabled = true
        clipboardProcess.command = ["wl-copy"]
        clipboardProcess.running = true
      } catch (error) {
        root.copyingInvite = false
        root.inviteCopyError = "Could not parse meshmsg invite"
      }
    }
  }

  Process {
    id: clipboardProcess
    stdinEnabled: true
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._inviteError = text }
    onStarted: {
      write(root._inviteToken)
      root._inviteToken = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      root._inviteToken = ""
      root.copyingInvite = false
      if (exitCode === 0) {
        root.inviteCopyError = ""
        root.inviteCopied = true
        inviteCopiedClear.restart()
      } else {
        root.inviteCopyError = root.cleanError(root._inviteError, "Could not copy invite")
      }
    }
  }

  Process {
    id: joinProcess
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._joinOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._joinError = text }
    onStarted: {
      write(root._joinToken + "\n")
      root._joinToken = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      root.joining = false
      root._joinToken = ""
      if (exitCode !== 0) {
        root.actionStatus = ""
        root.lastError = root.cleanError(root._joinError || root._joinOutput, "Could not join chat")
      } else {
        root.messages = []
        root.lastError = ""
        root.actionStatus = "Chat joined"
        actionClear.restart()
        root.startDaemon()
      }
    }
  }
}
