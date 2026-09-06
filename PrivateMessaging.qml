import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui

Rectangle {
  id: root

  required property var service
  required property color foreground
  required property color dim
  required property color accent
  required property color urgent
  required property color subtle
  required property string fontFamily
  property bool active: false
  property bool compact: false
  property bool detailOpen: false
  property bool creating: false
  property int selectedIndex: -1
  property string peerQuery: ""
  property string draftPeerKey: ""
  property string draftAlias: ""

  signal closeRequested()
  signal helpRequested()

  color: Color.background
  radius: Style.cornerRadius
  focus: active

  readonly property bool capable: value("privateSendAvailable", value("privateMessagingAvailable", false)) === true
  readonly property var conversations: value("conversations", value("privateConversations", [])) || []
  readonly property bool directoryAvailable: value("peerDirectoryAvailable", false) === true
  readonly property var knownPeers: value("knownPeers", []) || []
  readonly property var allPeers: buildPeerRows()
  readonly property var peers: filterPeerRows(allPeers, peerQuery)
  readonly property var selected: selectedIndex >= 0 && selectedIndex < peers.length ? peers[selectedIndex] : null
  readonly property string selectedKey: String(selected && (selected.peerKey || selected.peer || selected.key) || draftPeerKey)
  readonly property bool hasSelection: selectedKey !== ""
  readonly property bool selectedOnline: !selected || !selected._discovered || selected.online === true
  readonly property var selectedMessages: selected && (selected.messages || selected.timeline) || []

  function value(name, fallback) {
    var candidate = service ? service[name] : undefined
    return candidate === undefined ? fallback : candidate
  }

  function invoke(name, args) {
    var callable = service ? service[name] : null
    return typeof callable === "function" ? callable.apply(service, args || []) : false
  }

  function buildPeerRows() {
    var rows = []
    var positions = ({})
    var self = String(value("peer", ""))
    function keyOf(item) { return String(item && (item.peer || item.publicKey || item.peerKey || item.key) || "") }
    function addConversation(source) {
      var id = keyOf(source)
      if (id === "" || id === self || positions[id] !== undefined) return
      var row = {}
      for (var field in source) row[field] = source[field]
      row.peer = id
      row._hasConversation = true
      row._discovered = false
      positions[id] = rows.length
      rows.push(row)
    }
    for (var i = 0; i < conversations.length; i++) addConversation(conversations[i] || {})
    for (i = 0; i < knownPeers.length; i++) {
      var known = knownPeers[i] || {}
      var id = keyOf(known)
      if (id === "" || id === self) continue
      var index = positions[id]
      var target
      if (index === undefined) {
        target = { peer: id, messages: [], unreadCount: 0, lastTimestampMs: Number(known.lastSeenMs || 0), _hasConversation: false }
        positions[id] = rows.length
        rows.push(target)
      } else target = rows[index]
      target.publicKey = String(known.publicKey || id)
      target.alias = known.alias === null || known.alias === undefined ? "" : String(known.alias)
      target.online = known.online === true
      target.lastSeenMs = Number(known.lastSeenMs || 0)
      target.expiresAtMs = Number(known.expiresAtMs || 0)
      target._discovered = true
    }
    rows.sort(function(a, b) {
      if (a.online === true && b.online !== true) return -1
      if (b.online === true && a.online !== true) return 1
      return Number(b.lastSeenMs || b.lastTimestampMs || 0) - Number(a.lastSeenMs || a.lastTimestampMs || 0)
    })
    return rows
  }

  function filterPeerRows(values, query) {
    var needle = String(query || "").trim().toLowerCase()
    if (needle === "") return values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i] || {}
      var key = String(item.peerKey || item.peer || item.key || "")
      var alias = String(item.alias || item.label || item.name || "")
      if ((alias + " " + key).toLowerCase().indexOf(needle) !== -1) result.push(item)
    }
    return result
  }

  function peerLabel(item) {
    var key = String(item && (item.peerKey || item.peer || item.key) || "")
    var alias = String(item && (item.alias || item.label || item.name) || "").trim()
    return alias !== "" ? alias : "Unnamed node"
  }

  function canonicalPeer(value) {
    return /^[0-9a-f]{64}$/.test(String(value || ""))
  }

  function shortKey(key) {
    var text = String(key || "")
    return text.length > 18 ? text.substring(0, 10) + "…" + text.substring(text.length - 6) : text
  }

  function selectConversation(index) {
    if (index < 0 || index >= peers.length) return
    var candidate = peers[index]
    if (candidate._discovered && candidate.online !== true && !candidate._hasConversation) return
    selectedIndex = index
    draftPeerKey = ""
    draftAlias = ""
    detailOpen = true
    var key = String(peers[index].peerKey || peers[index].peer || peers[index].key || "")
    invoke("selectPrivateConversation", [key])
    invoke("markConversationRead", [key])
    Qt.callLater(function() { composer.forceActiveFocus() })
  }

  function moveSelection(delta) {
    if (peers.length === 0) return
    selectConversation(Math.max(0, Math.min(peers.length - 1, (selectedIndex < 0 ? 0 : selectedIndex + delta))))
  }

  function submitPeer() {
    var recipient = recipientField.text.trim()
    if (recipient === "") return
    selectedIndex = -1
    draftPeerKey = recipient
    draftAlias = canonicalPeer(recipient) ? "" : recipient
    detailOpen = true
    recipientField.text = ""
    creating = false
    Qt.callLater(function() { composer.forceActiveFocus() })
  }

  function acceptResolvedRecipient(requested, canonical) {
    if (draftPeerKey !== String(requested || "")) return
    draftPeerKey = String(canonical || "")
    Qt.callLater(function() {
      for (var i = 0; i < root.peers.length; i++) {
        var item = root.peers[i] || {}
        var key = String(item.peerKey || item.peer || item.key || "")
        if (key === root.draftPeerKey) {
          root.selectedIndex = i
          root.draftPeerKey = ""
          root.draftAlias = ""
          root.invoke("selectPrivateConversation", [key])
          root.invoke("markConversationRead", [key])
          break
        }
      }
    })
  }

  function sendCurrent() {
    var body = composer.text.trim()
    if (selectedKey === "" || body === "" || !selectedOnline) return
    if (invoke("sendPrivateMessage", [selectedKey, body]) !== false) composer.text = ""
  }

  function goBack() {
    if (creating) creating = false
    else if (compact && detailOpen) detailOpen = false
    else closeRequested()
  }

  Connections {
    target: root.service
    function onPrivateMessageAccepted(requestedRecipient, canonicalPeer) {
      root.acceptResolvedRecipient(requestedRecipient, canonicalPeer)
    }
  }

  ColumnLayout {
    anchors.fill: parent
    anchors.margins: Style.space(14)
    spacing: Style.space(10)

    RowLayout {
      Layout.fillWidth: true
      PanelActionButton {
        iconText: "󰁍"
        tooltipText: root.compact && root.detailOpen ? "Conversations" : "Back to chat"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.goBack()
      }
      ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Text { text: "PRIVATE MESSAGES"; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
        Text { text: root.compact ? (root.detailOpen && root.selected ? root.peerLabel(root.selected) : "CONVERSATIONS") : "PEERS · DIRECT TEXT"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
      }
      Button {
        visible: root.capable && (!root.compact || !root.detailOpen)
        text: root.creating ? "Cancel" : "New message"
        onClicked: root.creating = !root.creating
      }
    }

    PanelSeparator { Layout.fillWidth: true; foreground: root.foreground }

    Rectangle {
      visible: !root.capable
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: root.subtle
      radius: Style.cornerRadius
      Column {
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(40), Style.space(430))
        spacing: Style.space(10)
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: "󰌾"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.display }
        Text { width: parent.width; text: "Private messaging is unavailable"; horizontalAlignment: Text.AlignHCenter; color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.heading; font.bold: true }
        Text { width: parent.width; text: "Update meshmsg to a version that advertises private-message support. Group chat, status, and clipboard remain available."; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
      }
    }

    ColumnLayout {
      visible: root.capable
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.space(8)

      Rectangle {
        visible: root.creating && (!root.compact || !root.detailOpen)
        Layout.fillWidth: true
        implicitHeight: newForm.implicitHeight + Style.space(20)
        color: root.subtle
        radius: Style.cornerRadius
        ColumnLayout {
          id: newForm
          anchors.fill: parent
          anchors.margins: Style.space(10)
          Text { text: "NEW MESSAGE"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true }
          TextField { id: recipientField; Layout.fillWidth: true; placeholderText: "Peer alias or canonical node ID"; font.family: root.fontFamily; onAccepted: root.submitPeer() }
          Text { Layout.fillWidth: true; text: "Aliases are resolved by meshmsg and must uniquely identify an online peer. The resolved canonical node ID remains the conversation identity."; wrapMode: Text.WordWrap; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          Button { Layout.alignment: Qt.AlignRight; text: "Open"; enabled: recipientField.text.trim() !== ""; onClicked: root.submitPeer() }
        }
      }

      Rectangle {
        visible: !root.compact || !root.detailOpen
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
            id: peerSearchField
            Layout.fillWidth: true
            placeholderText: "Search peers"
            text: root.peerQuery
            font.family: root.fontFamily
            cursorVisible: activeFocus && root.active && (!root.compact || !root.detailOpen)
            cursorDelegate: Rectangle {
              width: 2
              color: root.foreground
              visible: peerSearchField.cursorVisible
            }
            background: Item {}
            onTextChanged: {
              root.peerQuery = text
              root.selectedIndex = -1
              if (peerList.count > 0) peerList.positionViewAtIndex(0, ListView.Beginning)
            }
          }

          Text {
            text: peerList.count + " peer" + (peerList.count === 1 ? "" : "s")
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
          visible: !root.compact || !root.detailOpen
          Layout.preferredWidth: root.compact ? -1 : parent.width * 0.46
          Layout.fillWidth: root.compact
          Layout.fillHeight: true
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.025)

          Text {
            anchors.centerIn: parent
            width: parent.width - Style.space(24)
            visible: root.peers.length === 0
            text: root.peerQuery !== "" ? "No matches" : "No peers"
            horizontalAlignment: Text.AlignHCenter
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          ListView {
            id: peerList
            anchors.fill: parent
            clip: true
            model: root.peers
            spacing: Style.space(3)
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: ListView.view.width
              height: Style.space(48)
              color: index === root.selectedIndex
                ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.20)
                : "transparent"

              Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: 0

                Text {
                  width: parent.width
                  text: root.peerLabel(modelData)
                  color: index === root.selectedIndex ? root.foreground : root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.shortKey(modelData.publicKey || modelData.peerKey || modelData.peer || modelData.key)
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideMiddle
                }
              }

              MouseArea {
                anchors.fill: parent
                enabled: !modelData._discovered || modelData.online || modelData._hasConversation
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.selectConversation(index)
              }
            }
          }
        }

        Rectangle {
          visible: !root.compact
          Layout.preferredWidth: 1
          Layout.fillHeight: true
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14)
        }

        Rectangle {
          visible: !root.compact || root.detailOpen
          Layout.fillWidth: true
          Layout.fillHeight: true
          color: "transparent"
          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.space(10)
            spacing: Style.space(7)
            RowLayout {
              visible: root.hasSelection
              Layout.fillWidth: true
              ColumnLayout { Layout.fillWidth: true; spacing: 0
                Text { Layout.fillWidth: true; text: root.selected ? root.peerLabel(root.selected) : (root.draftAlias !== "" ? root.draftAlias : root.shortKey(root.draftPeerKey)); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
                Text { Layout.fillWidth: true; text: root.selectedKey; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideMiddle }
              }
            }
            Item {
              Layout.fillWidth: true; Layout.fillHeight: true
              Text { anchors.centerIn: parent; visible: !root.hasSelection || root.selectedMessages.length === 0; text: !root.hasSelection ? "Select a conversation" : "No private messages yet"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.body }
              ListView {
                anchors.fill: parent; visible: root.hasSelection; clip: true; model: root.selectedMessages; spacing: Style.space(6); boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Rectangle {
                  required property var modelData
                  width: ListView.view.width; implicitHeight: privateBody.implicitHeight + Style.space(16); radius: Style.cornerRadius
                  color: modelData.outgoing ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.12) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.06)
                  Text { id: privateBody; anchors.left: parent.left; anchors.right: parent.right; anchors.margins: Style.space(8); text: String(modelData.body || modelData.text || ""); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; wrapMode: Text.WrapAnywhere }
                }
              }
            }
            RowLayout {
              visible: root.hasSelection
              Layout.fillWidth: true
              TextField { id: composer; Layout.fillWidth: true; placeholderText: root.selectedOnline ? "Private message" : "Peer is offline"; enabled: root.selectedOnline && !root.value("privateSending", false); font.family: root.fontFamily; onAccepted: root.sendCurrent() }
              Button { text: root.value("privateSending", false) ? "Sending…" : "Send"; enabled: root.selectedOnline && composer.text.trim() !== "" && !root.value("privateSending", false); onClicked: root.sendCurrent() }
            }
            Text { visible: root.hasSelection; Layout.fillWidth: true; text: root.selectedOnline ? "Text only · addressed to the canonical peer key · aliases are untrusted labels" : "This discovered peer is offline; its conversation remains available"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption }
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Text { Layout.fillWidth: true; text: "ctrl+d  group chat   ·   ctrl+k  key bindings"; color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; font.bold: true; MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.helpRequested() } }
    }
  }
}
