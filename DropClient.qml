pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Reactive store for Omaindrop. Every call shells out to bin/omaindrop-backend,
// which talks to the Raindrop.io REST API and answers with one JSON object.
Item {
  id: root

  readonly property string backendBin: String(Qt.resolvedUrl("bin/omaindrop-backend")).replace(/^file:\/\//, "")

  // Counts from /user/stats
  property var counts: ({ "all": 0, "unsorted": 0, "trash": 0 })
  // Newest items in the collection being shown (Unsorted by default)
  property var items: []
  property int itemsTotal: 0
  property int currentCollection: -1
  // Search
  property string searchQuery: ""
  property var searchResults: []
  property int searchTotal: 0
  property bool searching: false
  // Collections + tags
  property var systemCollections: []
  property var collections: []
  property var tags: []
  // Make It Rain hand-off
  property bool vaultAvailable: false
  property string vaultName: ""
  property bool vaultCommand: false
  // From ~/.config/omaindrop/config.json "defaultCollection" (Unsorted unless set)
  property int defaultCollection: -1

  property bool loading: false
  property bool busy: false
  property bool stale: false
  property bool tokenMissing: false
  property string lastError: ""
  property string lastMessage: ""

  signal refreshed()
  signal saved(bool ok, string message)
  signal notice(string message)

  readonly property var allCollections: (systemCollections || []).concat(collections || [])

  function collectionTitle(id) {
    var all = root.allCollections
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === id) return all[i].title
    }
    return id === -1 ? "Unsorted" : (id === 0 ? "All bookmarks" : "Collection")
  }

  function collectionOptions() {
    var out = []
    var all = root.allCollections
    for (var i = 0; i < all.length; i++) {
      if (all[i].id === 0) continue // can't save into "All"
      var indent = ""
      for (var d = 0; d < (all[i].depth || 0); d++) indent += "  "
      out.push({ "value": String(all[i].id), "label": indent + all[i].title })
    }
    if (out.length === 0) out.push({ "value": "-1", "label": "Unsorted" })
    return out
  }

  function _handleError(data, fallback) {
    if (data && data.code === "no_token") root.tokenMissing = true
    root.lastError = (data && data.error) ? data.error : fallback
  }

  // ---------------------------------------------------------------- reads

  function refresh() {
    if (root.loading) return
    root.loading = true
    root.lastError = ""
    countProc.running = true
    root.loadRecent(root.currentCollection)
  }

  function refreshAll() {
    root.refresh()
    root.loadCollections()
    root.loadTags()
    root.checkVault()
  }

  Process {
    id: countProc
    command: [root.backendBin, "count"]
    stdout: StdioCollector { id: countOut; waitForEnd: true }
    onExited: function(exitCode) {
      root.loading = false
      try {
        var data = JSON.parse(countOut.text)
        if (data && data.ok) {
          root.counts = data.counts || root.counts
          root.stale = data.stale === true
          root.tokenMissing = false
          root.refreshed()
          return
        }
        root._handleError(data, "Couldn't reach Raindrop")
      } catch (e) {
        root.lastError = "Backend returned something odd (exit " + exitCode + ")"
      }
    }
  }

  function loadRecent(collection) {
    root.currentCollection = collection
    run(["recent", "--collection", String(collection), "--limit", "40"], function(data) {
      if (data && data.ok) {
        root.items = data.items || []
        root.itemsTotal = data.total || 0
        if (data.stale) root.stale = true
      } else {
        root._handleError(data, "Couldn't load bookmarks")
      }
    }, false)
  }

  function search(query) {
    root.searchQuery = query
    var q = (query || "").trim()
    if (!q) {
      root.searchResults = []
      root.searchTotal = 0
      return
    }
    root.searching = true
    run(["search", q, "--collection", "0", "--limit", "40"], function(data) {
      // Ignore answers to a query the user has already typed past
      if ((root.searchQuery || "").trim() !== q) return
      root.searching = false
      if (data && data.ok) {
        root.searchResults = data.items || []
        root.searchTotal = data.total || 0
      } else {
        root.searchResults = []
        root._handleError(data, "Search failed")
      }
    }, false)
  }

  function loadCollections() {
    run(["collections"], function(data) {
      if (data && data.ok) {
        root.systemCollections = data.system || []
        root.collections = data.collections || []
      }
    }, false)
  }

  function loadTags() {
    run(["tags", "--limit", "40"], function(data) {
      if (data && data.ok) root.tags = data.tags || []
    }, false)
  }

  function checkVault() {
    run(["vault"], function(data) {
      root.vaultAvailable = !!(data && data.ok && data.available)
      root.vaultName = (data && data.vault) ? data.vault.name : ""
      root.vaultCommand = !!(data && data.vault && data.vault.advancedUri)
    }, false)
  }

  function readClipboard(cb) {
    run(["clipboard"], function(data) {
      if (typeof cb === "function") cb((data && data.ok) ? (data.url || "") : "")
    }, false)
  }

  // ---------------------------------------------------------------- writes

  function save(url, collection, tags, cb) {
    var args = ["save"]
    if (url) args.push(url)
    if (collection !== undefined && collection !== null && collection !== "") args.push("--collection", String(collection))
    if (tags) args.push("--tags", tags)
    run(args, function(data) {
      var ok = !!(data && data.ok)
      var msg = ok ? (data.message || "Saved") : ((data && data.error) || "Save failed")
      root.lastMessage = msg
      root.saved(ok, msg)
      if (typeof cb === "function") cb(data)
    }, true)
  }

  function screenshot(collection, tags, full, cb) {
    var args = ["screenshot"]
    if (collection !== undefined && collection !== null && collection !== "") args.push("--collection", String(collection))
    if (tags) args.push("--tags", tags)
    if (full) args.push("--full")
    run(args, function(data) {
      var ok = !!(data && data.ok)
      var msg = ok ? (data.message || "Screenshot saved") : ((data && data.error) || "Screenshot failed")
      root.lastMessage = msg
      root.saved(ok, msg)
      if (typeof cb === "function") cb(data)
    }, true)
  }

  function move(id, collection, cb) {
    run(["move", String(id), String(collection)], cb, true)
  }

  function setTags(id, tags, cb) {
    run(["tag", String(id), tags], cb, true)
  }

  function trash(id, cb) {
    run(["delete", String(id)], cb, true)
  }

  function openLink(url) {
    run(url ? ["open", url] : ["open"], null, false)
  }

  function copyLink(url) {
    run(["copy", url], function(data) {
      if (data && data.ok) root.notice("Link copied")
    }, false)
  }

  function pullToVault() {
    run(["pull"], function(data) {
      root.notice((data && (data.message || data.error)) || "Couldn't reach Make It Rain")
    }, false)
  }

  // ---------------------------------------------------------------- plumbing

  // args: backend arguments; cb(result); mutates: refresh after success; input: optional stdin
  function run(args, cb, mutates, input) {
    var cmd = [root.backendBin]
    for (var i = 0; i < args.length; i++) cmd.push(String(args[i]))
    var proc = actionProcComponent.createObject(root, {
      commandArgs: cmd,
      input: input === undefined ? "" : input,
      callback: cb || null,
      mutates: mutates === true
    })
    if (mutates) root.busy = true
    proc.start()
  }

  Component {
    id: actionProcComponent
    Process {
      id: ap
      property var commandArgs: []
      property string input: ""
      property var callback: null
      property bool mutates: false

      command: commandArgs
      stdinEnabled: input.length > 0
      stdout: StdioCollector { id: apOut; waitForEnd: true }

      function start() { ap.running = true }

      onStarted: {
        if (ap.input.length > 0) ap.write(ap.input)
      }

      onExited: function(exitCode) {
        var res = { "ok": false, "error": "Backend exited with " + exitCode }
        try {
          if (apOut.text) res = JSON.parse(apOut.text)
        } catch (e) {}
        if (ap.mutates) root.busy = false
        if (typeof ap.callback === "function") ap.callback(res)
        if (ap.mutates && res.ok) {
          root.refresh()
          root.loadCollections()
        }
        ap.destroy()
      }
    }
  }

  // Raindrop allows 120 requests a minute; a two-minute poll is plenty for a badge.
  Timer {
    interval: 120000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    root.run(["status"], function(data) {
      if (data && data.ok) {
        root.defaultCollection = data.defaultCollection
        if (!data.token) root.tokenMissing = true
      }
    }, false)
    root.loadCollections()
    root.loadTags()
    root.checkVault()
  }
}
