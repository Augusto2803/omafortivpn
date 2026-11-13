import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// FortiGate SSL VPN indicator and panel.
//
// The icon stays in the bar, dimmed while disconnected; set `alwaysShow` to
// false to show it only while a tunnel is up. Clicking it opens a panel with
// the tunnel state, the profiles, and what can be done with them.
//
// Connecting is deliberately not done inside the panel. openfortivpn asks for
// a password and then a 2FA token that rotates every 30 seconds, and sudo for
// the account password, so it needs a terminal a human can type into — the
// CLI opens a floating one and closes it once the tunnel is up.
Panel {
  id: root
  moduleName: "io.github.augusto2803.omafortivpn"
  ipcTarget: "io.github.augusto2803.omafortivpn"
  manageIpc: false

  property var status: Model.DISCONNECTED

  readonly property bool connected: status.connected === true
  readonly property bool connecting: status.connecting === true
  readonly property bool up: connected || connecting
  readonly property var profiles: status.profiles
  readonly property bool alwaysShow: setting("alwaysShow", true) !== false

  // Countdown of fast re-reads owed after an action. A plain settle.restart()
  // would assign `running` imperatively and blow away its binding, so the
  // timer stays declarative and this is what it watches.
  property int settleTicks: 0
  readonly property int pollInterval: Math.max(2, setting("refreshIntervalSec", 5)) * 1000
  // Wall clock as of the last read, for "dropped 5 minutes ago".
  property real now: Date.now()

  // One keyboard cursor over everything that can be activated, top to bottom:
  // the hero's switch, each profile, then the two actions.
  property bool cursorActive: false
  property int cursorIndex: 0
  readonly property int newIndex: 1 + profiles.length
  readonly property int logIndex: newIndex + 1

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // The plugin is installed by cloning this repo, which puts no CLI on PATH.
  // Resolving the bundled script against this file's own location keeps the
  // widget working straight out of `omarchy plugin add`, with or without the
  // optional install.sh.
  readonly property string cli: {
    var url = String(Qt.resolvedUrl("bin/fortivpn"))
    return decodeURIComponent(url.indexOf("file://") === 0 ? url.substring(7) : url)
  }

  readonly property string stateText: connected ? strings.t("state.connected")
    : (connecting ? strings.t("state.connecting") : strings.t("state.disconnected"))

  readonly property string errorText: {
    if (up || status.error === "") return ""
    var when = Model.ago(status.errorAt, now)
    var ago = when.n === 0 ? strings.t(when.key)
      : strings.tn(when.key, when.n).arg(Commons.I18n.formatNumber(when.n))
    return strings.t("error." + status.errorKind).arg(status.errorProfile).arg(ago)
  }

  readonly property string switchHint: {
    if (up) return strings.t("hero.disconnect")
    if (status.defaultProfile === "") return strings.t("hero.noProfiles")
    return strings.t("hero.connect").arg(status.defaultProfile) + "\n" + strings.t("hero.connectHelp")
  }

  readonly property string barTooltip: {
    if (!connected) return stateText + "\n" + strings.t("bar.openPanel")
    var parts = [strings.t("bar.connectedTo").arg(status.profile)]
    if (status.ip) parts.push(status.ip)
    var elapsed = Model.formatUptime(status.uptime)
    if (elapsed) parts.push(elapsed)
    return parts.join(" · ") + "\n" + strings.t("bar.openPanel")
  }

  // An open panel keeps its icon: disconnecting from it must not pull the
  // anchor out from under it.
  visible: up || alwaysShow || opened
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // ------------------------------------------------------------ actions

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function cliCommand(args) {
    var command = Model.quote(root.cli)
    for (var i = 0; i < args.length; i++) command += " " + Model.quote(args[i])
    return command
  }

  function runCli(args, ticks) {
    if (root.bar) root.bar.run(cliCommand(args))
    settleTicks = Math.max(settleTicks, ticks)
  }

  // For what has to ask something in a terminal: the panel gets out of the way.
  function runInTerminal(args, ticks) {
    if (root.bar)
      root.bar.run("omarchy-launch-floating-terminal-with-presentation " + Model.quote(cliCommand(args)))
    settleTicks = Math.max(settleTicks, ticks)
    close()
  }

  // `up` opens its own floating terminal, so it is not wrapped in another.
  function connectTo(name) {
    if (root.up || name === "") return
    runCli(["up", name], 8)
    close()
  }

  function disconnect() {
    if (root.up) runCli(["down"], 5)
  }

  function toggleTunnel() {
    if (root.up) disconnect()
    else connectTo(status.defaultProfile)
  }

  function makeDefault(name) { runCli(["use", name], 2) }
  function pin(name) { runInTerminal(["trust", name], 20) }
  function edit(name) { runCli(["edit", name], 0); close() }
  function newProfile() { runInTerminal(["new"], 30) }

  function openLog() {
    runCli(status.errorProfile !== "" ? ["log", status.errorProfile] : ["log"], 0)
    close()
  }

  // A bar is built per monitor, and each one polls. Only the first instance
  // speaks up about a drop, so it is announced once rather than once a screen.
  function primaryInstance() {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : [root]
    return items.length === 0 || items[0] === root
  }

  function announceDrop(next) {
    if (!root.bar || !primaryInstance()) return
    var body = strings.t("notify.dropped").arg(next.errorProfile).arg(next.error)
    root.bar.run("notify-send -a FortiVPN -i network-vpn FortiVPN " + Model.quote(Model.escapeMarkup(body)))
  }

  // ------------------------------------------------------------ cursor

  function selectedProfile() {
    var i = cursorIndex - 1
    return i >= 0 && i < profiles.length ? profiles[i] : null
  }

  function moveCursor(dy) {
    cursorActive = true
    var first = profiles.length > 0 || up ? 0 : newIndex
    cursorIndex = Math.max(first, Math.min(logIndex, cursorIndex + dy))
  }

  function activateCursor() {
    if (cursorIndex === 0) toggleTunnel()
    else if (cursorIndex === newIndex) newProfile()
    else if (cursorIndex === logIndex) openLog()
    else {
      var p = selectedProfile()
      if (p) connectTo(p.name)
    }
  }

  function withSelected(fn) {
    var p = selectedProfile()
    if (p) fn(p.name)
  }

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = profiles.length > 0 || up ? 0 : newIndex
    now = Date.now()
    refresh()
    Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
  }

  // ------------------------------------------------------------ state

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
    function connect(): void { root.connectTo(root.status.defaultProfile) }
    function disconnect(): void { root.disconnect() }
    function toggleTunnel(): void { root.toggleTunnel() }
  }

  Process {
    id: statusProc
    command: [root.cli, "status", "--json"]
    running: false
    stdout: StdioCollector { id: statusOut; waitForEnd: true }
    onExited: function (exitCode) {
      var next = exitCode === 0 ? Model.parse(statusOut.text) : Model.DISCONNECTED
      if (Model.dropped(root.status, next)) root.announceDrop(next)
      root.now = Date.now()
      root.status = next
    }
  }

  Timer {
    interval: root.pollInterval
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // While the state is in flight — mid-handshake, or the seconds right after
  // an action — it changes on a scale of seconds, so it is worth re-reading
  // faster than the configured interval until it settles.
  Timer {
    interval: 1000
    repeat: true
    running: root.connecting || root.settleTicks > 0
    triggeredOnStart: true
    onTriggered: {
      if (root.settleTicks > 0) root.settleTicks--
      root.refresh()
    }
  }

  // ------------------------------------------------------------ bar icon

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\u{F0582}"
    active: root.connected
    dimmed: !root.connected
    tooltipText: root.opened ? "" : root.barTooltip
    onPressed: function (mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
      else if (mouseButton === Qt.MiddleButton) root.toggleTunnel()
      else if (mouseButton === Qt.RightButton) root.refresh()
    }
  }

  // A slow, even pulse while the handshake is under way. Skipped outright
  // when animations are off: a zero-length infinite loop would only spin.
  SequentialAnimation {
    running: root.connecting && Style.duration(700) > 0
    loops: Animation.Infinite
    onRunningChanged: if (!running) button.opacity = 1
    NumberAnimation { target: button; property: "opacity"; to: 0.35; duration: Style.duration(700) }
    NumberAnimation { target: button; property: "opacity"; to: 1; duration: Style.duration(700) }
  }

  // ------------------------------------------------------------ panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight, Style.space(520))

    content: PanelKeyCatcher {
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = t.toLowerCase()
        if (key === "r") root.refresh()
        else if (key === "n") root.newProfile()
        else if (key === "e") root.withSelected(root.edit)
        else if (key === "s") root.withSelected(root.makeDefault)
        else if (key === "p") root.withSelected(root.pin)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // The hero's trailingControl resolves `root` to PanelHero, not to
            // this Panel, so what the switch needs is exposed here.
            readonly property bool ringVisible: root.cursorActive && root.cursorIndex === 0
            readonly property bool switchShown: root.up || root.status.defaultProfile !== ""
            readonly property string hint: root.switchHint
            function focusHero() { root.cursorActive = true; root.cursorIndex = 0 }
            function flip() { root.toggleTunnel() }

            PanelHero {
              id: hero
              width: parent.width
              title: "FortiVPN"
              detail: root.up ? root.status.profile : ""
              meta: {
                // Connected, the switch and the profile pill already say so;
                // the line is better spent on the address and the uptime.
                if (!root.connected) return root.stateText
                var parts = []
                if (root.status.ip) parts.push(root.status.ip)
                var elapsed = Model.formatUptime(root.status.uptime)
                if (elapsed) parts.push(elapsed)
                return parts.length > 0 ? parts.join(" · ") : root.stateText
              }
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: root.connected ? 1.0 : 0.5
              iconComponent: Component {
                Text {
                  textFormat: Text.PlainText
                  text: "\u{F0582}"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.display
                }
              }

              trailingControl: Component {
                ToggleSwitch {
                  id: tunnelSwitch
                  visible: header.switchShown
                  checked: root.up
                  busy: root.connecting
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: header.flip()

                  PanelToolTip {
                    visible: tunnelSwitch.containsMouse
                    text: header.hint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.errorText !== ""
            width: parent.width
            text: root.errorText + "\n" + root.status.error
            color: root.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: strings.t("profiles.header")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              visible: root.profiles.length === 0
              width: parent.width
              text: strings.t("hero.noProfiles")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Repeater {
              model: root.profiles
              ProfileRow {
                required property var modelData
                required property int index
                width: column.width
                profile: modelData
                rowIndex: index + 1
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          Column {
            width: parent.width
            spacing: Style.space(6)

            ActionRow {
              width: column.width
              rowIndex: root.newIndex
              glyph: "\u{F0415}"
              title: strings.t("actions.new")
              help: strings.t("actions.newHelp")
              onActivated: root.newProfile()
            }

            ActionRow {
              width: column.width
              rowIndex: root.logIndex
              glyph: "\u{F02FC}"
              title: strings.t("actions.log")
              help: strings.t("actions.logHelp")
              onActivated: root.openLog()
            }
          }
        }
      }
    }
  }

  // ------------------------------------------------------------ rows

  component ProfileRow: CursorSurface {
    id: profileRow
    property var profile: null
    property int rowIndex: 0
    readonly property string name: profile ? profile.name : ""
    readonly property bool live: root.up && root.status.profile === name
    readonly property bool connectable: !root.up
    readonly property string caption: {
      if (!profile) return ""
      var parts = []
      if (profile.host) parts.push(profile.host)
      if (profile.isDefault) parts.push(strings.t("profiles.default"))
      if (!profile.pinned) parts.push(strings.t("profiles.unpinned"))
      return parts.join(" · ")
    }

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    current: live
    foreground: root.foreground
    implicitHeight: profileContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: profileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: profileRow.connectable ? Qt.PointingHandCursor : Qt.ArrowCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = profileRow.rowIndex }
      onClicked: if (profileRow.connectable) root.connectTo(profileRow.name)
    }

    PanelToolTip {
      visible: profileRow.connectable && profileMouse.containsMouse
      text: strings.t("hero.connect").arg(profileRow.name) + "\n" + strings.t("hero.connectHelp")
      fontFamily: root.fontFamily
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: profileRow.live ? "\u{F0582}" : "\u{F048B}"
        color: root.foreground
        opacity: profileRow.live ? 1.0 : 0.7
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: profileContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: profileRow.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: profileRow.live
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: profileRow.caption
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        visible: profileRow.profile && !profileRow.profile.isDefault
        iconText: "\u{F04D2}"
        tooltipText: strings.t("profiles.setDefault")
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.makeDefault(profileRow.name)
      }

      PanelActionButton {
        visible: profileRow.profile && !profileRow.profile.pinned
        iconText: "\u{F033E}"
        tooltipText: strings.t("profiles.pin")
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.pin(profileRow.name)
      }

      PanelActionButton {
        iconText: "\u{F03EB}"
        tooltipText: strings.t("profiles.edit")
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.edit(profileRow.name)
      }
    }
  }

  component ActionRow: CursorSurface {
    id: actionRow
    property int rowIndex: 0
    property string glyph: ""
    property string title: ""
    property string help: ""
    signal activated()

    hasCursor: root.cursorActive && root.cursorIndex === rowIndex
    foreground: root.foreground
    implicitHeight: actionContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.cursorIndex = actionRow.rowIndex }
      onClicked: actionRow.activated()
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: actionRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: actionContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: actionRow.help
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }
}
