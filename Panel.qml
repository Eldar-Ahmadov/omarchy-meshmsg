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
  property int previousMessageCount: 0

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
    if (messageList.count > 0) messageList.positionViewAtEnd()
  }

  onOpenedChanged: if (opened) {
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
    function status(): string {
      return JSON.stringify({ running: mesh.running, connected: mesh.topicJoined, neighbors: mesh.neighbors, peer: mesh.peer })
    }
  }

  Shortcut {
    sequence: "Escape"
    context: Qt.ApplicationShortcut
    enabled: root.opened
    onActivated: root.close()
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
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))

    ColumnLayout {
      id: content
      width: parent.width
      spacing: Style.space(12)

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

        Button {
          visible: mesh.installed
          text: mesh.running ? "Stop" : "Start"
          enabled: !mesh.busy
          onClicked: mesh.running ? mesh.stopDaemon() : mesh.startDaemon()
        }
      }

      Text {
        visible: mesh.peer !== ""
        Layout.fillWidth: true
        text: (mesh.role || "peer") + " · " + mesh.shortPeer(mesh.peer) + (mesh.topic !== "" ? " · topic " + mesh.shortPeer(mesh.topic) : "")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideMiddle
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

      Rectangle {
        visible: mesh.installed && mesh.running
        Layout.fillWidth: true
        Layout.preferredHeight: Style.space(360)
        radius: Style.cornerRadius
        color: root.subtle
        clip: true

        Text {
          anchors.centerIn: parent
          visible: mesh.messages.length === 0
          text: mesh.topicJoined ? "No messages yet" : "Waiting for a mesh peer…"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        ListView {
          id: messageList
          anchors.fill: parent
          anchors.margins: Style.space(10)
          spacing: Style.space(8)
          clip: true
          model: mesh.messages
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
              // Keep chat bubbles wide enough for peer IDs, timestamps, and
              // normal message lines. Deriving this from bubbleContent's
              // implicit width was circular because that content is anchored
              // to the bubble, collapsing every message to the 120px minimum.
              width: parent.width * 0.86
              implicitHeight: bubbleContent.implicitHeight + Style.space(16)
              anchors.right: modelData.outgoing ? parent.right : undefined
              anchors.left: modelData.outgoing ? undefined : parent.left
              radius: Style.cornerRadius
              color: modelData.outgoing ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)

              Column {
                id: bubbleContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: Style.space(11)
                spacing: Style.space(3)

                RowLayout {
                  width: parent.width
                  Text {
                    Layout.fillWidth: true
                    text: modelData.outgoing ? "YOU" : mesh.shortPeer(modelData.from)
                    color: modelData.outgoing ? root.accent : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                  Text {
                    text: Qt.formatTime(new Date(modelData.timestampMs), "HH:mm")
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                Text {
                  width: parent.width
                  text: modelData.body
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  wrapMode: Text.WrapAnywhere
                  topPadding: Style.space(8)
                  bottomPadding: Style.space(4)
                }

                Item {
                  width: parent.width
                  implicitHeight: copyButton.implicitHeight

                  PanelActionButton {
                    id: copyButton
                    anchors.right: parent.right
                    iconText: messageDelegate.copied ? "✓" : "󰆏"
                    tooltipText: messageDelegate.copied ? "Copied" : "Copy message"
                    foreground: messageDelegate.copied ? root.accent : root.foreground
                    fontFamily: root.fontFamily
                    onClicked: messageDelegate.copyMessage()
                  }
                }
              }
            }
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
          text: "ESC  CLOSE · ENTER  SEND"
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
  }
}
