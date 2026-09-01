import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})
  property bool installed: false
  property string binaryPath: ""
  property bool running: false
  property bool endpointOnline: false
  property bool topicJoined: false
  property int neighbors: 0
  property string peer: ""
  property string role: ""
  property string topic: ""
  property string statusText: "Checking…"
  property string lastError: ""
  property string actionStatus: ""
  property var messages: []
  property bool starting: false
  property bool stopping: false
  property bool joining: false
  property bool sending: false

  property string _joinToken: ""
  property string _sendBody: ""
  property string _statusOutput: ""
  property string _statusError: ""
  property string _sendOutput: ""
  property string _sendError: ""
  property string _joinOutput: ""
  property string _joinError: ""
  property string _actionOutput: ""
  property string _actionError: ""

  readonly property int refreshIntervalSec: boundedInt("refreshIntervalSec", 5, 2, 60)
  readonly property int maxMessages: boundedInt("maxMessages", 100, 20, 500)
  readonly property bool busy: starting || stopping || joining || sending

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

  function shortPeer(value) {
    var text = String(value || "")
    return text.length > 12 ? text.substring(0, 8) + "…" + text.substring(text.length - 4) : text
  }

  function refresh() {
    if (statusProcess.running || !installed) return
    _statusOutput = ""
    _statusError = ""
    statusProcess.command = [binaryPath, "--json", "status"]
    statusProcess.running = true
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
      peer = String(value.peer || "")
      role = String(value.role || "")
      topic = String(value.topic || "")
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

  function handleEvent(line) {
    var text = String(line || "").trim()
    if (text === "") return
    try {
      var event = JSON.parse(text)
      var type = String(event.type || "")
      if (type === "message" || type === "queued") {
        appendMessage({
          type: type,
          from: String(event.from || ""),
          body: String(event.body || ""),
          timestampMs: Number(event.timestamp_ms || Date.now()),
          outgoing: type === "queued"
        })
      } else if (type === "peer_up" || type === "peer_down") {
        refreshSoon.restart()
      } else if (type === "lagged" || type === "error") {
        lastError = cleanError(event.message, type === "lagged" ? "Some messages were missed" : "Meshmsg event error")
      }
    } catch (error) {
      console.warn("meshmsg: ignored invalid event", text)
    }
  }

  function appendMessage(message) {
    var next = messages.slice(0)
    next.push(message)
    if (next.length > maxMessages) next = next.slice(next.length - maxMessages)
    messages = next
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

  function clearMessages() {
    messages = []
  }

  Component.onCompleted: {
    whichProcess.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/eldar.meshmsg/resolve-meshmsg.sh"]
    whichProcess.running = true
  }

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

  Process {
    id: whichProcess
    property string output: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: whichProcess.output = String(text || "").trim() }
    onExited: function(exitCode) {
      root.binaryPath = exitCode === 0 ? whichProcess.output : ""
      root.installed = root.binaryPath !== ""
      if (root.installed) root.refresh()
      else root.setUnavailable("Not installed")
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
    stdout: SplitParser { onRead: function(line) { root.handleEvent(line) } }
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
