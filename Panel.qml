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
  property string clipboardQuery: ""
  property var clipboardHistory: []
  property int clipboardIndex: 0
  property bool messageCursorActive: false
  property string copiedStatusKey: ""
  property int previousMessageCount: 0
  readonly property var displayedMessages: filterMessages(mesh.messages, searchQuery)
  readonly property var displayedClipboard: filterClipboard(clipboardHistory, clipboardQuery)
  readonly property string clipboardHistoryPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"

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

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function sendCurrent() {
    if (mesh.sendMessage(messageField.text)) {
      messageField.text = ""
      Qt.callLater(scrollToBottom)
    }
  }

  function submitJoin() {
    if (mesh.joinChat(inviteField.text, replaceExisting)) {
      inviteField.text = ""
      revealInvite = false
    }
  }

  function scrollToBottom() {
    if (messageList.count > 0) {
      messageList.currentIndex = messageList.count - 1
      messageList.positionViewAtEnd()
    }
  }

  function filterMessages(values, query) {
    var needle = String(query || "").trim().toLowerCase()
    if (needle === "") return values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var message = values[i] || {}
      var haystack = String(message.body || "") + " " + String(message.from || "")
      if (haystack.toLowerCase().indexOf(needle) !== -1) result.push(message)
    }
    return result
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
    clipboardOpen = open
    if (open) {
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

  function setSettingsSurface(open) {
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
      statusSurface.focus = false
      if (mesh.running) chatFocusTimer.restart()
    }
  }

  onOpenedChanged: if (opened) {
    settingsOpen = false
    clipboardOpen = false
    searchOpen = false
    searchQuery = ""
    unread = 0
    previousMessageCount = mesh.messages.length
    mesh.refresh()
    Qt.callLater(function() {
      root.scrollToBottom()
      if (mesh.running) messageField.forceActiveFocus()
    })
  }

  Service {
    id: mesh
    settings: root.settings
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
    function onMessagesChanged() {
      var count = mesh.messages.length
      if (!root.opened && count > root.previousMessageCount)
        root.unread += count - root.previousMessageCount
      root.previousMessageCount = count
      if (root.opened) Qt.callLater(root.scrollToBottom)
    }
    function onRunningChanged() {
      if (mesh.running) root.showJoin = false
    }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { mesh.refresh(); return "ok" }
    function start(): string { mesh.startDaemon(); return "ok" }
    function stop(): string { mesh.stopDaemon(); return "ok" }
    function settings(): string { root.open(); root.setSettingsSurface(true); return "ok" }
    function clipboard(): string { root.open(); root.setClipboardSurface(true); return "ok" }
    function copyInvite(): string { return mesh.copyInvite() ? "ok" : "unavailable" }
    function status(): string {
      return JSON.stringify({ running: mesh.running, connected: mesh.topicJoined, neighbors: mesh.neighbors, peer: mesh.peer })
    }
  }

  Shortcut {
    sequence: "Escape"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: {
      if (root.clipboardOpen) root.setClipboardSurface(false)
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
    sequence: "Tab"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: root.setClipboardSurface(!root.clipboardOpen)
  }

  Shortcut {
    sequence: "Ctrl+S"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: root.setSettingsSurface(!root.settingsOpen)
  }

  Timer {
    id: chatFocusTimer
    interval: 240
    repeat: false
    onTriggered: if (root.opened && !root.settingsOpen && !root.clipboardOpen && mesh.running) messageField.forceActiveFocus()
  }

  Timer {
    id: copiedStatusClear
    interval: 1200
    repeat: false
    onTriggered: root.copiedStatusKey = ""
  }

  Shortcut {
    sequence: "C"
    context: Qt.ApplicationShortcut
    enabled: root.opened && root.settingsOpen && mesh.hasInvite && !mesh.copyingInvite
    onActivated: mesh.copyInvite()
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
    tooltipText: root.unread > 0 ? root.unread + " unread meshmsg message" + (root.unread === 1 ? "" : "s")
      : "Meshmsg · " + root.connectionLabel.toLowerCase()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) mesh.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: mesh.running ? messageField : (root.showJoin ? inviteField : null)
    contentWidth: panel.fittedContentWidth(Style.space(645))
    contentHeight: panel.fittedContentHeight(content.implicitHeight + Style.space(28), Style.space(620))

    Rectangle {
      id: chatSurfaceBorder
      anchors.fill: parent
      visible: content.visible
      opacity: content.opacity
      color: "transparent"
      radius: Style.cornerRadius
      border.width: 1
      border.color: root.subtle

      transform: Rotation {
        origin.x: chatSurfaceBorder.width / 2
        origin.y: chatSurfaceBorder.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: chatRotation.angle
      }
    }

    ColumnLayout {
      id: content
      x: Style.space(14)
      y: Style.space(14)
      width: parent.width - Style.space(28)
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
          text: mesh.running ? "Stop" : "Start"
          enabled: !mesh.busy
          onClicked: mesh.running ? mesh.stopDaemon() : mesh.startDaemon()
        }
      }

      Text {
        visible: mesh.actionStatus !== "" || mesh.lastError !== ""
        Layout.fillWidth: true
        text: mesh.lastError !== "" ? mesh.lastError : mesh.actionStatus
        color: mesh.lastError !== "" ? root.urgent : root.dim
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
        Layout.preferredHeight: Style.space(360)
        clip: true

        Rectangle {
          id: searchBar
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: Style.space(8)
          height: Style.space(44)
          z: 3
          visible: root.searchOpen
          radius: Style.space(10)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
          border.width: 1
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(8)
            spacing: Style.space(8)

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

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
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
                  width: parent.width
                  rightPadding: Style.space(30)
                  topPadding: Style.space(3)
                  bottomPadding: Style.space(2)
                  text: modelData.body
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WrapAnywhere
                  renderType: Text.NativeRendering
                }
              }

              Rectangle {
                id: copyButton
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Style.space(7)
                width: Style.space(22)
                height: width
                radius: Style.space(3)
                opacity: rowMouse.containsMouse || messageDelegate.copied ? 1 : 0
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
        Text {
          Layout.fillWidth: true
          text: "esc  close · tab  clipboard · ctrl+s  settings · ↑↓  messages · ctrl+f  search · enter  send"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          visible: mesh.messages.length > 0
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
      border.width: 1
      border.color: root.subtle

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
            Text {
              text: "Live information from meshmsg --json status"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          PanelActionButton {
            iconText: "󰑓"
            tooltipText: "Refresh status"
            foreground: root.foreground
            fontFamily: root.fontFamily
            enabled: mesh.installed
            onClicked: mesh.refresh()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
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
              StatusRow { label: "STATE DIR"; value: mesh.stateDir || "—"; wrapValue: true; copyable: mesh.stateDir !== ""; copyKey: "state-dir" }
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
            Layout.fillWidth: true
            text: mesh.inviteCopyError !== "" ? mesh.inviteCopyError : "esc  back · ctrl+s  chat · tab  clipboard · c  copy invite"
            color: mesh.inviteCopyError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
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
    }

    Rectangle {
      id: clipboardSurface
      anchors.fill: parent
      z: 20
      visible: root.clipboardOpen || clipboardRotation.angle < 89.9
      opacity: 1.0 - clipboardRotation.angle / 90.0
      color: Color.background
      radius: Style.cornerRadius
      border.width: 1
      border.color: root.subtle

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
          radius: Style.space(8)
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

          Text {
            Layout.fillWidth: true
            text: "esc  back · tab  chat · ctrl+s  settings · ↑↓  select · enter  broadcast"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Button {
            text: mesh.sending ? "Broadcasting…" : "Broadcast"
            enabled: clipboardList.count > 0 && !mesh.sending
            onClicked: root.broadcastClipboardSelection()
          }
        }
      }
    }
  }

  component StatusRow: RowLayout {
    property string label: ""
    property string value: "—"
    property color valueColor: root.foreground
    property bool wrapValue: false
    property bool copyable: false
    property string copyKey: ""

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
