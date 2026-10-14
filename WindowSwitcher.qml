import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property bool messageMode: false
  property string messageText: ""
  property int selectedIndex: 0
  // Set only when Alt-Tab is entered from the empty Scratchpad surface. An
  // Apple Music row selected from that overview must be placed in the
  // Scratchpad, because the surface itself is not a Hyprland workspace.
  property bool scratchpadTargetPending: false
  readonly property string pluginId: "io.github.leandro-3rne.window-switcher"
  readonly property string appleMusicPluginId: "io.github.leandro-3rne.apple-music"
  readonly property string iconDirectory: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + pluginId + "/icons/"
  readonly property string appIconDirectory: Quickshell.env("HOME") + "/.local/share/icons/hicolor/scalable/apps/"
  readonly property string launcherIconDirectory: Quickshell.env("HOME") + "/.local/share/icons/hicolor/256x256/apps/"
  readonly property string flatpakIconDirectory: Quickshell.env("HOME") + "/.local/share/flatpak/exports/share/icons/hicolor/128x128/apps/"

  // Match Omarchy's weather/audio/etc. popout surfaces. Selection colors
  // still come from the menu tokens used by keyboard-driven lists.
  property color background: Color.popups.background
  property color foreground: Color.popups.text
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int headerHeight: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)
  readonly property int cardGap: Style.spacing.md
  readonly property int maxColumnsForScreen: Math.max(1, Math.floor((panel.width - Style.gapsOut * 2 - contentMargin * 2 + cardGap) / (tileWidth + cardGap)))
  readonly property int columnCount: Math.max(1, Math.min(4, maxColumnsForScreen, Math.ceil(Math.sqrt(windowModel.count))))
  readonly property int rowCount: Math.max(1, Math.ceil(windowModel.count / columnCount))
  readonly property int tileWidth: Style.space(280)
  readonly property int tileHeight: Style.space(72)

  function workspaceForWindow(win) {
    var workspace = win ? win.workspace : null
    if (workspace) {
      var name = String(workspace.name || "")
      if (workspace.id > 0) return String(workspace.id)
      var specialName = name.replace(/^special:/, "")
      if (specialName.toLowerCase() === "scratchpad") return "Scratchpad"
      return specialName || "Special"
    }
    return "?"
  }

  function isAppleMusicWindow(win) {
    var id = String(win && win.appId || "").toLowerCase()
    return id.indexOf("music.apple.com") !== -1
  }

  function isHiddenWorkspace(workspace) {
    if (!workspace) return false
    // Hyprland assigns non-positive ids to special workspaces. Keep this
    // independent of the display name so renamed special workspaces still
    // follow the same activation path.
    var id = Number(workspace.id)
    var name = String(workspace.name || "")
    return (isFinite(id) && id <= 0) || name.indexOf("special:") === 0
  }

  function webIconForApp(appId) {
    var id = String(appId || "").toLowerCase()
    // Chromium app classes include the host before "__" and may encode the
    // URL path afterwards (for example onedrive.live.com__my-Default).
    var match = id.match(/^chrome-(.+)__.*-default$/)
    if (!match) return ""

    var host = match[1]
    // Reuse these installed launcher icons so the Apps menu and Window-Switcher
    // stay visually consistent.
    var launcherIcons = {
      "github.com": "github.png",
      "web.goodnotes.com": "goodnotes.png"
    }
    if (launcherIcons[host])
      return root.launcherIconDirectory + launcherIcons[host]

    var localIcons = {
      "discord.com": "discord.png",
      "mail.proton.me": "proton-mail",
      "calendar.proton.me": "proton-calendar",
      "drive.proton.me": "proton-drive",
      "pass.proton.me": "proton-pass",
      "onedrive.live.com": "onedrive.png",
      "www.icloud.com": "icloud.png",
      "music.apple.com": "apple-music.png",
      "www.netflix.com": "netflix.png",
      "youtube.com": "youtube.svg",
      "www.linkedin.com": "linkedin.png"
    }
    if (localIcons[host]) {
      var icon = localIcons[host]
      return icon.indexOf("proton-") === 0
        ? root.appIconDirectory + icon + ".svg"
        : root.iconDirectory + icon
    }

    // Never turn a client-controlled appId into a network request. Unknown
    // web apps fall back to their desktop entry icon below.
    return ""
  }

  function desktopIconForApp(appId) {
    var id = String(appId || "").toLowerCase()
    if (id === "zotero" || id === "org.zotero.zotero")
      return (Quickshell.env("HOME") || "") + "/.local/opt/zotero/icons/icon128.png"
    // Native Proton clients expose window app IDs that do not always match
    // their desktop-file IDs, so DesktopEntries.heuristicLookup() can miss
    // them. Keep explicit aliases beside the Chromium-host icon mapping.
    var localIcons = {
      "proton mail": "proton-mail",
      "proton-mail": "proton-mail",
      "proton pass": "proton-pass",
      "proton-pass": "proton-pass",
      "proton vpn": "proton-vpn-logo",
      "proton-vpn": "proton-vpn-logo",
      "protonvpn-app": "proton-vpn-logo",
      "proton.vpn.app.gtk": "proton-vpn-logo",
      "kitty": "kitty",
      "org.omarchy.agent": "kitty",
      "org.omarchy.terminal": "kitty",
      "foot": "foot",
      "alacritty": "Alacritty"
    }
    if (localIcons[id]) {
      if (id.indexOf("proton") === 0)
        return root.appIconDirectory + localIcons[id] + ".svg"
      return Quickshell.iconPath(localIcons[id])
    }

    var entry = DesktopEntries.heuristicLookup(appId)
    return entry
      ? Quickshell.iconPath(entry.icon)
      : Quickshell.iconPath("application-x-executable")
  }

  function craftFlatpakIconForApp(appId) {
    var id = String(appId || "").toLowerCase()
    var craftApps = {
      "ai.storyteller.artcraft-launcher": true,
      "ai.storyteller.photocraft": true,
      "ai.storyteller.filmcraft": true,
      "ai.storyteller.lightcraft": true,
      "ai.storyteller.pdfcraft": true,
      "ai.storyteller.wordcraft": true,
      "ai.storyteller.deckcraft": true,
      "ai.storyteller.gridcraft": true,
      "ai.storyteller.soundcraft": true
    }
    // Craft apps publish their icons with their Flatpak exports. Keep the
    // allowlist explicit so a client-controlled app ID cannot become a path.
    return craftApps[id] ? root.flatpakIconDirectory + id + ".png" : ""
  }

  function appNameForWindow(appId, title) {
    var id = String(appId || "")
    var lower = id.toLowerCase()
    var chromium = lower.match(/^chrome-(.+)__.*-default$/)
    if (chromium) {
      var host = chromium[1].replace(/^www\./, "")
      var known = {
        "discord.com": "Discord",
        "mail.proton.me": "Proton Mail",
        "calendar.proton.me": "Proton Calendar",
        "drive.proton.me": "Proton Drive",
        "pass.proton.me": "Proton Pass",
        "onedrive.live.com": "OneDrive",
        "www.icloud.com": "iCloud",
        "music.apple.com": "Apple Music",
        "web.goodnotes.com": "Goodnotes",
        "www.netflix.com": "Netflix",
        "youtube.com": "YouTube",
        "github.com": "GitHub",
        "www.linkedin.com": "LinkedIn",
        "mail.google.com": "Gmail",
        "calendar.google.com": "Google Calendar",
        "docs.google.com": "Google Docs",
        "sheets.google.com": "Google Sheets",
        "drive.google.com": "Google Drive",
        "teams.microsoft.com": "Microsoft Teams",
        "web.whatsapp.com": "WhatsApp"
      }
      return known[chromium[1]] || host.split(".")[0]
    }
    var nativeNames = {
      "ai.storyteller.artcraft-launcher": "ArtCraft Launcher",
      "ai.storyteller.photocraft": "PhotoCraft",
      "ai.storyteller.filmcraft": "FilmCraft",
      "ai.storyteller.lightcraft": "LightCraft",
      "ai.storyteller.pdfcraft": "PdfCraft",
      "ai.storyteller.wordcraft": "WordCraft",
      "ai.storyteller.deckcraft": "DeckCraft",
      "ai.storyteller.gridcraft": "GridCraft",
      "ai.storyteller.soundcraft": "SoundCraft",
      "org.omarchy.agent": "OpenCode",
      "zotero": "Zotero",
      "org.zotero.zotero": "Zotero",
      "proton mail": "Proton Mail",
      "proton-mail": "Proton Mail",
      "proton pass": "Proton Pass",
      "proton-pass": "Proton Pass",
      "proton vpn": "Proton VPN",
      "proton-vpn": "Proton VPN",
      "protonvpn-app": "Proton VPN",
      "proton.vpn.app.gtk": "Proton VPN"
    }
    if (nativeNames[lower]) return nativeNames[lower]
    var domainNames = { "wheelmap.org": "Wheelmap", "www.wheelmap.org": "Wheelmap" }
    if (domainNames[lower]) return domainNames[lower]
    var entry = DesktopEntries.heuristicLookup(id)
    return entry && entry.name ? String(entry.name) : (id || "Unknown application")
  }

  function displayTitleForWindow(appId, title) {
    var id = String(appId || "").toLowerCase()
    var value = String(title || "")
    if (id === "zotero" || id === "org.zotero.zotero") return "Zotero"
    if (id.indexOf("music.apple.com") !== -1) return "Apple Music"
    if (id.match(/^chrome-.+__.*-default$/))
      value = value.replace(/\s+[—–-]\s+Web App$/i, "")
    if (id === "chatgpt") {
      var cleaned = value.replace(/\s+[—–-]\s+ChatGPT$/i, "")
      return cleaned && cleaned.toLowerCase() !== "chatgpt" ? cleaned : "ChatGPT"
    }
    return value || "Untitled window"
  }

  function rebuildModel() {
    windowModel.clear()
    var windows = Hyprland.toplevels.values
    var rows = []
    for (var i = 0; i < windows.length; i++) {
      var hyprWindow = windows[i]
      if (!hyprWindow || !hyprWindow.wayland) continue
      var win = hyprWindow.wayland
      var workspace = hyprWindow.workspace
      var workspaceId = workspace ? Number(workspace.id) : 0
      var appleMusic = root.isAppleMusicWindow(win)
      var hiddenWorkspace = root.isHiddenWorkspace(workspace)
      rows.push({
        windowObject: win,
        address: String(hyprWindow.address || win.address || ""),
        appleMusic: appleMusic,
        hiddenWorkspace: hiddenWorkspace,
        title: root.displayTitleForWindow(win.appId, hyprWindow.title || win.title || win.appId),
        appId: String(win.appId || ""),
        appName: root.appNameForWindow(win.appId, hyprWindow.title || win.title),
        workspace: workspaceForWindow(hyprWindow),
        workspaceSort: workspaceId > 0 ? workspaceId : 100000,
        originalIndex: i
      })
    }

    rows.sort(function(left, right) {
      if (left.workspaceSort !== right.workspaceSort)
        return left.workspaceSort - right.workspaceSort
      return left.originalIndex - right.originalIndex
    })

    for (var j = 0; j < rows.length; j++) {
      windowModel.append(rows[j])
    }
    if (windowModel.count === 0) selectedIndex = 0
    else selectedIndex = Math.max(0, Math.min(selectedIndex, windowModel.count - 1))
  }

  // Toplevel titles change without changing the Hyprland toplevel list. Keep
  // the overview's copied model rows in sync so terminal progress spinners and
  // other live titles visibly advance while Alt-Tab is held.
  function refreshWindowTitles() {
    if (!root.opened || root.messageMode) return
    var toplevels = Hyprland.toplevels.values
    for (var i = 0; i < windowModel.count; i++) {
      var row = windowModel.get(i)
      var win = row.windowObject
      if (!win) continue
      var sourceTitle = win.title || row.title || row.appId
      for (var j = 0; j < toplevels.length; j++) {
        if (toplevels[j] && toplevels[j].wayland === win) {
          sourceTitle = toplevels[j].title || sourceTitle
          break
        }
      }
      var title = root.displayTitleForWindow(row.appId, sourceTitle)
      if (title !== row.title) windowModel.setProperty(i, "title", title)
    }
  }

  function open(payloadJson) {
    scratchpadTargetPending = false
    var reverse = false
    try { reverse = Boolean(JSON.parse(payloadJson || "{}").reverse) } catch (e) {}
    messageMode = false
    messageText = ""
    rebuildModel()
    var activeIndex = -1
    for (var i = 0; i < windowModel.count; i++) {
      if (windowModel.get(i).windowObject === ToplevelManager.activeToplevel) {
        activeIndex = i
        break
      }
    }
    if (windowModel.count > 0) {
      var direction = reverse ? -1 : 1
      selectedIndex = activeIndex >= 0
        ? (activeIndex + direction + windowModel.count) % windowModel.count
        : (reverse ? windowModel.count - 1 : 0)
    }
    opened = true
    Qt.callLater(function() {
      keyCatcher.forceActiveFocus()
      if (windowModel.count > 0) grid.positionViewAtIndex(selectedIndex, GridView.Contain)
    })
  }

  function close() {
    opened = false
    scratchpadTargetPending = false
  }

  function dismiss() {
    opened = false
    scratchpadTargetPending = false
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || root.pluginId)
  }

  function toggle(payloadJson) {
    if (opened) dismiss()
    else open(payloadJson || "{}")
  }

  function showScratchpadEmpty() {
    scratchpadTargetPending = false
    if (opened && messageMode) {
      dismiss()
      return "ok"
    }
    messageMode = true
    messageText = "Scratchpad is empty"
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    return "ok"
  }

  // The Apple Music controller needs to distinguish the persistent empty
  // scratchpad hint from a normal Alt-Tab overlay. Keep that state available
  // over the shell IPC boundary without exposing any window data.
  function isScratchpadEmpty() {
    return opened && messageMode ? "true" : "false"
  }

  function dismissScratchpadEmpty() {
    if (opened && messageMode) dismiss()
    return "ok"
  }

  function moveWindowToScratchpad(win, rawAddress) {
    var address = String(rawAddress || (win && win.address) || "")
    if (address.indexOf("0x") !== 0) address = "0x" + address
    if (!address.match(/^0x[0-9a-f]+$/i)) return false

    var script = 'local w = hl.get_window("address:' + address + '"); '
      + 'if w then '
      + 'if w.group then hl.dispatch(hl.dsp.window.move({ window = w, out_of_group = true })) end; '
      + 'hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:scratchpad", follow = true })); '
      + 'hl.exec_scheduled_prop_refresh_immediately(); '
      + 'hl.dispatch(hl.dsp.focus({ window = w })) '
      + 'end'
    Quickshell.execDetached(["hyprctl", "eval", script])
    return true
  }

  function activateWindowOutsideScratchpad(win, rawAddress) {
    var address = String(rawAddress || (win && win.address) || "")
    if (address.indexOf("0x") !== 0) address = "0x" + address
    var workspace = win && win.workspace ? String(win.workspace.name || "") : ""
    if (workspace === "special:scratchpad" || !address.match(/^0x[0-9a-f]+$/i)) {
      if (win) win.activate()
      return
    }

    // Close the visible Scratchpad before focusing a window from another
    // workspace. Doing both dispatches in one Hyprland eval avoids a race in
    // which the target focus lands while the special workspace is still up.
    var script = 'local w = hl.get_window("address:' + address + '"); '
      + 'local special = hl.get_active_special_workspace(); '
      + 'if special and special.name == "special:scratchpad" then '
      + 'hl.dispatch(hl.dsp.workspace.toggle_special("scratchpad")) end; '
      + 'if w then hl.dispatch(hl.dsp.focus({ window = w })) end'
    Quickshell.execDetached(["hyprctl", "eval", script])
  }

  function moveOpenedWindowToScratchpad(rawAddress) {
    if (!opened || !messageMode) return

    var address = String(rawAddress || "")
    if (address.indexOf("0x") !== 0) address = "0x" + address
    if (!address.match(/^0x[0-9a-f]+$/i)) return

    dismiss()
    var script = 'local w = hl.get_window("address:' + address + '"); '
      + 'if w then '
      + 'hl.dispatch(hl.dsp.window.move({ window = w, out_of_group = true })); '
      + 'hl.dispatch(hl.dsp.window.move({ window = w, workspace = "special:scratchpad", follow = true })) '
      + 'end'
    Quickshell.execDetached(["hyprctl", "eval", script])
  }

  function cycle(direction) {
    var reverse = String(direction || "next") === "previous"
    if (!opened) {
      scratchpadTargetPending = false
      open(JSON.stringify({ reverse: reverse }))
    } else if (messageMode) {
      open(JSON.stringify({ reverse: reverse }))
      // open() resets the regular overview state; retain this one bit of
      // context for the activation that follows from the empty hint.
      scratchpadTargetPending = true
    }
    else if (windowModel.count === 0) dismiss()
    else select(reverse ? -1 : 1)
    return "ok"
  }

  function select(delta) {
    if (windowModel.count === 0) return
    selectedIndex = (selectedIndex + delta + windowModel.count) % windowModel.count
    grid.positionViewAtIndex(selectedIndex, GridView.Contain)
  }

  function activate(index) {
    if (messageMode) return
    if (index < 0 || index >= windowModel.count) {
      dismiss()
      return
    }
    var row = windowModel.get(index)
    var win = row.windowObject
    var targetScratchpad = root.scratchpadTargetPending
    root.scratchpadTargetPending = false
    dismiss()
    if (row.appleMusic === true && row.hiddenWorkspace === true) {
      if (targetScratchpad && root.moveWindowToScratchpad(win, row.address)) return
      // Always reveal and focus Apple Music. Unlike the bar's toggle action,
      // this also does the right thing for a window on a visible scratchpad:
      // selecting it must not hide that scratchpad.
      var service = root.shell && typeof root.shell.serviceFor === "function"
        ? root.shell.serviceFor(root.appleMusicPluginId) : null
      if (service && typeof service.focusWindow === "function") service.focusWindow()
      else Quickshell.execDetached(["omarchy-shell", root.appleMusicPluginId, "show"])
      return
    }
    if (win) root.activateWindowOutsideScratchpad(win, row.address)
  }

  ListModel { id: windowModel }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { if (root.opened) root.rebuildModel() }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened || !root.messageMode) return

      var name = String(event.name || "")
      if (name === "openwindow") {
        var fields = event.parse(4)
        root.moveOpenedWindowToScratchpad(fields.length > 0 ? fields[0] : "")
      } else if (name === "workspace" || name === "activespecial") {
        root.dismiss()
      }
    }
  }

  Timer {
    id: titleRefreshTimer
    interval: 100
    repeat: true
    running: root.opened && !root.messageMode
    onTriggered: root.refreshWindowTitles()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Rectangle { anchors.fill: parent; color: root.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: surface
      anchors.centerIn: parent
      width: root.messageMode
        ? Math.min(panel.width - Style.gapsOut * 2, Style.space(280) + root.contentMargin * 2 + borderLeft + borderRight)
        : Math.min(panel.width - Style.gapsOut * 2, root.columnCount * root.tileWidth + (root.columnCount - 1) * root.cardGap + root.contentMargin * 2 + borderLeft + borderRight)
      height: root.messageMode
        ? Style.space(64) + root.contentMargin * 2 + borderTop + borderBottom
        : Math.min(panel.height - Style.gapsOut * 2, root.rowCount * root.tileHeight + (root.rowCount - 1) * root.cardGap + root.headerHeight + root.cardGap + root.contentMargin * 2 + borderTop + borderBottom)
      radius: Style.cornerRadius
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onReleased: function(event) {
          if (!root.messageMode && (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr)) {
            root.activate(root.selectedIndex)
            event.accepted = true
          }
        }
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
          } else if (root.messageMode) {
            return
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activate(root.selectedIndex)
          } else if (event.key === Qt.Key_Tab) {
            root.select((event.modifiers & Qt.ShiftModifier) ? -1 : 1)
          } else if (event.key === Qt.Key_Left) {
            root.select(-1)
          } else if (event.key === Qt.Key_Right) {
            root.select(1)
          } else if (event.key === Qt.Key_Up) {
            root.select(-root.columnCount)
          } else if (event.key === Qt.Key_Down) {
            root.select(root.columnCount)
          } else {
            return
          }
          event.accepted = true
        }

        Column {
          visible: !root.messageMode
          anchors.fill: parent
          anchors.topMargin: surface.contentTopInset
          anchors.rightMargin: surface.contentRightInset
          anchors.bottomMargin: surface.contentBottomInset
          anchors.leftMargin: surface.contentLeftInset
          spacing: Style.spacing.md

          Item {
            width: parent.width
            height: root.headerHeight

            Text {
              anchors.left: parent.left
              anchors.right: countLabel.left
              anchors.rightMargin: Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              text: "Select window…"
              color: root.foreground
              opacity: 0.58
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.heading
              elide: Text.ElideRight
            }

            Text {
              id: countLabel
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: windowModel.count + " windows"
              color: root.foreground
              opacity: 0.45
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
            }
          }

          GridView {
            id: grid
            // GridView counts a trailing cell gap when deciding how many
            // columns fit. The extra virtual gap keeps the last delegate in
            // the intended row; the delegate itself still ends at the real
            // content edge.
            width: parent.width + root.cardGap
            height: parent.height - root.headerHeight - parent.spacing + root.cardGap
            model: windowModel
            cellWidth: root.tileWidth + root.cardGap
            cellHeight: root.tileHeight + root.cardGap
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
              id: tile
              required property int index
              required property var windowObject
              required property string address
              required property string title
              required property string appId
              required property string appName
              required property string workspace
              width: root.tileWidth
              height: root.tileHeight
              radius: Style.cornerRadius
              color: index === root.selectedIndex ? root.selectedBackground : "transparent"

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.spacing.md
                spacing: Style.spacing.md

                Item {
                  Layout.preferredWidth: Style.space(36)
                  Layout.preferredHeight: Style.space(36)

                  Image {
                    anchors.centerIn: parent
                    width: Style.font.iconLarge
                    height: Style.font.iconLarge
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    smooth: true
                    source: root.desktopIconForApp(tile.appId)
                    visible: webIcon.status !== Image.Ready && craftIcon.status !== Image.Ready
                  }

                  Image {
                    id: webIcon
                    anchors.centerIn: parent
                    width: Style.font.iconLarge
                    height: Style.font.iconLarge
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    asynchronous: true
                    cache: true
                    smooth: true
                    source: root.webIconForApp(tile.appId)
                    visible: status === Image.Ready
                  }

                  Image {
                    id: craftIcon
                    anchors.centerIn: parent
                    width: Style.font.iconLarge
                    height: Style.font.iconLarge
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: width * Screen.devicePixelRatio
                    sourceSize.height: height * Screen.devicePixelRatio
                    asynchronous: true
                    cache: true
                    smooth: true
                    source: root.craftFlatpakIconForApp(tile.appId)
                    visible: status === Image.Ready
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.spacing.xs

                  Text {
                    Layout.fillWidth: true
                    text: tile.title
                    color: tile.index === root.selectedIndex ? root.selectedText : root.foreground
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.title
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    wrapMode: Text.NoWrap
                  }

                  Text {
                    Layout.fillWidth: true
                    text: tile.appName + "  ·  Workspace " + tile.workspace
                    visible: text !== ""
                    color: tile.index === root.selectedIndex ? root.selectedText : root.foreground
                    opacity: 0.65
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: root.selectedIndex = tile.index
                onClicked: root.activate(tile.index)
              }
            }

            Text {
              anchors.centerIn: parent
              visible: windowModel.count === 0
              text: "No open windows"
              color: root.foreground
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.messageMode
          text: root.messageText
          color: root.foreground
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
        }
      }
    }
  }
}
