import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "eldar.meshmsg"
  ipcTarget: "eldar.meshmsg"
  manageIpc: false

  property int unread: 0
  property bool showJoin: false
  property bool revealInvite: false
  property bool replaceExisting: false
  property bool settingsOpen: false
  property bool searchOpen: false
  property string searchQuery: ""
  property bool clipboardOpen: false
  property bool helpOpen: false
  property int helpTab: 0
  property string clipboardQuery: ""
  property var clipboardHistory: []
  property int clipboardIndex: 0
  property bool messageCursorActive: false
  property bool pointerCursorReady: false
  property string copiedStatusKey: ""
  property bool inviteQrOpen: false
  property bool inviteQrLoading: false
  property string inviteQrError: ""
  property var inviteQrRows: []
  property int inviteQrSize: 0
  property int spinnerIndex: 0
  property var attachmentDraft: null
  property bool attachmentPickerBusy: false
  property string pendingDownloadAttachmentId: ""
  property string attachmentPickerError: ""
  property string copiedAttachmentId: ""
  property string _attachmentPickerMode: ""
  property string _attachmentPickerOutput: ""
  property string _attachmentPickerError: ""
  property bool _attachmentPickerReturning: false
  property bool _attachmentPickerReturnSearchOpen: false
  property string _attachmentPickerReturnSearchQuery: ""
  property string _pathCopyText: ""
  readonly property var spinnerFrames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
  readonly property string spinnerFrame: spinnerFrames[spinnerIndex]
  readonly property var displayedMessages: filterMessages(mesh.messages, searchQuery).slice().reverse()
  readonly property var displayedClipboard: filterClipboard(clipboardHistory, clipboardQuery)
  readonly property string clipboardHistoryPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  readonly property var helpTabs: [
    { label: "CHAT", bindings: [
      { key: "Esc", action: "Close Meshmsg or leave search" },
      { key: "Ctrl+O", action: "Choose a file to share" },
      { key: "Ctrl+Shift+O", action: "Choose a folder snapshot to share" },
      { key: "Ctrl+Shift+V", action: "Open the clipboard surface" },
      { key: "Ctrl+S", action: "Open the status surface" },
      { key: "Ctrl+F", action: "Search messages" },
      { key: "Ctrl+C", action: "Clear the chat timeline" },
      { key: "↑ / ↓", action: "Move through messages" },
      { key: "Enter", action: "Send or share the focused item" }
    ] },
    { label: "STATUS", bindings: [
      { key: "Esc", action: "Return to chat" },
      { key: "Ctrl+S", action: "Return to chat" },
      { key: "Ctrl+Shift+V", action: "Open the clipboard surface" },
      { key: "C", action: "Copy the invite" },
      { key: "Q", action: "Show the invite QR code" }
    ] },
    { label: "CLIPBOARD", bindings: [
      { key: "Esc", action: "Return to chat" },
      { key: "Ctrl+Shift+V", action: "Return to chat" },
      { key: "Ctrl+S", action: "Open the status surface" },
      { key: "↑ / ↓", action: "Move through clipboard entries" },
      { key: "Enter", action: "Broadcast the selected entry" }
    ] },
    { label: "PICKER", bindings: [
      { key: "Type", action: "Fuzzy-filter the current folder" },
      { key: "Enter", action: "Open a folder or choose a file" },
      { key: "Alt+Enter", action: "Choose a folder" },
      { key: "Ctrl+F", action: "Toggle recursive search" },
      { key: "Esc", action: "Cancel selection" }
    ] }
  ]
  readonly property var activeHelpBindings: [
    { key: "Tab / Shift+Tab", action: "Cycle key-binding tabs" }
  ].concat(helpTabs[Math.max(0, Math.min(helpTab, helpTabs.length - 1))].bindings)

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.58)
  readonly property color subtle: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.07)
  readonly property color accent: Color.accent
  readonly property color urgent: Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string connectionLabel: !mesh.installed ? "MESHMSG NOT INSTALLED"
    : mesh.running && mesh.topicJoined ? "CONNECTED"
    : mesh.running ? "CONNECTING"
    : "DAEMON STOPPED"
  readonly property color connectionColor: mesh.running && mesh.topicJoined ? "#43a047"
    : mesh.running ? "#f9a825" : dim
  readonly property string dockSide: normalizedDockSide(setting("dockSide", "right"))
  readonly property int panelWidthSetting: normalizedPanelWidth(setting("panelWidthPercent", "50"))
  property real panelWidthPercent: panelWidthSetting
  readonly property var barWindow: button.QsWindow ? button.QsWindow.window : null
  readonly property point buttonBarPosition: {
    panelAnchorWatcher.transform
    if (!barWindow || !barWindow.contentItem) return Qt.point(0, 0)
    return button.mapToItem(barWindow.contentItem, 0, 0)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Behavior on panelWidthPercent {
    NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
  }

  function sendCurrent() {
    if (mesh.sendMessage(messageField.text)) {
      messageField.text = ""
      Qt.callLater(scrollToLatest)
    }
  }

  function submitJoin() {
    if (mesh.joinChat(inviteField.text, replaceExisting)) {
      inviteField.text = ""
      revealInvite = false
    }
  }

  function scrollToLatest() {
    if (messageList.count > 0) {
      messageList.currentIndex = 0
      messageList.positionViewAtBeginning()
    }
  }

  function filterMessages(values, query) {
    var needle = String(query || "").trim().toLowerCase()
    if (needle === "") return values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var message = values[i] || {}
      var haystack = String(message.body || "") + " " + String(message.from || "") + " " + String(message.name || "")
      if (haystack.toLowerCase().indexOf(needle) !== -1) result.push(message)
    }
    return result
  }

  function pathName(path) {
    var value = String(path || "").replace(/\/+$/, "")
    var separator = value.lastIndexOf("/")
    return separator >= 0 ? value.substring(separator + 1) : value
  }

  function attachmentName(item) {
    var name = String(item && item.name || "Attachment")
    return String(item && item.attachmentKind || "") === "directory_tar_v1" && /\.tar$/i.test(name)
      ? name.substring(0, name.length - 4) : name
  }

  function formatBytes(value) {
    var bytes = Number(value || 0)
    if (!isFinite(bytes) || bytes < 0) return "Unknown size"
    if (bytes < 1024) return bytes + " B"
    var units = ["KiB", "MiB", "GiB"]
    var amount = bytes
    var unit = "B"
    for (var i = 0; i < units.length && amount >= 1024; i++) {
      amount /= 1024
      unit = units[i]
    }
    var formatted = amount >= 10 ? amount.toFixed(1) : amount.toFixed(2)
    return formatted.replace(/(\.\d*?)0+$/, "$1").replace(/\.$/, "") + " " + unit
  }

  function toggleHelp() {
    if (helpOpen) {
      helpOpen = false
      return
    }
    helpTab = clipboardOpen ? 2 : settingsOpen ? 1 : 0
    helpOpen = true
  }

  function restoreChatFocus() {
    if (!root.opened || root.settingsOpen || root.clipboardOpen || root.helpOpen || !mesh.running) return
    Qt.callLater(function() {
      if (root.searchOpen) searchField.forceActiveFocus()
      else messageField.forceActiveFocus()
    })
  }

  function clearAttachmentDraft() {
    shareAttachmentFocusTimer.stop()
    attachmentDraft = null
    restoreChatFocus()
  }

  function stageAttachment(path, kind) {
    // Drop the composer's cursor before the attachment card changes the
    // layout. Qt can otherwise retain its old cursor scene-graph node.
    messageField.focus = false
    var value = String(path || "")
    var attachmentKind = String(kind || "")
    var name = pathName(value)
    if (value.charAt(0) !== "/" || /[\r\n\0]/.test(value) || name === ""
        || (attachmentKind !== "file" && attachmentKind !== "directory_tar_v1")) {
      attachmentPickerError = "Could not use the selected local path"
      restoreChatFocus()
      return
    }
    attachmentPickerError = ""
    attachmentDraft = { path: value, name: name, attachmentKind: attachmentKind }
    // Let the attachment card finish entering the layout before focusing its
    // primary action, so Return can share immediately.
    shareAttachmentFocusTimer.restart()
  }

  function shareDraft() {
    var draft = attachmentDraft
    if (!draft) return
    if (mesh.shareAttachment(draft.path, draft.name, draft.attachmentKind)) clearAttachmentDraft()
  }

  function downloadAttachment(timelineId) {
    mesh.prepareDownload(timelineId, "")
  }

  function chooseDownloadFolder(timelineId) {
    var id = String(timelineId || "")
    if (id !== "") startAttachmentPicker("save-folder", id)
  }

  function startAttachmentPicker(mode, timelineId) {
    var value = String(mode || "")
    if (attachmentPickerBusy || mesh.attachmentBusy) return false
    if (value !== "share-file" && value !== "share-folder" && value !== "save-folder") return false
    var pendingId = String(timelineId || "")
    if (value === "save-folder" && pendingId === "") return false
    attachmentPickerError = ""
    _attachmentPickerMode = value
    _attachmentPickerOutput = ""
    _attachmentPickerError = ""
    _attachmentPickerReturnSearchOpen = searchOpen
    _attachmentPickerReturnSearchQuery = searchQuery
    pendingDownloadAttachmentId = pendingId
    attachmentPickerBusy = true
    root.close()
    attachmentPickerProcess.command = [
      "timeout", "--signal=TERM", "--kill-after=5s", "310s",
      Quickshell.env("HOME") + "/.config/omarchy/plugins/eldar.meshmsg/attachment-picker.py",
      value
    ]
    attachmentPickerProcess.running = true
    return true
  }

  function finishAttachmentPicker(exitCode) {
    var mode = _attachmentPickerMode
    var pendingId = pendingDownloadAttachmentId
    var output = stripFinalLineEnding(_attachmentPickerOutput)
    var error = String(_attachmentPickerError || "").replace(/\s+/g, " ").trim()
    _attachmentPickerMode = ""
    _attachmentPickerOutput = ""
    _attachmentPickerError = ""
    pendingDownloadAttachmentId = ""
    attachmentPickerBusy = false
    _attachmentPickerReturning = true
    root.open()
    Qt.callLater(function() {
      if (exitCode === 0) {
        if (output.charAt(0) !== "/" || /[\r\n\0]/.test(output)) {
          root.attachmentPickerError = "The attachment picker returned an invalid local path"
          root.restoreChatFocus()
        } else if (mode === "share-file") {
          root.stageAttachment(output, "file")
        } else if (mode === "share-folder") {
          root.stageAttachment(output, "directory_tar_v1")
        } else if (mode === "save-folder") {
          if (!mesh.prepareDownload(pendingId, output)) {
            root.attachmentPickerError = "The attachment is no longer available to download"
          }
          root.restoreChatFocus()
        }
      } else {
        if (exitCode !== 2) root.attachmentPickerError = error !== "" ? error : "Could not open the attachment picker"
        root.restoreChatFocus()
      }
    })
  }

  function stripFinalLineEnding(text) {
    var value = String(text || "")
    if (value.endsWith("\n")) {
      value = value.substring(0, value.length - 1)
      if (value.endsWith("\r")) value = value.substring(0, value.length - 1)
    }
    return value
  }

  function chatContentVisible() {
    return root.opened && !root.settingsOpen && !root.clipboardOpen && !root.helpOpen && !root.searchOpen
      && !attachmentPickerBusy
  }

  function markChatRead() {
    if (chatContentVisible()) unread = 0
  }

  function openPath(path) {
    var value = String(path || "")
    if (value !== "") Quickshell.execDetached(["uwsm-app", "--", "xdg-open", value])
  }

  function showInFiles(path, directory) {
    var value = String(path || "")
    if (value === "") return
    if (directory) {
      openPath(value)
      return
    }
    Quickshell.execDetached(["uwsm-app", "--", "nautilus", "--select", Util.fileUrl(value)])
  }

  function copyAttachmentPath(item) {
    var value = String(item && item.outputPath || "")
    if (value === "" || pathCopyProcess.running) return
    _pathCopyText = value
    copiedAttachmentId = String(item.id || "")
    pathCopyProcess.stdinEnabled = true
    pathCopyProcess.command = ["wl-copy"]
    pathCopyProcess.running = true
  }

  function moveMessageCursor(delta) {
    if (messageList.count === 0) return
    messageCursorActive = true
    var next = messageList.currentIndex
    if (next < 0) next = delta > 0 ? 0 : messageList.count - 1
    else next = Math.max(0, Math.min(messageList.count - 1, next + delta))
    messageList.currentIndex = next
    messageList.positionViewAtIndex(next, ListView.Contain)
  }

  function openSearch() {
    searchOpen = true
    messageCursorActive = false
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function closeSearch() {
    searchOpen = false
    searchQuery = ""
    markChatRead()
    if (mesh.running) Qt.callLater(function() { messageField.forceActiveFocus() })
  }

  function parseClipboardHistory(raw) {
    var rows = []
    try {
      var values = JSON.parse(String(raw || "[]"))
      if (!Array.isArray(values)) values = []
      for (var i = 0; i < values.length && rows.length < 100; i++) {
        var entry = values[i] || {}
        if (String(entry.type || "") !== "text") continue
        var text = String(entry.text || "")
        if (text.trim() === "") continue
        rows.push({
          fullText: text,
          previewText: text.replace(/\s+/g, " ").trim()
        })
      }
    } catch (error) {
      rows = []
    }
    clipboardHistory = rows
    if (clipboardIndex >= displayedClipboard.length)
      clipboardIndex = Math.max(0, displayedClipboard.length - 1)
  }

  function filterClipboard(values, query) {
    var needle = String(query || "").trim().toLowerCase()
    if (needle === "") return values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var entry = values[i] || {}
      if (String(entry.fullText || "").toLowerCase().indexOf(needle) !== -1) result.push(entry)
    }
    return result
  }

  function moveClipboardCursor(delta) {
    if (clipboardList.count === 0) return
    clipboardIndex = Math.max(0, Math.min(clipboardList.count - 1, clipboardIndex + delta))
    clipboardList.positionViewAtIndex(clipboardIndex, ListView.Contain)
  }

  function broadcastClipboardSelection() {
    if (!mesh.running || clipboardIndex < 0 || clipboardIndex >= displayedClipboard.length) return
    var entry = displayedClipboard[clipboardIndex]
    if (entry && mesh.sendMessage(entry.fullText)) setClipboardSurface(false)
  }

  function setClipboardSurface(open) {
    helpOpen = false
    clipboardOpen = open
    if (open) {
      if (inviteQrOpen) closeInviteQr()
      settingsOpen = false
      searchOpen = false
      searchQuery = ""
      clipboardQuery = ""
      clipboardIndex = 0
      chatFocusTimer.stop()
      messageField.focus = false
      inviteField.focus = false
      Qt.callLater(function() { clipboardSearchField.forceActiveFocus() })
    } else {
      clipboardSearchField.focus = false
      root.markChatRead()
      if (mesh.running) chatFocusTimer.restart()
    }
  }

  function copyStatusValue(value, key) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
    copiedStatusKey = key
    copiedStatusClear.restart()
  }

  function openStateDir() {
    var path = String(mesh.stateDir || "")
    if (path === "") return
    Quickshell.execDetached(["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + path])
  }

  function parseInviteQr(raw) {
    var lines = String(raw || "").trim().split(/\r?\n/).filter(function(line) { return line !== "" })
    if (lines.length === 0) {
      inviteQrError = "Could not generate invite QR code"
      return
    }
    var size = lines[0].length
    if (size !== lines.length) {
      inviteQrError = "Invalid invite QR matrix"
      return
    }
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].length !== size || !/^[01]+$/.test(lines[i])) {
        inviteQrError = "Invalid invite QR matrix"
        return
      }
    }
    inviteQrRows = lines
    inviteQrSize = size
    inviteQrError = ""
  }

  function showInviteQr() {
    if (!mesh.hasInvite || inviteQrProcess.running) return
    inviteQrSize = 0
    inviteQrRows = []
    inviteQrError = ""
    inviteQrLoading = true
    inviteQrOpen = true
    inviteQrProcess.command = [Quickshell.env("HOME") + "/.config/omarchy/plugins/eldar.meshmsg/invite-qr.sh", mesh.binaryPath]
    inviteQrProcess.running = true
    Qt.callLater(function() { inviteQrSurface.forceActiveFocus() })
  }

  function closeInviteQr() {
    inviteQrOpen = false
    inviteQrLoading = false
    inviteQrSize = 0
    inviteQrRows = []
    inviteQrError = ""
    if (inviteQrProcess.running) inviteQrProcess.running = false
    Qt.callLater(function() { statusSurface.forceActiveFocus() })
  }

  function normalizedDockSide(value) {
    var side = String(value || "").toLowerCase()
    return ["left", "center", "right"].indexOf(side) !== -1 ? side : "right"
  }

  function normalizedPanelWidth(value) {
    var width = parseInt(value, 10)
    return [25, 40, 50].indexOf(width) !== -1 ? width : 50
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function moveDockSide(side) {
    var value = normalizedDockSide(side)
    if (value !== dockSide) persistSettings({ dockSide: value })
  }

  function setPanelWidth(value) {
    var width = normalizedPanelWidth(value)
    if (width !== panelWidthSetting) persistSettings({ panelWidthPercent: String(width) })
  }

  function setSettingsSurface(open) {
    helpOpen = false
    settingsOpen = open
    if (open) {
      clipboardOpen = false
      searchOpen = false
      searchQuery = ""
      chatFocusTimer.stop()
      messageField.focus = false
      inviteField.focus = false
      mesh.refresh()
      Qt.callLater(function() { statusSurface.forceActiveFocus() })
    } else {
      if (inviteQrOpen) closeInviteQr()
      statusSurface.focus = false
      root.markChatRead()
      if (mesh.running) chatFocusTimer.restart()
    }
  }

  onOpenedChanged: {
    if (!opened) {
      helpOpen = false
      pointerCursorReady = false
      pointerCursorResetTimer.stop()
      chatFocusTimer.stop()
      messageField.focus = false
      inviteField.focus = false
      return
    }
    var pickerReturn = _attachmentPickerReturning
    if (pickerReturn) {
      _attachmentPickerReturning = false
      settingsOpen = false
      clipboardOpen = false
      searchOpen = _attachmentPickerReturnSearchOpen
      searchQuery = _attachmentPickerReturnSearchQuery
    } else {
      settingsOpen = false
      clipboardOpen = false
      searchOpen = false
      searchQuery = ""
    }
    if (!searchOpen) unread = 0
    pointerCursorReady = false
    pointerCursorResetTimer.restart()
    mesh.refresh()
    Qt.callLater(root.scrollToLatest)
    // Wait for the panel's opening/layout transition before showing a text
    // cursor; focusing during that transition can leave a stale cursor quad.
    if (!pickerReturn && mesh.running) chatFocusTimer.restart()
  }

  Service {
    id: mesh
    settings: root.settings
  }

  Process {
    id: attachmentPickerProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._attachmentPickerOutput = text
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._attachmentPickerError = text
    }
    onExited: function(exitCode) { root.finishAttachmentPicker(exitCode) }
  }

  Process {
    id: pathCopyProcess
    stdinEnabled: true
    onStarted: {
      write(root._pathCopyText)
      root._pathCopyText = ""
      stdinEnabled = false
    }
    onExited: function(exitCode) {
      stdinEnabled = true
      root._pathCopyText = ""
      if (exitCode !== 0) root.copiedAttachmentId = ""
      else copiedAttachmentClear.restart()
    }
  }

  Process {
    id: inviteQrProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseInviteQr(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var message = String(text || "").replace(/^error:\s*/i, "").trim()
        if (message !== "") root.inviteQrError = message
      }
    }
    onExited: function(exitCode) {
      root.inviteQrLoading = false
      if (exitCode !== 0 && root.inviteQrError === "") root.inviteQrError = "Could not generate invite QR code"
    }
  }

  FileView {
    id: clipboardHistoryFile
    path: root.clipboardHistoryPath
    watchChanges: true
    printErrors: false
    onLoaded: root.parseClipboardHistory(text())
    onLoadFailed: root.parseClipboardHistory("[]")
    onFileChanged: reload()
  }

  Connections {
    target: mesh
    function onTimelineItemAdded() {
      if (root.opened) Qt.callLater(root.scrollToLatest)
    }
    function onIncomingActivity() {
      if (!root.chatContentVisible()) root.unread += 1
    }
    function onRunningChanged() {
      if (mesh.running) root.showJoin = false
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { if (!root.attachmentPickerBusy) root.open() }
    function close(): void { root.close() }
    function show(): void { if (!root.attachmentPickerBusy) root.open() }
    function hide(): void { root.close() }
    function toggle(): void { if (!root.attachmentPickerBusy) root.toggle() }
    function refresh(): string { mesh.refresh(); return "ok" }
    function start(): string { mesh.startDaemon(); return "ok" }
    function stop(): string { mesh.stopDaemon(); return "ok" }
    function settings(): string {
      if (root.attachmentPickerBusy) return "busy"
      root.open(); root.setSettingsSurface(true); return "ok"
    }
    function clipboard(): string {
      if (root.attachmentPickerBusy) return "busy"
      root.open(); root.setClipboardSurface(true); return "ok"
    }
    function copyInvite(): string { return mesh.copyInvite() ? "ok" : "unavailable" }
    function inviteQr(): string {
      if (root.attachmentPickerBusy) return "busy"
      root.open(); root.setSettingsSurface(true); root.showInviteQr(); return "ok"
    }
    function status(): string {
      return JSON.stringify({ running: mesh.running, connected: mesh.topicJoined, neighbors: mesh.neighbors, peer: mesh.peer })
    }
  }

  Shortcut {
    sequence: "Escape"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: {
      if (root.helpOpen) root.helpOpen = false
      else if (root.inviteQrOpen) root.closeInviteQr()
      else if (root.clipboardOpen) root.setClipboardSurface(false)
      else if (root.searchOpen) root.closeSearch()
      else if (root.settingsOpen) root.setSettingsSurface(false)
      else root.close()
    }
  }

  Shortcut {
    sequence: "Up"
    context: Qt.ApplicationShortcut
    enabled: root.opened && !root.settingsOpen && !root.clipboardOpen && messageList.count > 0
    onActivated: root.moveMessageCursor(-1)
  }

  Shortcut {
    sequence: "Down"
    context: Qt.ApplicationShortcut
    enabled: root.opened && !root.settingsOpen && !root.clipboardOpen && messageList.count > 0
    onActivated: root.moveMessageCursor(1)
  }

  Shortcut {
    sequence: "Ctrl+K"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: root.toggleHelp()
  }

  Shortcut {
    sequence: "Tab"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.helpOpen
    onActivated: root.helpTab = (root.helpTab + 1) % root.helpTabs.length
  }

  Shortcut {
    sequence: "Shift+Tab"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.helpOpen
    onActivated: root.helpTab = (root.helpTab + root.helpTabs.length - 1) % root.helpTabs.length
  }

  Shortcut {
    sequence: "Ctrl+F"
    context: Qt.ApplicationShortcut
    enabled: root.opened && !root.settingsOpen && !root.clipboardOpen && !root.searchOpen
    onActivated: root.openSearch()
  }

  Shortcut {
    sequence: "Up"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.clipboardOpen && clipboardList.count > 0
    onActivated: root.moveClipboardCursor(-1)
  }

  Shortcut {
    sequence: "Down"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.clipboardOpen && clipboardList.count > 0
    onActivated: root.moveClipboardCursor(1)
  }

  Shortcut {
    sequence: "Return"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.clipboardOpen && clipboardList.count > 0 && !mesh.sending
    onActivated: root.broadcastClipboardSelection()
  }

  Shortcut {
    sequence: "Return"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.attachmentDraft && shareAttachmentButton.activeFocus
      && shareAttachmentButton.enabled
    onActivated: root.shareDraft()
  }

  Shortcut {
    sequence: "Ctrl+C"
    context: Qt.ApplicationShortcut
    enabled: root.opened && !root.settingsOpen && !root.clipboardOpen && !root.helpOpen && !root.searchOpen
      && mesh.messages.length > 0 && !mesh.attachmentBusy && !root.attachmentPickerBusy
    onActivated: mesh.clearMessages()
  }

  Shortcut {
    sequence: "Ctrl+Shift+V"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: root.setClipboardSurface(!root.clipboardOpen)
  }

  Shortcut {
    sequence: "Ctrl+O"
    context: Qt.ApplicationShortcut
    enabled: root.opened && !root.settingsOpen && !root.clipboardOpen && mesh.running
      && !mesh.attachmentBusy && !root.attachmentPickerBusy
    onActivated: root.startAttachmentPicker("share-file", "")
  }

  Shortcut {
    sequence: "Ctrl+Shift+O"
    context: Qt.ApplicationShortcut
    enabled: root.opened && !root.settingsOpen && !root.clipboardOpen && mesh.running
      && !mesh.attachmentBusy && !root.attachmentPickerBusy
    onActivated: root.startAttachmentPicker("share-folder", "")
  }

  Shortcut {
    sequence: "Ctrl+S"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: root.setSettingsSurface(!root.settingsOpen)
  }

  Timer {
    id: pointerCursorResetTimer
    interval: 300
    repeat: false
    onTriggered: root.pointerCursorReady = root.opened
  }

  Timer {
    id: chatFocusTimer
    interval: 240
    repeat: false
    onTriggered: if (root.opened && !root.settingsOpen && !root.clipboardOpen && !root.helpOpen && mesh.running) messageField.forceActiveFocus()
  }

  Timer {
    id: shareAttachmentFocusTimer
    interval: 120
    repeat: false
    onTriggered: if (root.opened && root.attachmentDraft && shareAttachmentButton.enabled)
      shareAttachmentButton.forceActiveFocus(Qt.TabFocusReason)
  }

  Timer {
    id: copiedStatusClear
    interval: 1200
    repeat: false
    onTriggered: root.copiedStatusKey = ""
  }

  Timer {
    id: copiedAttachmentClear
    interval: 1200
    repeat: false
    onTriggered: root.copiedAttachmentId = ""
  }

  Timer {
    interval: 80
    repeat: true
    running: mesh.starting
    onTriggered: root.spinnerIndex = (root.spinnerIndex + 1) % root.spinnerFrames.length
    onRunningChanged: if (!running) root.spinnerIndex = 0
  }

  Shortcut {
    sequence: "C"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.settingsOpen && !root.inviteQrOpen && mesh.hasInvite && !mesh.copyingInvite
    onActivated: mesh.copyInvite()
  }

  Shortcut {
    sequence: "Q"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.settingsOpen && !root.inviteQrOpen && mesh.hasInvite && !root.inviteQrLoading
    onActivated: root.showInviteQr()
  }

  TransformWatcher {
    id: panelAnchorWatcher
    a: root.barWindow ? root.barWindow.contentItem : null
    b: button
  }

  // A virtual anchor can move freely along the bar without moving or
  // recreating the widget itself. KeyboardPanel follows it, so the open card
  // glides between screen positions instead of disappearing during a bar
  // layout reload.
  Item {
    id: panelAnchor
    parent: button
    width: 0
    height: 0
    x: {
      if (panel.barPos === "left" || panel.barPos === "right") return 0
      var center = root.dockSide === "left" ? panel.margin + panel.contentWidth / 2
        : root.dockSide === "center" ? panel.screenW / 2
        : panel.screenW - panel.margin - panel.contentWidth / 2
      return center - root.buttonBarPosition.x
    }
    y: {
      if (panel.barPos === "top" || panel.barPos === "bottom") return 0
      var center = root.dockSide === "left" ? panel.margin + panel.contentHeight / 2
        : root.dockSide === "center" ? panel.screenH / 2
        : panel.screenH - panel.margin - panel.contentHeight / 2
      return center - root.buttonBarPosition.y
    }

    Behavior on x {
      enabled: root.opened
      NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
    }
    Behavior on y {
      enabled: root.opened
      NumberAnimation { duration: 260; easing.type: Easing.InOutCubic }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.unread > 0 ? "󰍦 " + Math.min(root.unread, 99) : "󰍦"
    foreground: root.unread > 0 ? root.accent : root.connectionColor
    fontFamily: root.fontFamily
    fontSize: Style.font.icon
    horizontalMargin: 8
    tooltipText: root.unread > 0 ? root.unread + " unread meshmsg item" + (root.unread === 1 ? "" : "s")
      : "Meshmsg · " + root.connectionLabel.toLowerCase()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) mesh.refresh()
      else if (!root.attachmentPickerBusy) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: panelAnchor
    owner: root
    bar: root.bar
    open: root.opened
    centerOnBar: false
    // Focus is assigned by chatFocusTimer after the opening animation. Letting
    // KeyboardPanel focus the field immediately can create a stale blinking
    // cursor at the field's pre-layout position.
    focusTarget: null
    contentWidth: panel.fittedContentWidth(panel.screenW * root.panelWidthPercent / 100)
    contentHeight: Math.max(1, Math.round(panel.availableCardHeight))

    ColumnLayout {
      id: content
      x: Style.space(14)
      y: Style.space(14)
      width: parent.width - Style.space(28)
      height: parent.height - Style.space(28)

      // Toggle this handler after the panel opens so Qt reapplies the arrow
      // even when the pointer has not moved since shell startup.
      HoverHandler {
        enabled: root.pointerCursorReady
        cursorShape: Qt.ArrowCursor
      }
      spacing: Style.space(12)
      visible: (!root.settingsOpen && !root.clipboardOpen) || chatRotation.angle > -89.9
      opacity: 1.0 - Math.abs(chatRotation.angle) / 90.0

      transform: Rotation {
        id: chatRotation
        origin.x: content.width / 2
        origin.y: content.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: root.settingsOpen || root.clipboardOpen ? -90 : 0
        Behavior on angle {
          NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.space(10)

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(2)
          Text {
            Layout.fillWidth: true
            text: "MESHMSG"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
          RowLayout {
            spacing: Style.space(6)
            Rectangle {
              implicitWidth: Style.space(8)
              implicitHeight: implicitWidth
              radius: implicitWidth / 2
              color: root.connectionColor
            }
            Text {
              text: root.connectionLabel + (mesh.running ? " · " + mesh.neighbors + " PEER" + (mesh.neighbors === 1 ? "" : "S") : "")
              color: root.connectionColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }
          }
        }

        PanelActionButton {
          visible: mesh.installed && mesh.running
          iconText: "󰅌"
          tooltipText: "Broadcast clipboard"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.setClipboardSurface(true)
        }

        PanelActionButton {
          visible: mesh.installed && mesh.running
          iconText: "󰒓"
          tooltipText: "Meshmsg status"
          foreground: root.foreground
          fontFamily: root.fontFamily
          onClicked: root.setSettingsSurface(true)
        }

        Button {
          visible: mesh.installed
          text: mesh.starting ? root.spinnerFrame + " Starting" : (mesh.running ? "Stop" : "Start")
          enabled: mesh.running ? !mesh.stopping : !mesh.busy
          onClicked: mesh.running ? mesh.stopDaemon() : mesh.startDaemon()
        }
      }

      Text {
        visible: mesh.actionStatus !== "" || mesh.lastError !== "" || root.attachmentPickerError !== ""
        Layout.fillWidth: true
        text: root.attachmentPickerError !== "" ? root.attachmentPickerError
          : (mesh.lastError !== "" ? mesh.lastError : mesh.actionStatus)
        color: root.attachmentPickerError !== "" || mesh.lastError !== "" ? root.urgent : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        wrapMode: Text.WordWrap
      }

      Rectangle {
        visible: !mesh.installed
        Layout.fillWidth: true
        implicitHeight: missingText.implicitHeight + Style.space(24)
        radius: Style.cornerRadius
        color: root.subtle
        Text {
          id: missingText
          anchors.fill: parent
          anchors.margins: Style.space(12)
          text: "Install meshmsg and make sure it is available on PATH."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }
      }

      PanelSeparator {
        visible: mesh.installed && mesh.running
        Layout.fillWidth: true
        foreground: root.foreground
      }

      Item {
        visible: mesh.installed && mesh.running
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: root.attachmentDraft ? Style.space(292) : Style.space(360)
        clip: true

        Rectangle {
          id: searchBar
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: Style.space(44)
          z: 3
          visible: root.searchOpen
          radius: 0
          color: root.subtle
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(9)

            Text {
              text: "󰍉"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }

            TextField {
              id: searchField
              Layout.fillWidth: true
              placeholderText: "Search messages or peer ID"
              text: root.searchQuery
              font.family: root.fontFamily
              cursorVisible: activeFocus && root.opened && root.searchOpen
              cursorDelegate: Rectangle {
                width: 2
                color: root.foreground
                visible: searchField.cursorVisible
              }
              background: Item {}
              onTextChanged: {
                root.searchQuery = text
                root.messageCursorActive = false
                messageList.currentIndex = messageList.count > 0 ? 0 : -1
                if (messageList.count > 0) messageList.positionViewAtIndex(0, ListView.Beginning)
              }
            }

            Text {
              text: messageList.count + " result" + (messageList.count === 1 ? "" : "s")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            PanelActionButton {
              iconText: "󰅖"
              tooltipText: "Close search"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.closeSearch()
            }
          }
        }

        Column {
          anchors.centerIn: parent
          visible: root.displayedMessages.length === 0
          spacing: Style.space(8)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "󰍦"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            opacity: 0.65
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.searchQuery !== "" ? "No matching messages"
              : mesh.topicJoined ? "No messages yet" : "Waiting for a mesh peer…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        ListView {
          id: messageList
          anchors.fill: parent
          anchors.leftMargin: 0
          anchors.rightMargin: 0
          anchors.bottomMargin: Style.space(8)
          anchors.topMargin: root.searchOpen ? Style.space(54) : Style.space(8)
          spacing: Style.space(8)
          clip: true
          model: root.displayedMessages
          boundsBehavior: Flickable.StopAtBounds
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          delegate: Item {
            id: messageDelegate
            required property var modelData
            required property int index
            property bool copied: false
            readonly property bool isAttachment: String(modelData.itemKind || "text") === "attachment"
            readonly property bool isDirectoryAttachment: String(modelData.attachmentKind || "") === "directory_tar_v1"
            readonly property string attachmentState: String(modelData.state || "")
            readonly property string attachmentStatus: {
              if (attachmentState === "sharing") return isDirectoryAttachment ? "Preparing and sharing folder snapshot…" : "Sharing file…"
              if (attachmentState === "shared") return modelData.deliveryAcknowledged ? "Offer shared · delivery acknowledged" : "Offer shared · delivery not acknowledged"
              if (attachmentState === "preparing_download") return "Preparing download…"
              if (attachmentState === "queued") return "Preparing download…"
              if (attachmentState === "downloading") return "Downloading…"
              if (attachmentState === "complete") return "Saved as " + root.pathName(modelData.outputPath)
              if (attachmentState === "failed") return String(modelData.error || "Attachment operation failed")
              return "Not downloaded · plaintext attachment"
            }
            width: messageList.width
            height: bubble.implicitHeight

            function copyMessage() {
              Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(String(modelData.body || "")) + " | wl-copy"])
              copied = true
              copiedTimer.restart()
            }

            Timer {
              id: copiedTimer
              interval: 1200
              repeat: false
              onTriggered: messageDelegate.copied = false
            }

            Rectangle {
              id: bubble
              anchors.left: parent.left
              anchors.right: parent.right
              implicitHeight: bubbleContent.implicitHeight + Style.space(16)
              radius: 0
              color: root.messageCursorActive && messageList.currentIndex === index
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                : modelData.outgoing
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.09)
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.055)

              Rectangle {
                visible: root.messageCursorActive && messageList.currentIndex === index
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: Style.space(3)
                color: root.accent
              }

              HoverHandler {
                id: bubbleHover
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: {
                  root.messageCursorActive = true
                  messageList.currentIndex = index
                }
              }

              Column {
                id: bubbleContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Style.space(8)
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(10)
                spacing: Style.space(2)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(7)

                  Text {
                    visible: modelData.outgoing
                    text: Qt.formatTime(new Date(modelData.timestampMs), "HH:mm")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Rectangle {
                    visible: !modelData.outgoing
                    implicitWidth: Style.space(7)
                    implicitHeight: implicitWidth
                    radius: implicitWidth / 2
                    color: root.dim
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Text {
                    Layout.fillWidth: true
                    text: modelData.outgoing ? "YOU" : mesh.shortPeer(modelData.from)
                    color: modelData.outgoing ? root.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    elide: Text.ElideMiddle
                    horizontalAlignment: modelData.outgoing ? Text.AlignRight : Text.AlignLeft
                  }

                  Rectangle {
                    visible: modelData.outgoing
                    implicitWidth: Style.space(7)
                    implicitHeight: implicitWidth
                    radius: implicitWidth / 2
                    color: root.accent
                    Layout.alignment: Qt.AlignVCenter
                  }

                  Text {
                    visible: !modelData.outgoing
                    text: Qt.formatTime(new Date(modelData.timestampMs), "HH:mm")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  id: messageBody
                  visible: !messageDelegate.isAttachment
                  width: parent.width
                  rightPadding: Style.space(30)
                  topPadding: Style.space(3)
                  bottomPadding: Style.space(2)
                  text: String(modelData.body || "")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WrapAnywhere
                  renderType: Text.NativeRendering
                }

                ColumnLayout {
                  visible: messageDelegate.isAttachment
                  width: parent.width
                  spacing: Style.space(6)

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(9)

                    Text {
                      text: messageDelegate.isDirectoryAttachment ? "󰉋" : "󰈔"
                      color: modelData.outgoing ? root.accent : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.display
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 0
                      Text {
                        Layout.fillWidth: true
                        text: root.attachmentName(modelData)
                        color: root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideMiddle
                      }
                      Text {
                        Layout.fillWidth: true
                        text: (messageDelegate.isDirectoryAttachment ? "Folder snapshot" : "File")
                          + (messageDelegate.attachmentState === "sharing" ? "" : " · " + root.formatBytes(modelData.size))
                        color: root.dim
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  ProgressBar {
                    Layout.fillWidth: true
                    visible: messageDelegate.attachmentState === "preparing_download"
                      || messageDelegate.attachmentState === "queued"
                      || messageDelegate.attachmentState === "downloading"
                    from: 0
                    to: Math.max(1, Number(modelData.totalBytes || modelData.size || 1))
                    value: Number(modelData.receivedBytes || 0)
                    indeterminate: Number(modelData.receivedBytes || 0) <= 0
                  }

                  Text {
                    Layout.fillWidth: true
                    text: messageDelegate.attachmentState === "downloading" && Number(modelData.receivedBytes || 0) > 0
                      ? root.formatBytes(modelData.receivedBytes) + " / " + root.formatBytes(modelData.totalBytes || modelData.size)
                      : messageDelegate.attachmentStatus
                    color: messageDelegate.attachmentState === "failed" ? root.urgent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    visible: messageDelegate.attachmentState === "offered" || messageDelegate.attachmentState === "failed"

                    Item { Layout.fillWidth: true }
                    Button {
                      visible: !modelData.outgoing
                      text: "Save elsewhere…"
                      enabled: !mesh.attachmentBusy && !root.attachmentPickerBusy
                      onClicked: root.chooseDownloadFolder(modelData.id)
                    }
                    Button {
                      text: messageDelegate.attachmentState === "failed" ? "Retry" : (messageDelegate.isDirectoryAttachment ? "Download folder" : "Download")
                      enabled: !mesh.attachmentBusy && !root.attachmentPickerBusy
                      onClicked: {
                        if (messageDelegate.attachmentState === "failed") mesh.retryAttachment(modelData.id)
                        else root.downloadAttachment(modelData.id)
                      }
                    }
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(6)
                    visible: messageDelegate.attachmentState === "complete"

                    Item { Layout.fillWidth: true }
                    Button {
                      text: root.copiedAttachmentId === String(modelData.id || "") ? "Copied" : "Copy path"
                      onClicked: root.copyAttachmentPath(modelData)
                    }
                    Button {
                      text: messageDelegate.isDirectoryAttachment ? "Open folder" : "Show in Files"
                      onClicked: root.showInFiles(modelData.outputPath, messageDelegate.isDirectoryAttachment)
                    }
                    Button {
                      visible: !messageDelegate.isDirectoryAttachment
                      text: "Open"
                      onClicked: root.openPath(modelData.outputPath)
                    }
                  }
                }
              }

              Rectangle {
                id: copyButton
                visible: !messageDelegate.isAttachment
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(7)
                width: Style.space(22)
                height: width
                radius: Style.space(3)
                opacity: bubbleHover.hovered || copyMouse.containsMouse || messageDelegate.copied ? 1 : 0
                enabled: opacity > 0
                color: copyMouse.containsMouse
                  ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                  : "transparent"
                border.width: 1
                border.color: messageDelegate.copied
                  ? root.accent
                  : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)

                Behavior on opacity {
                  NumberAnimation { duration: 120 }
                }

                Text {
                  anchors.centerIn: parent
                  text: messageDelegate.copied ? "✓" : "󰆏"
                  color: messageDelegate.copied ? root.accent : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: copyMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: messageDelegate.copyMessage()
                }

                PanelToolTip {
                  visible: copyMouse.containsMouse
                  text: messageDelegate.copied ? "Copied" : "Copy message"
                  fontFamily: root.fontFamily
                }
              }
            }
          }
        }
      }

      PanelSeparator {
        visible: mesh.installed && mesh.running
        Layout.fillWidth: true
        foreground: root.foreground
      }

      Rectangle {
        visible: mesh.installed && mesh.running && root.attachmentDraft !== null
        Layout.fillWidth: true
        implicitHeight: attachmentDraftContent.implicitHeight + Style.space(16)
        color: root.subtle
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
        radius: Style.cornerRadius

        ColumnLayout {
          id: attachmentDraftContent
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(8)
          spacing: Style.space(5)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Text {
              text: root.attachmentDraft && root.attachmentDraft.attachmentKind === "directory_tar_v1" ? "󰉋" : "󰈔"
              color: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }
            Text {
              Layout.fillWidth: true
              text: root.attachmentDraft ? root.attachmentDraft.name : ""
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideMiddle
            }
            Button {
              text: "Remove"
              onClicked: root.clearAttachmentDraft()
            }
            Button {
              id: shareAttachmentButton
              text: root.attachmentDraft && root.attachmentDraft.attachmentKind === "directory_tar_v1" ? "Share snapshot" : "Share file"
              enabled: !mesh.attachmentBusy && !root.attachmentPickerBusy
              onClicked: root.shareDraft()
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Plaintext to everyone in this chat · shared offers cannot currently be revoked"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }

      RowLayout {
        visible: mesh.installed && mesh.running
        Layout.fillWidth: true
        spacing: Style.space(8)

        TextField {
          id: messageField
          Layout.fillWidth: true
          placeholderText: mesh.topicJoined ? "Message the chat" : "Message (daemon is still connecting)"
          enabled: !mesh.sending
          font.family: root.fontFamily
          cursorVisible: activeFocus && root.opened && !root.settingsOpen && !root.clipboardOpen
          cursorDelegate: Rectangle {
            width: 2
            color: root.foreground
            visible: messageField.cursorVisible
          }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_C
                && event.modifiers === Qt.ControlModifier
                && mesh.messages.length > 0
                && !mesh.attachmentBusy && !root.attachmentPickerBusy) {
              mesh.clearMessages()
              event.accepted = true
            }
          }
          onAccepted: root.sendCurrent()
        }
        Button {
          text: mesh.sending ? "Sending…" : "Send"
          enabled: !mesh.sending && messageField.text.trim() !== ""
          onClicked: root.sendCurrent()
        }
      }

      RowLayout {
        visible: mesh.installed && !mesh.running
        Layout.fillWidth: true
        spacing: Style.space(8)
        Text {
          Layout.fillWidth: true
          text: "Have an invite for another chat?"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
        Button {
          text: root.showJoin ? "Cancel" : "Join chat"
          enabled: !mesh.joining
          onClicked: root.showJoin = !root.showJoin
        }
      }

      ColumnLayout {
        visible: mesh.installed && !mesh.running && root.showJoin
        Layout.fillWidth: true
        spacing: Style.space(8)

        Text {
          Layout.fillWidth: true
          text: "Invites grant access to a trusted plaintext chat. Only paste one from someone you trust."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)
          TextField {
            id: inviteField
            Layout.fillWidth: true
            placeholderText: "Paste meshmsg invite"
            echoMode: root.revealInvite ? TextInput.Normal : TextInput.Password
            font.family: root.fontFamily
            cursorVisible: activeFocus && root.opened && root.showJoin
            cursorDelegate: Rectangle {
              width: 2
              color: root.foreground
              visible: inviteField.cursorVisible
            }
            onAccepted: root.submitJoin()
          }
          Button {
            text: root.revealInvite ? "Hide" : "Show"
            onClicked: root.revealInvite = !root.revealInvite
          }
        }

        CheckBox {
          text: "Replace this machine's existing meshmsg identity/chat"
          checked: root.replaceExisting
          onToggled: root.replaceExisting = checked
        }

        Button {
          Layout.alignment: Qt.AlignRight
          text: mesh.joining ? "Joining…" : "Join and start daemon"
          enabled: !mesh.joining && inviteField.text.trim() !== ""
          onClicked: root.submitJoin()
        }
      }

      RowLayout {
        Layout.fillWidth: true
        HelpLink { Layout.fillWidth: true }
        Text {
          visible: mesh.messages.length > 0 && !mesh.attachmentBusy
          text: "CLEAR"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: mesh.clearMessages()
          }
        }
      }
    }

    Rectangle {
      id: statusSurface
      anchors.fill: parent
      z: 20
      visible: root.settingsOpen || settingsRotation.angle < 89.9
      opacity: 1.0 - settingsRotation.angle / 90.0
      color: Color.background
      radius: Style.cornerRadius

      HoverHandler {
        enabled: root.pointerCursorReady
        cursorShape: Qt.ArrowCursor
      }

      transform: Rotation {
        id: settingsRotation
        origin.x: statusSurface.width / 2
        origin.y: statusSurface.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: root.settingsOpen ? 0 : 90
        Behavior on angle {
          NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          PanelActionButton {
            iconText: "󰁍"
            tooltipText: "Back to chat"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.setSettingsSurface(false)
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(1)
            Text {
              Layout.fillWidth: true
              text: "MESHMSG STATUS"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
          }

          PanelActionButton {
            iconText: "󰑓"
            tooltipText: "Refresh status"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: mesh.installed
            onClicked: mesh.refreshAll()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "PANEL POSITION"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
              options: [
                { value: "left", label: "Left" },
                { value: "center", label: "Center" },
                { value: "right", label: "Right" }
              ]
              value: root.dockSide
              foreground: root.foreground
              background: Color.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onChanged: function(value) { root.moveDockSide(value) }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(12)

            Text {
              text: "PANEL WIDTH"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
            }

            Item { Layout.fillWidth: true }

            ButtonGroup {
              options: [
                { value: "25", label: "25%" },
                { value: "40", label: "40%" },
                { value: "50", label: "50%" }
              ]
              value: String(root.panelWidthSetting)
              foreground: root.foreground
              background: Color.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              onChanged: function(value) { root.setPanelWidth(value) }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: Style.cornerRadius
          color: root.subtle

          Flickable {
            anchors.fill: parent
            anchors.margins: Style.space(14)
            contentWidth: width
            contentHeight: statusRows.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            ColumnLayout {
              id: statusRows
              width: parent.width
              spacing: Style.space(9)

              StatusRow { label: "VERSION"; value: mesh.version || "—" }
              StatusRow { label: "DAEMON"; value: mesh.running ? "Running" : "Stopped"; valueColor: mesh.running ? root.connectionColor : root.dim }
              StatusRow { label: "ENDPOINT"; value: mesh.endpointOnline ? "Online" : "Offline"; valueColor: mesh.endpointOnline ? root.connectionColor : root.dim }
              StatusRow { label: "TOPIC"; value: mesh.topicJoined ? "Joined" : "Not joined"; valueColor: mesh.topicJoined ? root.connectionColor : root.dim }
              StatusRow { label: "DIRECT NEIGHBORS"; value: String(mesh.neighbors) }

              PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

              StatusRow { label: "ADVERTISES SELF"; value: mesh.advertisesSelf ? "Yes" : "No" }
              StatusRow { label: "SELF ADVERTISED"; value: mesh.selfAdvertised ? "Yes" : "No" }
              StatusRow { label: "HAS INVITE"; value: mesh.hasInvite ? "Yes" : "No" }
              StatusRow { label: "BOOTSTRAP PEERS"; value: String(mesh.bootstrapPeerCount) }

              PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

              StatusRow { label: "PEER ID"; value: mesh.peer || "—"; wrapValue: true; copyable: mesh.peer !== ""; copyKey: "peer" }
              StatusRow { label: "TOPIC ID"; value: mesh.topic || "—"; wrapValue: true; copyable: mesh.topic !== ""; copyKey: "topic" }
              StatusRow { label: "STATE DIR"; value: mesh.stateDir || "—"; wrapValue: true; openable: mesh.stateDir !== "" }
              StatusRow {
                label: "UPDATED"
                value: mesh.statusUpdatedAt > 0 ? Qt.formatDateTime(new Date(mesh.statusUpdatedAt), "yyyy-MM-dd HH:mm:ss") : "—"
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            visible: mesh.inviteCopyError !== ""
            Layout.fillWidth: visible
            text: mesh.inviteCopyError
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          HelpLink { Layout.fillWidth: mesh.inviteCopyError === "" }

          PanelActionButton {
            iconText: "󰐲"
            tooltipText: mesh.hasInvite ? "Show invite QR code" : "Invite unavailable"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: mesh.hasInvite && !root.inviteQrLoading
            onClicked: root.showInviteQr()
          }

          PanelActionButton {
            iconText: mesh.inviteCopied ? "✓" : "󰆏"
            tooltipText: mesh.inviteCopied ? "Invite copied" : (mesh.hasInvite ? "Copy invite" : "Invite unavailable")
            foreground: mesh.inviteCopied ? root.accent : root.foreground
            fontFamily: root.fontFamily
            enabled: mesh.hasInvite && !mesh.copyingInvite
            onClicked: mesh.copyInvite()
          }
        }
      }

      Rectangle {
        id: inviteQrSurface
        anchors.fill: parent
        z: 30
        visible: root.inviteQrOpen
        focus: visible
        color: Color.background

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(16)
          spacing: Style.space(10)

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.space(10)

            PanelActionButton {
              iconText: "󰁍"
              tooltipText: "Back to status"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.closeInviteQr()
            }

            Text {
              Layout.fillWidth: true
              text: "INVITE QR CODE"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
          }

          Item {
            id: qrArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            Text {
              anchors.centerIn: parent
              visible: root.inviteQrLoading
              text: "Generating invite QR code…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              anchors.centerIn: parent
              visible: !root.inviteQrLoading && root.inviteQrError !== ""
              width: parent.width - Style.space(32)
              text: root.inviteQrError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
              id: inviteQrCanvas
              readonly property int moduleSize: root.inviteQrSize > 0
                ? Math.max(2, Math.floor(Math.min(qrArea.width - Style.space(32), qrArea.height - Style.space(32)) / root.inviteQrSize))
                : 0
              visible: root.inviteQrSize > 0 && !root.inviteQrLoading && root.inviteQrError === ""
              width: root.inviteQrSize * moduleSize
              height: width
              anchors.centerIn: parent
              color: "white"

              Grid {
                anchors.fill: parent
                columns: root.inviteQrSize

                Repeater {
                  model: root.inviteQrSize * root.inviteQrSize

                  Rectangle {
                    required property int index
                    readonly property int matrixRow: Math.floor(index / root.inviteQrSize)
                    readonly property int matrixColumn: index % root.inviteQrSize
                    readonly property string matrixText: matrixRow < root.inviteQrRows.length ? String(root.inviteQrRows[matrixRow] || "") : ""
                    width: inviteQrCanvas.moduleSize
                    height: width
                    color: matrixText.charAt(matrixColumn) === "1" ? "#111111" : "transparent"
                  }
                }
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: "Anyone who scans this code can join the plaintext topic."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }

    Rectangle {
      id: clipboardSurface
      anchors.fill: parent
      z: 20
      visible: root.clipboardOpen || clipboardRotation.angle < 89.9
      opacity: 1.0 - clipboardRotation.angle / 90.0
      color: Color.background
      radius: Style.cornerRadius

      HoverHandler {
        enabled: root.pointerCursorReady
        cursorShape: Qt.ArrowCursor
      }

      transform: Rotation {
        id: clipboardRotation
        origin.x: clipboardSurface.width / 2
        origin.y: clipboardSurface.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: root.clipboardOpen ? 0 : 90
        Behavior on angle {
          NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          PanelActionButton {
            iconText: "󰁍"
            tooltipText: "Back to chat"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.setClipboardSurface(false)
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(1)
            Text {
              Layout.fillWidth: true
              text: "BROADCAST CLIPBOARD"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              text: "Choose a text entry to send to every connected peer"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          implicitHeight: Style.space(44)
          radius: 0
          color: root.subtle
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.10)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(9)

            Text {
              text: "󰍉"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.icon
            }

            TextField {
              id: clipboardSearchField
              Layout.fillWidth: true
              placeholderText: "Search clipboard history"
              text: root.clipboardQuery
              font.family: root.fontFamily
              cursorVisible: activeFocus && root.opened && root.clipboardOpen
              cursorDelegate: Rectangle {
                width: 2
                color: root.foreground
                visible: clipboardSearchField.cursorVisible
              }
              background: Item {}
              onTextChanged: {
                root.clipboardQuery = text
                root.clipboardIndex = 0
                if (clipboardList.count > 0) clipboardList.positionViewAtIndex(0, ListView.Beginning)
              }
            }

            Text {
              text: clipboardList.count + " item" + (clipboardList.count === 1 ? "" : "s")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 0

          Rectangle {
            Layout.preferredWidth: parent.width * 0.46
            Layout.fillHeight: true
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)

            ListView {
              id: clipboardList
              anchors.fill: parent
              model: root.displayedClipboard
              clip: true
              spacing: Style.space(3)
              boundsBehavior: Flickable.StopAtBounds
              currentIndex: root.clipboardIndex
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: Rectangle {
                id: clipboardRow
                required property int index
                required property var modelData
                width: clipboardList.width
                height: Style.space(48)
                color: index === root.clipboardIndex
                  ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                  : "transparent"

                Text {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  text: modelData.previewText
                  color: index === root.clipboardIndex ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                  verticalAlignment: Text.AlignVCenter
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onEntered: root.clipboardIndex = clipboardRow.index
                  onClicked: root.clipboardIndex = clipboardRow.index
                  onDoubleClicked: root.broadcastClipboardSelection()
                }
              }
            }

            Column {
              anchors.centerIn: parent
              visible: clipboardList.count === 0
              spacing: Style.space(8)
              Text {
                width: parent.width
                text: "󰅌"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
                horizontalAlignment: Text.AlignHCenter
              }
              Text {
                width: parent.width
                text: root.clipboardHistory.length === 0 ? "Clipboard is empty" : "No matches"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }

          Rectangle {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "transparent"

            Flickable {
              anchors.fill: parent
              anchors.margins: Style.space(14)
              contentWidth: width
              contentHeight: clipboardPreview.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              Text {
                id: clipboardPreview
                width: parent.width
                text: root.displayedClipboard.length > 0 && root.clipboardIndex < root.displayedClipboard.length
                  ? root.displayedClipboard[root.clipboardIndex].fullText : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                wrapMode: Text.WrapAnywhere
                renderType: Text.NativeRendering
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          HelpLink { Layout.fillWidth: true }

          Button {
            text: mesh.sending ? "Broadcasting…" : "Broadcast"
            enabled: clipboardList.count > 0 && !mesh.sending
            onClicked: root.broadcastClipboardSelection()
          }
        }
      }
    }

    Rectangle {
      id: helpSurface
      anchors.fill: parent
      z: 40
      visible: root.helpOpen || helpRotation.angle < 89.9
      opacity: 1.0 - helpRotation.angle / 90.0
      color: Color.background
      radius: Style.cornerRadius
      focus: root.helpOpen

      HoverHandler {
        enabled: root.pointerCursorReady
        cursorShape: Qt.ArrowCursor
      }

      transform: Rotation {
        id: helpRotation
        origin.x: helpSurface.width / 2
        origin.y: helpSurface.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: root.helpOpen ? 0 : 90
        Behavior on angle {
          NumberAnimation { duration: 220; easing.type: Easing.InOutQuad }
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.space(16)
        spacing: Style.space(10)

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(10)

          PanelActionButton {
            iconText: "󰁍"
            tooltipText: "Back"
            foreground: root.foreground
            fontFamily: root.fontFamily
            onClicked: root.helpOpen = false
          }

          Text {
            Layout.fillWidth: true
            text: "KEY BINDINGS"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.bold: true
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(4)

          Repeater {
            model: root.helpTabs

            delegate: Rectangle {
              required property int index
              required property var modelData
              Layout.fillWidth: true
              height: Style.space(34)
              color: index === root.helpTab ? root.subtle : "transparent"
              border.width: index === root.helpTab ? 1 : 0
              border.color: root.accent

              Text {
                anchors.centerIn: parent
                text: modelData.label
                color: index === root.helpTab ? root.accent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.helpTab = parent.index
              }
            }
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          color: root.subtle
          radius: Style.cornerRadius

          ListView {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            model: root.activeHelpBindings
            clip: true
            spacing: Style.space(2)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: RowLayout {
              required property var modelData
              width: ListView.view.width
              height: Style.space(30)
              spacing: Style.space(16)

              Text {
                Layout.preferredWidth: Style.space(145)
                text: modelData.key
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                Layout.fillWidth: true
                text: modelData.action
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }
            }
          }
        }

        HelpLink { Layout.fillWidth: true }
      }
    }
  }

  component HelpLink: Text {
    text: "ctrl+k  key bindings"
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleHelp()
    }
  }

  component StatusRow: RowLayout {
    property string label: ""
    property string value: "—"
    property color valueColor: root.foreground
    property bool wrapValue: false
    property bool copyable: false
    property string copyKey: ""
    property bool openable: false

    Layout.fillWidth: true
    spacing: Style.space(16)

    Text {
      Layout.preferredWidth: Style.space(170)
      Layout.alignment: Qt.AlignTop
      text: parent.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    PanelActionButton {
      visible: parent.copyable
      iconText: root.copiedStatusKey === parent.copyKey ? "✓" : "󰆏"
      tooltipText: root.copiedStatusKey === parent.copyKey ? "Copied" : "Copy " + parent.label.toLowerCase()
      foreground: root.copiedStatusKey === parent.copyKey ? root.accent : root.dim
      fontFamily: root.fontFamily
      onClicked: root.copyStatusValue(parent.value, parent.copyKey)
    }

    PanelActionButton {
      visible: parent.openable
      iconText: "󰋜"
      tooltipText: "Open state directory"
      foreground: root.dim
      fontFamily: root.fontFamily
      onClicked: root.openStateDir()
    }

    Text {
      Layout.fillWidth: true
      text: parent.value
      color: parent.valueColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: parent.wrapValue ? Text.AlignLeft : Text.AlignRight
      wrapMode: parent.wrapValue ? Text.WrapAnywhere : Text.NoWrap
      elide: parent.wrapValue ? Text.ElideNone : Text.ElideMiddle
    }
  }
}
