pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.frostmute.omaindrop"
  ipcTarget: "io.github.frostmute.omaindrop"
  manageIpc: false

  readonly property string pluginId: "io.github.frostmute.omaindrop"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  property var client: null

  // "unsorted" or "all"
  property string currentView: "unsorted"
  property string searchQuery: ""
  property string saveCollection: root.client ? String(root.client.defaultCollection) : "-1"
  property string saveTags: ""
  property string prefillUrl: ""
  property string notice: ""

  readonly property bool hasClient: root.client !== null
  readonly property bool isSearching: root.searchQuery.trim().length > 0
  readonly property var shownItems: !root.hasClient ? [] : (root.isSearching ? root.client.searchResults : root.client.items)

  function tint(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function showNotice(msg) {
    root.notice = msg
    noticeTimer.restart()
  }

  function setView(view) {
    root.currentView = view
    if (root.client) root.client.loadRecent(view === "all" ? 0 : -1)
  }

  function launchDesktopWindow() {
    root.close()
    if (root.bar) root.bar.run("omarchy-shell shell summon " + root.pluginId + " \"{}\"")
  }

  function takeScreenshot() {
    // Get the popup out of the way so slurp can see the screen
    root.close()
    screenshotDelay.restart()
  }

  onOpenedChanged: {
    if (!root.opened || !root.client) return
    root.client.refresh()
    root.client.readClipboard(function(url) { root.prefillUrl = url })
  }

  Connections {
    target: root.client
    function onSaved(ok, message) { root.showNotice(message) }
    function onNotice(message) { root.showNotice(message) }
  }

  Timer {
    id: noticeTimer
    interval: 4000
    onTriggered: root.notice = ""
  }

  Timer {
    id: screenshotDelay
    interval: 350
    onTriggered: if (root.client) root.client.screenshot(root.saveCollection, root.saveTags, false)
  }

  Timer {
    id: searchDebounce
    interval: 300
    onTriggered: if (root.client) root.client.search(root.searchQuery)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    contentWidth: Style.space(440)
    contentHeight: Style.space(580)

    content: Component {
      Item {
        id: card
        anchors.fill: parent

        function submitSave() {
          if (!root.client) return
          var url = urlInput.text.trim() || root.prefillUrl
          root.client.save(url, root.saveCollection, root.saveTags, function(res) {
            if (res && res.ok) {
              urlInput.text = ""
              root.prefillUrl = ""
            }
          })
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.md
          spacing: Style.spacing.sm

          // --- Header ---
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xs

            Text {
              text: "󰖌"
              font.family: Style.font.family
              font.pixelSize: Style.font.title * 1.1
              color: Commons.Color.accent
            }

            Text {
              text: "Omaindrop"
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              color: Commons.Color.foreground
            }

            // Unsorted pill
            Rectangle {
              visible: root.hasClient && !root.client.tokenMissing
              Layout.leftMargin: Style.spacing.xs
              implicitWidth: pillText.implicitWidth + Style.space(12)
              implicitHeight: Style.space(20)
              radius: height / 2
              color: root.tint(Commons.Color.accent, 0.14)
              border.width: 1
              border.color: root.tint(Commons.Color.accent, 0.45)

              Text {
                id: pillText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: !root.hasClient ? "" : (root.client.stale ? "offline · " : "") + (root.client.counts.unsorted || 0) + " unsorted"
                font.family: Style.font.family
                font.pixelSize: Style.font.caption * 0.85
                color: Commons.Color.accent
              }
            }

            Item { Layout.fillWidth: true }

            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Refresh"
              onClicked: if (root.client) root.client.refreshAll()
            }

            PanelActionButton {
              iconText: "󰄀"
              tooltipText: "Screenshot a region to Raindrop"
              visible: root.hasClient && !root.client.tokenMissing
              onClicked: root.takeScreenshot()
            }

            PanelActionButton {
              iconText: "󰇚"
              tooltipText: root.hasClient && root.client.vaultCommand
                ? "Pull to vault (Make It Rain in " + root.client.vaultName + ")"
                : "Pull to vault: opens " + (root.hasClient ? root.client.vaultName : "your vault") + " for Make It Rain"
              visible: root.hasClient && root.client.vaultAvailable && !root.client.tokenMissing
              onClicked: if (root.client) root.client.pullToVault()
            }

            PanelActionButton {
              iconText: "↗"
              tooltipText: "Open as a desktop window (floats or tiles in Hyprland)"
              onClicked: root.launchDesktopWindow()
            }

            PanelActionButton {
              iconText: "󰅖"
              tooltipText: "Close popup"
              onClicked: root.close()
            }
          }

          // ==========================================
          // FIRST RUN: no token yet
          // ==========================================
          ColumnLayout {
            visible: root.hasClient && root.client.tokenMissing
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.sm

            Text {
              Layout.fillWidth: true
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: "Omaindrop needs a Raindrop test token. Create an app under Settings → Integrations, copy its test token, and paste it here. It's stored in ~/.config/raindrop/token (mode 600)."
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Commons.Color.muted
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xs

              TextField {
                id: tokenInput
                Layout.fillWidth: true
                password: true
                placeholderText: "Paste test token + Enter..."
                Keys.onReturnPressed: tokenSave.clicked()
              }

              PanelActionButton {
                id: tokenSave
                iconText: "󰌆"
                tooltipText: "Verify and save token"
                enabled: tokenInput.text.trim().length > 0
                onClicked: {
                  if (!root.client || !tokenInput.text.trim()) return
                  root.client.run(["set-token", tokenInput.text.trim()], function(res) {
                    if (res && res.ok) {
                      tokenInput.text = ""
                      root.client.tokenMissing = false
                      root.client.refreshAll()
                      root.showNotice("Token saved")
                    } else {
                      root.showNotice((res && res.error) || "Token rejected")
                    }
                  }, false)
                }
              }
            }

            PanelActionButton {
              iconText: "󰏌"
              tooltipText: "Open Raindrop integrations settings"
              onClicked: if (root.client) root.client.openLink("https://app.raindrop.io/settings/integrations")
            }

            Item { Layout.fillHeight: true }
          }

          // ==========================================
          // NORMAL VIEW
          // ==========================================
          ColumnLayout {
            visible: root.hasClient && !root.client.tokenMissing
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.sm

            // --- Save row ---
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xs

              TextField {
                id: urlInput
                Layout.fillWidth: true
                placeholderText: root.prefillUrl ? ("Enter saves " + root.prefillUrl) : "Paste a link + Enter to save..."
                Keys.onReturnPressed: card.submitSave()
              }

              PanelActionButton {
                iconText: "󰐕"
                tooltipText: root.prefillUrl && !urlInput.text.trim() ? "Save clipboard link" : "Save link"
                enabled: urlInput.text.trim().length > 0 || root.prefillUrl.length > 0
                onClicked: card.submitSave()
              }
            }

            // --- Collection + tags for the next save ---
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.xs

              Dropdown {
                id: collectionPicker
                Layout.preferredWidth: Style.space(170)
                showLabel: false
                options: root.hasClient ? root.client.collectionOptions() : []
                value: root.saveCollection
                onChanged: function(v) { root.saveCollection = v }
              }

              TextField {
                id: tagsInput
                Layout.fillWidth: true
                placeholderText: "tags, comma, separated"
                text: root.saveTags
                onTextChanged: root.saveTags = text
                Keys.onReturnPressed: card.submitSave()
              }
            }

            PanelSeparator { Layout.fillWidth: true }

            // --- Search ---
            TextField {
              id: searchInput
              Layout.fillWidth: true
              placeholderText: "Search all bookmarks (#tag works too)..."
              text: root.searchQuery
              onTextChanged: {
                root.searchQuery = text
                searchDebounce.restart()
              }
              Keys.onEscapePressed: searchInput.text = ""
            }

            // --- View chips ---
            RowLayout {
              Layout.fillWidth: true
              visible: !root.isSearching
              spacing: Style.space(4)

              Repeater {
                model: [
                  { id: "unsorted", label: "Unsorted (" + (root.hasClient ? root.client.counts.unsorted : 0) + ")" },
                  { id: "all", label: "All (" + (root.hasClient ? root.client.counts.all : 0) + ")" }
                ]

                delegate: Rectangle {
                  id: chip
                  required property var modelData
                  readonly property bool isSelected: root.currentView === modelData.id

                  implicitWidth: chipText.implicitWidth + Style.space(14)
                  implicitHeight: Style.space(22)
                  radius: Style.cornerRadius
                  color: isSelected ? Commons.Color.accent : (chipMouse.containsMouse ? root.tint(Commons.Color.foreground, 0.12) : root.tint(Commons.Color.foreground, 0.06))
                  border.width: 1
                  border.color: isSelected ? Commons.Color.accent : root.tint(Commons.Color.foreground, 0.15)

                  Text {
                    id: chipText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: chip.modelData.label
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption * 0.9
                    font.bold: chip.isSelected
                    color: chip.isSelected ? Commons.Color.background : Commons.Color.foreground
                  }

                  MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.setView(chip.modelData.id)
                  }
                }
              }

              Item { Layout.fillWidth: true }
            }

            // --- Notice / error line ---
            Text {
              Layout.fillWidth: true
              visible: text.length > 0
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: root.notice || (root.hasClient ? root.client.lastError : "")
              font.family: Style.font.family
              font.pixelSize: Style.font.caption * 0.9
              color: root.notice ? Commons.Color.accent : Commons.Color.urgent
            }

            // --- Items ---
            ListView {
              id: list
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              spacing: Style.space(2)
              model: root.shownItems
              boundsBehavior: Flickable.StopAtBounds
              ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

              delegate: Rectangle {
                id: row
                required property var modelData
                required property int index

                width: list.width
                implicitHeight: Style.space(46)
                radius: Style.cornerRadius
                color: rowHover.hovered ? root.tint(Commons.Color.foreground, 0.08) : "transparent"

                HoverHandler { id: rowHover }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.client) root.client.openLink(row.modelData.link)
                    root.close()
                  }
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(4)
                  spacing: Style.spacing.sm

                  // Letter tile
                  Rectangle {
                    Layout.preferredWidth: Style.space(28)
                    Layout.preferredHeight: Style.space(28)
                    radius: Style.cornerRadius
                    color: root.tint(Commons.Color.accent, 0.16)

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: (row.modelData.domain || row.modelData.title || "?").replace(/^www\./, "").charAt(0).toUpperCase()
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
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
                      text: row.modelData.title || row.modelData.link
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                      color: Commons.Color.foreground
                    }

                    Text {
                      Layout.fillWidth: true
                      elide: Text.ElideRight
                      textFormat: Text.PlainText
                      text: {
                        var bits = [row.modelData.domain || ""]
                        if (row.modelData.highlights > 0) bits.push(row.modelData.highlights + " highlights")
                        var tags = row.modelData.tags || []
                        if (tags.length) bits.push("#" + tags.join(" #"))
                        if (root.isSearching || root.currentView === "all") bits.push(root.client ? root.client.collectionTitle(row.modelData.collectionId) : "")
                        return bits.filter(function(b) { return b }).join("  ·  ")
                      }
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption * 0.85
                      color: Commons.Color.muted
                    }
                  }

                  PanelActionButton {
                    visible: rowHover.hovered
                    iconText: "󰆏"
                    tooltipText: "Copy link"
                    onClicked: if (root.client) root.client.copyLink(row.modelData.link)
                  }

                  PanelActionButton {
                    visible: rowHover.hovered
                    iconText: "󰩺"
                    tooltipText: "Move to Trash"
                    hoverColor: Commons.Color.urgent
                    onClicked: if (root.client) root.client.trash(row.modelData.id)
                  }
                }
              }

              // Empty state
              Text {
                anchors.centerIn: parent
                visible: list.count === 0
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignHCenter
                text: !root.hasClient ? "" : (root.isSearching
                  ? (root.client.searching ? "Searching..." : "Nothing matches")
                  : (root.client.loading ? "Loading..." : (root.currentView === "unsorted" ? "Unsorted is empty. Nice." : "No bookmarks yet")))
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Commons.Color.muted
              }
            }
          }
        }
      }
    }
  }
}
