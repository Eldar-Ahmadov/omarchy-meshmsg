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
  property string alias: ""
  property bool aliasEnabled: false
  property string capturedHostname: ""
  property string customAlias: ""
  property int advertisedAliases: 0
  property var ipcCapabilities: []
  readonly property bool privateSendAvailable: ipcCapabilities.indexOf("private_send_v1") !== -1
  readonly property bool peerDirectoryAvailable: ipcCapabilities.indexOf("peer_directory_v1") !== -1
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
  // Private state intentionally lives outside the broadcast/attachment timeline.
  // Conversation objects are { peer, messages, unreadCount, lastTimestampMs }.
  property var privateMessages: []
  property var conversations: []
  property var knownPeers: []
  readonly property int privateUnreadCount: {
    var count = 0
    for (var i = 0; i < conversations.length; i++) count += Number(conversations[i].unreadCount || 0)
    return count
  }
  property bool privateSending: false
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
  signal privateMessageAccepted(string requestedRecipient, string canonicalPeer)

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
  property string _privateSendBody: ""
  property string _privateSendRecipient: ""
  property string _privateSendOutput: ""
  property string _privateSendError: ""
  property string _statusOutput: ""
  property string _statusError: ""
  property string _peersOutput: ""
  property string _peersError: ""
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
  readonly property bool busy: starting || stopping || joining || sending || privateSending || attachmentBusy
  readonly property int maxPrivateMessages: boundedInt("maxPrivateMessages", maxMessages, 20, 500)
  readonly property int maxConversations: boundedInt("maxConversations", 50, 5, 200)
  readonly property int maxKnownPeers: boundedInt("maxKnownPeers", 100, 10, 500)
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
    ipcCapabilities = []
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
      alias = String(value.alias || "")
      aliasEnabled = value.alias_enabled === true
      capturedHostname = String(value.captured_hostname || "")
      customAlias = value.custom_alias === null || value.custom_alias === undefined ? "" : String(value.custom_alias)
      advertisedAliases = Math.max(0, Number(value.advertised_aliases || 0))
      ipcCapabilities = Array.isArray(value.ipc_capabilities) ? value.ipc_capabilities.map(function(capability) { return String(capability) }) : []
      statusUpdatedAt = Date.now()
      statusText = !endpointOnline ? "Connecting…" : (!topicJoined ? "Waiting for peers" : "Connected")
      lastError = ""
      starting = false
      stopping = false
      if (running && !listenProcess.running && !listenRestart.running) startListening()
      if (running && peerDirectoryAvailable) refreshPeers()
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

  function refreshPeers() {
    if (!installed || !running || !peerDirectoryAvailable || peersProcess.running) return false
    _peersOutput = ""
    _peersError = ""
    peersProcess.command = [binaryPath, "--json", "peers"]
    peersProcess.running = true
    return true
  }

  function directoryPeer(raw, expired) {
    if (!raw || typeof raw !== "object") return null
    var key = String(raw.public_key || "")
    var seen = Number(raw.last_seen_ms), expires = Number(raw.expires_at_ms)
    if (!canonicalPeer(key) || key === peer || (raw.alias !== null && raw.alias !== undefined && typeof raw.alias !== "string")
        || typeof raw.online !== "boolean" || !isFinite(seen) || seen < 0 || !isFinite(expires) || expires < seen) return null
    return { peer: key, publicKey: key, alias: raw.alias === null || raw.alias === undefined ? "" : String(raw.alias),
      online: expired === true ? false : raw.online, lastSeenMs: seen, expiresAtMs: expires }
  }

  function applyPeersSnapshot(event) {
    if (Number(event.schema_version) !== 1 || !Array.isArray(event.peers) || !event.self || typeof event.self !== "object") return false
    if (!canonicalPeer(event.self.public_key) || typeof event.self.online !== "boolean"
        || (event.self.alias !== null && event.self.alias !== undefined && typeof event.self.alias !== "string")) return false
    var next = [], seen = {}
    for (var i = 0; i < event.peers.length; i++) {
      var item = directoryPeer(event.peers[i], false)
      if (!item || seen[item.peer]) return false
      seen[item.peer] = true
      next.push(item)
    }
    if (next.length > maxKnownPeers) next = next.slice(0, maxKnownPeers)
    knownPeers = next
    return true
  }

  function applyPeerLifecycle(event, expired) {
    if (Number(event.schema_version) !== 1) return false
    var item = directoryPeer(event.peer, expired)
    if (!item) return false
    var next = [], replaced = false
    for (var i = 0; i < knownPeers.length; i++) {
      if (String(knownPeers[i].peer || "") === item.peer) { replaced = true; if (!expired) next.push(item) }
      else next.push(knownPeers[i])
    }
    if (!replaced && !expired) next.push(item)
    while (next.length > maxKnownPeers) next.pop()
    knownPeers = next
    return true
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
      } else if (type === "private_message") {
        handlePrivateMessage(event)
      } else if (type === "peers_snapshot") {
        applyPeersSnapshot(event)
      } else if (type === "peer_discovered" || type === "peer_updated") {
        applyPeerLifecycle(event, false)
      } else if (type === "peer_expired") {
        applyPeerLifecycle(event, true)
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
        if (type === "peer_up") rememberPeer(event.peer, Date.now())
        refreshSoon.restart()
      } else if (type === "lagged" || type === "error") {
        lastError = cleanError(event.message, type === "lagged" ? "Some messages were missed" : "Meshmsg event error")
        if (type === "lagged") refreshPeers()
      }
    } catch (error) {
      // Never log the raw line: malformed attachment events may contain a reusable capability.
      console.warn("meshmsg: ignored invalid event")
    }
  }

  function utf8Bytes(value) {
    return unescape(encodeURIComponent(String(value || ""))).length
  }

  function canonicalPeer(value) {
    return /^[0-9a-f]{64}$/.test(String(value || ""))
  }

  function rememberPeer(value, timestamp) {
    var id = String(value || "")
    if (!canonicalPeer(id) || id === peer) return
    var next = [], found = false
    for (var i = 0; i < knownPeers.length; i++) {
      var entry = knownPeers[i] || {}
      if (String(entry.peer || "") === id) {
        var copy = {}
        for (var field in entry) copy[field] = entry[field]
        copy.peer = id
        copy.publicKey = String(copy.publicKey || id)
        copy.lastSeenMs = Math.max(Number(entry.lastSeenMs || 0), Number(timestamp || Date.now()))
        next.push(copy)
        found = true
      } else next.push(entry)
    }
    if (!found) next.push({ peer: id, publicKey: id, alias: "", online: false, lastSeenMs: Number(timestamp || Date.now()), expiresAtMs: 0 })
    next.sort(function(a, b) { return Number(b.lastSeenMs) - Number(a.lastSeenMs) })
    while (next.length > maxKnownPeers) next.pop()
    knownPeers = next
  }

  function rebuildConversations(incomingPeer) {
    var oldUnread = {}
    for (var i = 0; i < conversations.length; i++) oldUnread[String(conversations[i].peer)] = Number(conversations[i].unreadCount || 0)
    var grouped = {}
    for (i = 0; i < privateMessages.length; i++) {
      var item = privateMessages[i]
      var other = item.outgoing ? String(item.to) : String(item.from)
      if (!grouped[other]) grouped[other] = []
      grouped[other].push(item)
    }
    var next = []
    for (var key in grouped) {
      var items = grouped[key]
      var unread = Number(oldUnread[key] || 0)
      if (incomingPeer === key) unread++
      next.push({ peer: key, messages: items, unreadCount: unread, lastTimestampMs: Number(items[items.length - 1].timestampMs || 0) })
    }
    next.sort(function(a, b) { return b.lastTimestampMs - a.lastTimestampMs })
    while (next.length > maxConversations) next.pop()
    conversations = next
  }

  function appendPrivateMessage(item, incoming) {
    var next = privateMessages.slice(0)
    next.push(item)
    while (next.length > maxPrivateMessages) next.shift()
    privateMessages = next
    var other = incoming ? String(item.from) : String(item.to)
    rememberPeer(other, item.timestampMs)
    rebuildConversations(incoming ? other : "")
    timelineItemAdded()
    if (incoming) incomingActivity()
  }

  function handlePrivateMessage(event) {
    var from = String(event.from || ""), id = String(event.message_id || "")
    var timestamp = Number(event.timestamp_ms), body = event.body
    if (Number(event.schema_version) !== 1 || event.private !== true || !canonicalPeer(from)
        || !/^[0-9a-f]{32}$/.test(id) || typeof body !== "string"
        || !isFinite(timestamp) || timestamp <= 0 || event.acceptance_acknowledged !== true
        || event.durable !== false || event.read !== false) return false
    for (var i = 0; i < privateMessages.length; i++) {
      if (!privateMessages[i].outgoing && privateMessages[i].from === from && privateMessages[i].messageId === id) return false
    }
    appendPrivateMessage({ id: "private:incoming:" + from + ":" + id, itemKind: "text", private: true,
      outgoing: false, from: from, to: peer, body: body, messageId: id, timestampMs: timestamp,
      acceptanceAcknowledged: true, durable: false, read: false }, true)
    return true
  }

  function markConversationRead(value) {
    var id = String(value || ""), next = [], changed = false
    for (var i = 0; i < conversations.length; i++) {
      var conversation = conversations[i]
      if (String(conversation.peer) === id && Number(conversation.unreadCount || 0) !== 0) {
        next.push({ peer: conversation.peer, messages: conversation.messages, unreadCount: 0,
          lastTimestampMs: conversation.lastTimestampMs })
        changed = true
      } else next.push(conversation)
    }
    if (changed) conversations = next
    return changed
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

  function sendPrivateMessage(recipient, body) {
    var to = String(recipient || "").trim()
    var text = String(body || "").trim()
    if (!running || privateSending || sending || !privateSendAvailable || to === "" || text === "") return false
    // Recipient is passed only to --to; the body is always delivered over stdin.
    _privateSendRecipient = to
    _privateSendBody = text
    _privateSendOutput = ""
    _privateSendError = ""
    privateSending = true
    privateSendProcess.stdinEnabled = true
    privateSendProcess.command = [binaryPath, "--json", "send", "--to", to, "--message-stdin"]
    privateSendProcess.running = true
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

  function removeMessage(timelineId) {
    var id = String(timelineId || "")
    if (id === "" || (attachmentBusy && id === _activeAttachmentId)) return false
    for (var i = 0; i < messages.length; i++) {
      var item = messages[i] || {}
      if (String(item.id || "") !== id) continue
      if (String(item.itemKind || "") === "attachment") forgetOffer(id)
      var next = messages.slice(0)
      next.splice(i, 1)
      messages = next
      return true
    }
    return false
  }

  function clearMessages() {
    messages = []
    _attachmentOffers = ({})
  }

  function clearPrivateMessages() {
    privateMessages = []
    conversations = []
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
    id: peersProcess
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._peersOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._peersError = text }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      try {
        var value = JSON.parse(String(root._peersOutput || "").trim())
        if (value.type !== "peers_snapshot" || !root.applyPeersSnapshot(value)) throw new Error("invalid snapshot")
      } catch (error) {
        root.lastError = "Could not parse meshmsg peer directory"
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
    id: privateSendProcess
    stdinEnabled: true
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root._privateSendOutput = text }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root._privateSendError = text }
    onStarted: {
      write(root._privateSendBody)
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      var body = root._privateSendBody
      var requested = root._privateSendRecipient
      root._privateSendBody = ""
      root._privateSendRecipient = ""
      root.privateSending = false
      if (exitCode !== 0) {
        root.lastError = root.cleanError(root._privateSendError || root._privateSendOutput, "Could not send private message")
        return
      }
      try {
        var value = JSON.parse(String(root._privateSendOutput || "").trim())
        var keys = Object.keys(value).sort().join(",")
        var expected = "acceptance_acknowledged,body_bytes,durable,message_id,read,schema_version,timestamp_ms,to,type"
        var timestamp = Number(value.timestamp_ms)
        if (keys !== expected || value.type !== "private_accepted" || typeof value.schema_version !== "number" || value.schema_version !== 1
            || typeof value.to !== "string" || !root.canonicalPeer(value.to) || (root.canonicalPeer(requested) && value.to !== requested)
            || typeof value.message_id !== "string" || !/^[0-9a-f]{32}$/.test(value.message_id)
            || typeof value.timestamp_ms !== "number" || !isFinite(timestamp) || timestamp <= 0 || Math.floor(timestamp) !== timestamp
            || typeof value.body_bytes !== "number" || value.body_bytes !== root.utf8Bytes(body) || Math.floor(value.body_bytes) !== value.body_bytes
            || value.acceptance_acknowledged !== true
            || value.durable !== false || value.read !== false) throw new Error("invalid acceptance")
        root.appendPrivateMessage({ id: "private:outgoing:" + value.to + ":" + value.message_id,
          itemKind: "text", private: true, outgoing: true, from: root.peer, to: value.to,
          requestedRecipient: requested, body: body, messageId: value.message_id, timestampMs: timestamp,
          acceptanceAcknowledged: true, durable: false, read: false }, false)
        root.privateMessageAccepted(requested, value.to)
        root.lastError = ""
      } catch (error) {
        // A malformed success is never converted into a broadcast retry.
        root.lastError = "Could not validate private-send acceptance"
      }
      root._privateSendOutput = ""
      root._privateSendError = ""
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
        root.clearPrivateMessages()
        root.knownPeers = []
        root.lastError = ""
        root.actionStatus = "Chat joined"
        actionClear.restart()
        root.startDaemon()
      }
    }
  }
}
