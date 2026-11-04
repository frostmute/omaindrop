pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.frostmute.omaindrop"

  readonly property string pluginId: "io.github.frostmute.omaindrop"

  // Bar coordination properties
  readonly property bool opened: panelItem ? panelItem.opened === true : false
  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function togglePanel() { if (panelItem) panelItem.toggle() }

  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  property var panelItem: null

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    panelItem = target
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("client" in target) target.client = dropClient
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  DropClient {
    id: dropClient
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("PopupPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // omarchy-shell omaindrop <method>
  IpcHandler {
    target: "omaindrop"

    function refresh(): void { dropClient.refreshAll() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function saveClipboard(): void { dropClient.save("", "", "") }
    function save(url: string): void { dropClient.save(url, "", "") }
    function screenshot(): void { dropClient.screenshot("", "", false) }
    function pull(): void { if (dropClient.vaultAvailable) dropClient.pullToVault() }
    function openWindow(): void { root.summonDesktopWindow() }
  }

  function summonDesktopWindow() {
    if (root.bar) {
      root.bar.run("omarchy-shell shell toggle " + root.pluginId)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰖌"
    slotSize: Style.bar.statusSlot
    dimmed: dropClient.tokenMissing
    tooltipText: {
      if (dropClient.tokenMissing) return "Omaindrop · no Raindrop token yet\nClick to set one up"
      var un = dropClient.counts.unsorted || 0
      var all = dropClient.counts.all || 0
      var st = dropClient.busy ? "Saving..." : (dropClient.stale ? "Offline (cached)" : (dropClient.lastError ? dropClient.lastError : "Ready"))
      return "Omaindrop · " + un + " unsorted of " + all + " bookmarks\nStatus: " + st + "\nClick: Quick Popup · Middle-Click: Desktop Window · Right-Click: Refresh"
    }

    onPressed: function(b) {
      if (b === Qt.LeftButton) {
        root.togglePanel()
      } else if (b === Qt.MiddleButton) {
        root.summonDesktopWindow()
      } else if (b === Qt.RightButton) {
        dropClient.refreshAll()
      }
    }
  }

  // Unsorted inbox badge
  Rectangle {
    id: badge
    visible: !dropClient.tokenMissing && (dropClient.counts.unsorted || 0) > 0
    anchors.top: button.top
    anchors.right: button.right
    anchors.topMargin: Style.space(2)
    anchors.rightMargin: Style.space(2)
    z: 10

    readonly property int unsortedCount: dropClient.counts.unsorted || 0
    // Past this many unsorted drops the badge turns urgent; tune with "warnAt" in shell.json
    readonly property int warnAt: root.setting("warnAt", 50)

    implicitWidth: Math.max(Style.space(14), badgeText.implicitWidth + Style.space(6))
    implicitHeight: Style.space(14)
    radius: height / 2
    color: dropClient.stale ? Commons.Color.muted : (unsortedCount >= warnAt ? Commons.Color.urgent : Commons.Color.accent)
    border.width: 1
    border.color: root.bar ? root.bar.background : "transparent"

    Text {
      id: badgeText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: badge.unsortedCount > 99 ? "99+" : String(badge.unsortedCount)
      color: Commons.Color.background
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.caption * 0.8
      font.bold: true
    }
  }

  // Working dot while a save / upload is in flight
  Rectangle {
    id: busyDot
    visible: dropClient.busy
    anchors.bottom: button.bottom
    anchors.right: button.right
    anchors.bottomMargin: Style.space(3)
    anchors.rightMargin: Style.space(3)
    width: Style.space(6)
    height: Style.space(6)
    radius: width / 2
    color: Commons.Color.accent
    z: 11

    SequentialAnimation on opacity {
      running: dropClient.busy
      loops: Animation.Infinite
      NumberAnimation { from: 0.3; to: 1.0; duration: 400; easing.type: Easing.InOutQuad }
      NumberAnimation { from: 1.0; to: 0.3; duration: 400; easing.type: Easing.InOutQuad }
    }
  }
}
