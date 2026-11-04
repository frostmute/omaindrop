pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
  id: root

  readonly property string pluginId: "io.github.frostmute.omaindrop"

  property var shell: null
  property var manifest: null
  property bool closingFromHost: false

  function open(payloadJson) {
    closingFromHost = false
    win.visible = true
    client.refreshAll()
    client.readClipboard(function(url) { root.prefillUrl = url })
  }

  function close() {
    closingFromHost = true
    win.visible = false
    closingFromHost = false
  }

  DropClient {
    id: client
  }

  property string searchQuery: ""
  property var selected: null
  property string saveCollection: String(client.defaultCollection)
  property string saveTags: ""
  property string prefillUrl: ""
  property string notice: ""

  readonly property bool isSearching: searchQuery.trim().length > 0
  readonly property var shownItems: isSearching ? client.searchResults : client.items

  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function showNotice(msg) {
    root.notice = msg
    noticeTimer.restart()
  }

  function selectCollection(id) {
    searchField.text = ""
    root.selected = null
    client.loadRecent(id)
  }

  function searchTag(name) {
    searchField.text = "#" + name
    client.search(searchField.text)
  }

  function formatDate(iso) {
    if (!iso) return ""
    var d = new Date(iso)
    if (isNaN(d.getTime())) return ""
    return d.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
  }

  function submitSave() {
    var url = saveUrlField.text.trim() || root.prefillUrl
    client.save(url, root.saveCollection, root.saveTags, function(res) {
      if (res && res.ok) {
        saveUrlField.text = ""
        root.prefillUrl = ""
      }
    })
  }

  // Keep the inspector pointed at fresh data after a move / retag
  Connections {
    target: client
    function onSaved(ok, message) { root.showNotice(message) }
    function onNotice(message) { root.showNotice(message) }
  }

  Timer {
    id: noticeTimer
    interval: 4000
    onTriggered: root.notice = ""
  }

  Timer {
    id: searchDebounce
    interval: 300
    onTriggered: client.search(root.searchQuery)
  }

  Timer {
    id: screenshotDelay
    interval: 350
    onTriggered: client.screenshot(root.saveCollection, root.saveTags, false, function() { win.visible = true })
  }

  FloatingWindow {
    id: win
    title: "Omaindrop — Raindrop.io"
    color: Commons.Color.background
    implicitWidth: 1040
    implicitHeight: 700
    minimumSize: Qt.size(780, 520)
    visible: false
    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function") {
        root.shell.hide(root.pluginId)
      }
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      readonly property bool typing: searchField.activeFocus || saveUrlField.activeFocus || saveTagsField.activeFocus || inspectorTags.activeFocus

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (focusScope.typing) {
            focusScope.forceActiveFocus()
          } else {
            win.visible = false
          }
          event.accepted = true
        } else if (focusScope.typing) {
          return
        } else if (event.key === Qt.Key_Slash) {
          searchField.forceActiveFocus()
          event.accepted = true
        } else if (event.key === Qt.Key_N) {
          saveUrlField.forceActiveFocus()
          event.accepted = true
        } else if (event.key === Qt.Key_R) {
          client.refreshAll()
          event.accepted = true
        } else if (event.key === Qt.Key_O && root.selected) {
          client.openLink(root.selected.link)
          event.accepted = true
        } else if (event.key === Qt.Key_Delete && root.selected) {
          client.trash(root.selected.id)
          root.selected = null
          event.accepted = true
        }
      }

      RowLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // LEFT SIDEBAR
        // ==========================================
        Rectangle {
          Layout.preferredWidth: Style.space(240)
          Layout.fillHeight: true
          color: root.tint(Commons.Color.foreground, 0.03)
          border.width: 1
          border.color: root.tint(Commons.Color.foreground, 0.08)

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.spacing.md
            spacing: Style.spacing.sm

            // App header
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xs

              Text {
                text: "󰖌"
                font.family: Style.font.family
                font.pixelSize: Style.font.title * 1.3
                color: Commons.Color.accent
              }

              Column {
                Text {
                  text: "OMAINDROP"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Commons.Color.foreground
                }
                Text {
                  text: "Raindrop.io for Omarchy"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption * 0.85
                  color: Commons.Color.muted
                }
              }

              Item { Layout.fillWidth: true }
            }

            PanelSeparator { Layout.fillWidth: true }

            PanelSectionHeader {
              text: "COLLECTIONS"
              Layout.topMargin: Style.space(4)
            }

            ListView {
              id: collectionList
              Layout.fillWidth: true
              Layout.fillHeight: true
              Layout.minimumHeight: Style.space(160)
              clip: true
              spacing: Style.space(1)
              model: client.allCollections
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: Rectangle {
                id: navItem
                required property var modelData
                readonly property bool isSelected: !root.isSearching && client.currentCollection === modelData.id

                width: collectionList.width
                implicitHeight: Style.space(26)
                radius: Style.cornerRadius
                color: isSelected ? root.tint(Commons.Color.accent, 0.16) : (navHover.hovered ? root.tint(Commons.Color.foreground, 0.06) : "transparent")

                HoverHandler { id: navHover }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6) + (navItem.modelData.depth || 0) * Style.space(12)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(6)

                  Text {
                    text: navItem.modelData.id === -1 ? "󰚇" : (navItem.modelData.id === 0 ? "󰖌" : "󰉋")
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: navItem.isSelected ? Commons.Color.accent : Commons.Color.muted
                  }

                  Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: navItem.modelData.title
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: navItem.isSelected
                    color: navItem.isSelected ? Commons.Color.accent : Commons.Color.foreground
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: String(navItem.modelData.count || 0)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 0.85
                    color: Commons.Color.muted
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectCollection(navItem.modelData.id)
                }
              }
            }

            PanelSectionHeader {
              text: "TAGS"
              visible: client.tags.length > 0
            }

            Flow {
              Layout.fillWidth: true
              Layout.maximumHeight: Style.space(120)
              clip: true
              spacing: Style.space(4)
              visible: client.tags.length > 0

              Repeater {
                model: client.tags.slice(0, 24)

                delegate: Rectangle {
                  id: tagChip
                  required property var modelData
                  implicitWidth: tagText.implicitWidth + Style.space(10)
                  implicitHeight: Style.space(20)
                  radius: height / 2
                  color: tagHover.hovered ? root.tint(Commons.Color.accent, 0.2) : root.tint(Commons.Color.foreground, 0.06)

                  HoverHandler { id: tagHover }

                  Text {
                    id: tagText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "#" + tagChip.modelData.name
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 0.85
                    color: Commons.Color.foreground
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.searchTag(tagChip.modelData.name)
                  }
                }
              }
            }

            PanelSeparator { Layout.fillWidth: true }

            // Footer actions
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xs

              PanelActionButton {
                iconText: "󰇚"
                visible: client.vaultAvailable
                tooltipText: client.vaultCommand
                  ? "Pull to vault (Make It Rain in " + client.vaultName + ")"
                  : "Pull to vault: opens " + client.vaultName + " for Make It Rain"
                onClicked: client.pullToVault()
              }

              PanelActionButton {
                iconText: "󰏌"
                tooltipText: "Open Raindrop in the browser"
                onClicked: client.openLink("")
              }

              Item { Layout.fillWidth: true }

              Text {
                textFormat: Text.PlainText
                text: client.tokenMissing ? "no token" : (client.stale ? "offline" : (client.loading ? "syncing" : "online"))
                font.family: Style.font.family
                font.pixelSize: Style.font.caption * 0.85
                color: client.tokenMissing || client.stale ? Commons.Color.urgent : Commons.Color.muted
              }
            }
          }
        }

        // ==========================================
        // MAIN COLUMN
        // ==========================================
        ColumnLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          Layout.margins: Style.spacing.md
          spacing: Style.spacing.sm

          // Token missing banner
          Rectangle {
            Layout.fillWidth: true
            visible: client.tokenMissing
            implicitHeight: bannerText.implicitHeight + Style.space(16)
            radius: Style.cornerRadius
            color: root.tint(Commons.Color.urgent, 0.14)
            border.width: 1
            border.color: root.tint(Commons.Color.urgent, 0.4)

            Text {
              id: bannerText
              anchors.fill: parent
              anchors.margins: Style.space(8)
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "No Raindrop token yet. Open the bar popup to paste one, or run: omaindrop-backend set-token <token>  (stored in ~/.config/raindrop/token)"
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Commons.Color.foreground
            }
          }

          // Save row
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xs
            enabled: !client.tokenMissing

            TextField {
              id: saveUrlField
              Layout.fillWidth: true
              placeholderText: root.prefillUrl ? ("Enter saves " + root.prefillUrl) : "Paste a link to save (n)..."
              Keys.onReturnPressed: root.submitSave()
            }

            Dropdown {
              Layout.preferredWidth: Style.space(180)
              showLabel: false
              options: client.collectionOptions()
              value: root.saveCollection
              onChanged: function(v) { root.saveCollection = v }
            }

            TextField {
              id: saveTagsField
              Layout.preferredWidth: Style.space(180)
              placeholderText: "tags, comma, separated"
              text: root.saveTags
              onTextChanged: root.saveTags = text
              Keys.onReturnPressed: root.submitSave()
            }

            PanelActionButton {
              iconText: "󰐕"
              tooltipText: "Save link"
              enabled: saveUrlField.text.trim().length > 0 || root.prefillUrl.length > 0
              onClicked: root.submitSave()
            }

            PanelActionButton {
              iconText: "󰄀"
              tooltipText: "Screenshot a region to Raindrop"
              onClicked: {
                win.visible = false
                screenshotDelay.restart()
              }
            }
          }

          // Search row
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xs

            TextField {
              id: searchField
              Layout.fillWidth: true
              placeholderText: "Search all bookmarks, #tag, site:domain (/)..."
              onTextChanged: {
                root.searchQuery = text
                searchDebounce.restart()
              }
            }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh (r)"
              onClicked: client.refreshAll()
            }
          }

          // Title + notice line
          RowLayout {
            Layout.fillWidth: true

            Text {
              textFormat: Text.PlainText
              text: root.isSearching
                ? ("Search · " + client.searchTotal + " found")
                : (client.collectionTitle(client.currentCollection) + " · " + client.itemsTotal)
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              color: Commons.Color.foreground
            }

            Item { Layout.fillWidth: true }

            Text {
              Layout.maximumWidth: Style.space(420)
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: root.notice || client.lastError
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: root.notice ? Commons.Color.accent : Commons.Color.urgent
            }
          }

          RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.md

            // Item list
            ListView {
              id: itemList
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              spacing: Style.space(2)
              model: root.shownItems
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: Rectangle {
                id: itemRow
                required property var modelData
                readonly property bool isSelected: root.selected !== null && root.selected.id === modelData.id

                width: itemList.width
                implicitHeight: Style.space(52)
                radius: Style.cornerRadius
                color: isSelected ? root.tint(Commons.Color.accent, 0.14) : (itemHover.hovered ? root.tint(Commons.Color.foreground, 0.06) : "transparent")
                border.width: isSelected ? 1 : 0
                border.color: root.tint(Commons.Color.accent, 0.5)

                HoverHandler { id: itemHover }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.selected = itemRow.modelData
                    focusScope.forceActiveFocus()
                  }
                  onDoubleClicked: client.openLink(itemRow.modelData.link)
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.spacing.sm

                  Rectangle {
                    Layout.preferredWidth: Style.space(32)
                    Layout.preferredHeight: Style.space(32)
                    radius: Style.cornerRadius
                    color: root.tint(Commons.Color.accent, 0.16)

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: (itemRow.modelData.domain || itemRow.modelData.title || "?").replace(/^www\./, "").charAt(0).toUpperCase()
                      font.family: Style.font.family
                      font.pixelSize: Style.font.title
                      font.bold: true
                      color: Commons.Color.accent
                    }
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                      Layout.fillWidth: true
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: itemRow.modelData.title
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                      color: Commons.Color.foreground
                    }

                    Text {
                      Layout.fillWidth: true
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: {
                        var bits = [itemRow.modelData.domain, root.formatDate(itemRow.modelData.created)]
                        var tags = itemRow.modelData.tags || []
                        if (tags.length) bits.push("#" + tags.join(" #"))
                        if (root.isSearching || client.currentCollection === 0) bits.push(client.collectionTitle(itemRow.modelData.collectionId))
                        return bits.filter(function(b) { return b }).join("  ·  ")
                      }
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption * 0.9
                      color: Commons.Color.muted
                    }
                  }
                }
              }

              Text {
                anchors.centerIn: parent
                visible: itemList.count === 0
                textFormat: Text.PlainText
                text: root.isSearching
                  ? (client.searching ? "Searching..." : "Nothing matches")
                  : (client.loading ? "Loading..." : (client.currentCollection === -1 ? "Unsorted is empty. Nice." : "Nothing here yet"))
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                color: Commons.Color.muted
              }
            }

            // ==========================================
            // INSPECTOR
            // ==========================================
            Rectangle {
              Layout.preferredWidth: Style.space(320)
              Layout.fillHeight: true
              radius: Style.cornerRadius
              color: root.tint(Commons.Color.foreground, 0.03)
              border.width: 1
              border.color: root.tint(Commons.Color.foreground, 0.08)

              Text {
                anchors.centerIn: parent
                visible: root.selected === null
                textFormat: Text.PlainText
                text: "Select a bookmark"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Commons.Color.muted
              }

              Flickable {
                anchors.fill: parent
                anchors.margins: Style.spacing.md
                visible: root.selected !== null
                clip: true
                contentHeight: inspectorColumn.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                  id: inspectorColumn
                  width: parent.width
                  spacing: Style.spacing.sm

                  Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.selected ? root.selected.title : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                    color: Commons.Color.foreground
                  }

                  Text {
                    Layout.fillWidth: true
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: root.selected ? root.selected.link : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Commons.Color.accent

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.selected) client.openLink(root.selected.link)
                    }
                  }

                  Text {
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: !root.selected ? "" : [client.collectionTitle(root.selected.collectionId), root.selected.type, root.formatDate(root.selected.created)].filter(function(b) { return b }).join("  ·  ")
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 0.9
                    color: Commons.Color.muted
                  }

                  Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.selected ? root.selected.excerpt : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Commons.Color.foreground
                  }

                  Text {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    text: root.selected && root.selected.note ? ("Note: " + root.selected.note) : ""
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    font.italic: true
                    color: Commons.Color.muted
                  }

                  PanelSeparator { Layout.fillWidth: true }

                  PanelSectionHeader { text: "TAGS" }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.xs

                    TextField {
                      id: inspectorTags
                      Layout.fillWidth: true
                      placeholderText: "tags, comma, separated"
                      text: root.selected ? (root.selected.tags || []).join(", ") : ""
                      Keys.onReturnPressed: applyTags.clicked()
                    }

                    PanelActionButton {
                      id: applyTags
                      iconText: "󰓹"
                      tooltipText: "Apply tags"
                      onClicked: {
                        if (!root.selected) return
                        var id = root.selected.id
                        client.setTags(id, inspectorTags.text, function(res) {
                          if (res && res.ok) {
                            root.selected = res.item
                            root.showNotice("Tags updated")
                          } else {
                            root.showNotice((res && res.error) || "Couldn't update tags")
                          }
                        })
                      }
                    }
                  }

                  PanelSectionHeader { text: "MOVE TO" }

                  Dropdown {
                    Layout.fillWidth: true
                    showLabel: false
                    options: client.collectionOptions()
                    value: root.selected ? String(root.selected.collectionId) : "-1"
                    onChanged: function(v) {
                      if (!root.selected || String(root.selected.collectionId) === v) return
                      client.move(root.selected.id, v, function(res) {
                        if (res && res.ok) {
                          root.showNotice("Moved to " + client.collectionTitle(Number(v)))
                          root.selected = null
                        } else {
                          root.showNotice((res && res.error) || "Couldn't move it")
                        }
                      })
                    }
                  }

                  PanelSeparator { Layout.fillWidth: true }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.spacing.xs

                    PanelActionButton {
                      iconText: "󰏌"
                      tooltipText: "Open (o)"
                      onClicked: if (root.selected) client.openLink(root.selected.link)
                    }

                    PanelActionButton {
                      iconText: "󰆏"
                      tooltipText: "Copy link"
                      onClicked: if (root.selected) client.copyLink(root.selected.link)
                    }

                    Item { Layout.fillWidth: true }

                    PanelActionButton {
                      iconText: "󰩺"
                      tooltipText: "Move to Trash (Del)"
                      hoverColor: Commons.Color.urgent
                      onClicked: {
                        if (!root.selected) return
                        client.trash(root.selected.id)
                        root.selected = null
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
