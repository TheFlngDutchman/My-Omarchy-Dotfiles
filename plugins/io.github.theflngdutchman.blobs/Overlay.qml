import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "Game.js" as Game

// Fullscreen overlay hosting the Blobs arena. The shell calls open(payload) /
// close() through its loader; Esc dismisses via the scoped shell facade.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null

  readonly property string pluginId: (root.manifest && root.manifest.id) || "io.github.theflngdutchman.blobs"

  property bool opened: false
  property bool paused: false
  property bool gameOver: false
  property bool newBest: false
  property int bots: 10
  property int highScore: 0
  property int score: 0
  property int rank: 0
  property int cellCount: 1
  property string killedBy: ""
  property var leaderboard: []
  property var game: null
  property real lastTick: 0

  // Camera in world units; smoothed toward the player's centroid.
  property real camX: Game.WORLD / 2
  property real camY: Game.WORLD / 2
  property real zoom: 1
  property bool mouseSeen: false
  property real mouseX: 0
  property real mouseY: 0

  // Menu surface tokens, like the built-in overlays.
  readonly property color background: Color.menu.background
  readonly property color foreground: Color.menu.text
  readonly property color border: Color.menu.border
  readonly property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  readonly property color scrim: Color.menu.scrim
  readonly property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  readonly property string fontFamily: Style.font.family
  readonly property int contentMargin: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(1600), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(1000), panel.height - Style.gapsOut * 2)

  // Every colour is derived from the theme palette: the player is the accent,
  // bots rotate the accent hue with a saturation floor so they stay
  // distinguishable on grey themes, food is a paler ring of the same hues.
  readonly property var botColors: root.hueRing(Color.accent, 12, 0.55, 0.55, 1)
  readonly property var foodColors: root.hueRing(Color.accent, 12, 0.5, 0.6, 0.8)

  function hueRing(base, n, minSat, light, alpha) {
    var out = []
    var h = base.hslHue < 0 ? 0 : base.hslHue
    var s = Math.max(minSat, base.hslSaturation)
    // Spread the ring over the 80% of the wheel farthest from the accent so no
    // bot can be mistaken for the player.
    for (var i = 0; i < n; i++) {
      out.push(String(Qt.hsla((h + 0.1 + i * (0.8 / Math.max(1, n - 1))) % 1, s, light, alpha)))
    }
    return out
  }

  // --------------------------------------------------------------- lifecycle

  function open(payloadJson) {
    root.applyPayload(payloadJson)
    root.highScore = Math.max(root.highScore, root.storedHighScore())
    root.opened = true
    root.startGame()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.paused = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function applyPayload(payloadJson) {
    if (!payloadJson) return
    try {
      var p = JSON.parse(payloadJson)
      if (p && isFinite(Number(p.bots))) root.bots = Math.max(2, Math.min(24, Math.round(Number(p.bots))))
    } catch (e) { /* payload is optional */ }
  }

  // Our own layout entry inside the detached config snapshot the facade hands us.
  function ownEntry() {
    var cfg = root.shell ? root.shell.barConfig : null
    if (!cfg || !cfg.layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var arr = cfg.layout[sections[s]] || []
      for (var i = 0; i < arr.length; i++) {
        if (arr[i] && String(arr[i].id) === root.pluginId) return arr[i]
      }
    }
    return null
  }

  function storedHighScore() {
    var entry = root.ownEntry()
    if (!entry) return 0
    var n = Number(entry.highScore)
    if (isFinite(Number(entry.bots))) root.bots = Math.max(2, Math.min(24, Math.round(Number(entry.bots))))
    return isFinite(n) && n > 0 ? Math.round(n) : 0
  }

  function persistHighScore() {
    if (!root.shell || typeof root.shell.updateEntryInline !== "function") return
    var entry = root.ownEntry()
    var next = {}
    if (entry) for (var k in entry) if (k !== "id") next[k] = entry[k]
    next.highScore = root.highScore
    root.shell.updateEntryInline(root.pluginId, next)
  }

  // -------------------------------------------------------------------- game

  function startGame() {
    root.game = Game.create({
      bots: root.bots,
      colors: root.botColors,
      playerColor: String(Color.accent)
    })
    root.gameOver = false
    root.newBest = false
    root.paused = false
    root.killedBy = ""
    root.score = 0
    root.mouseSeen = false
    var c = Game.centroid(root.game.player)
    root.camX = c.x; root.camY = c.y; root.zoom = 1
    root.lastTick = Date.now()
    root.refreshHud()
    canvas.requestPaint()
  }

  function tick() {
    if (!root.game || root.paused || root.gameOver) return
    var now = Date.now()
    var dt = Math.min(0.05, Math.max(0.001, (now - root.lastTick) / 1000))
    root.lastTick = now

    if (root.mouseSeen) {
      var wx = root.camX + (root.mouseX - canvas.width / 2) / root.zoom
      var wy = root.camY + (root.mouseY - canvas.height / 2) / root.zoom
      Game.setPlayerTarget(root.game, wx, wy)
    }

    Game.tick(root.game, dt)

    var c = Game.centroid(root.game.player)
    if (c) {
      var k = 1 - Math.pow(0.001, dt)
      root.camX += (c.x - root.camX) * k
      root.camY += (c.y - root.camY) * k
      var target = Math.pow(60 / Game.radius(c.mass), 0.4) * (canvas.height / 900)
      target = Math.max(0.28, Math.min(1.15, target))
      root.zoom += (target - root.zoom) * (1 - Math.pow(0.02, dt))
    }

    if (root.game.over) root.finishGame()
    canvas.requestPaint()
  }

  function finishGame() {
    root.gameOver = true
    root.killedBy = root.game.killedBy
    root.score = root.game.score
    if (root.score > root.highScore) {
      root.highScore = root.score
      root.newBest = true
      root.persistHighScore()
    }
    root.refreshHud()
  }

  function refreshHud() {
    if (!root.game) return
    root.leaderboard = Game.leaderboard(root.game, 6)
    root.rank = Game.playerRank(root.game)
    root.score = root.game.score
    root.cellCount = root.game.player.cells.length
  }

  Timer {
    running: root.opened && !root.paused && !root.gameOver
    interval: 16
    repeat: true
    onTriggered: root.tick()
  }

  Timer {
    running: root.opened && !root.paused && !root.gameOver
    interval: 300
    repeat: true
    onTriggered: root.refreshHud()
  }

  // ------------------------------------------------------------------ window

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-blobs"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: 0
      clip: true

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Space) {
            if (root.game && !root.paused && !root.gameOver) Game.splitPlayer(root.game)
            event.accepted = true
          } else if (event.key === Qt.Key_W) {
            if (root.game && !root.paused && !root.gameOver) Game.ejectPlayer(root.game)
            event.accepted = true
          } else if (event.key === Qt.Key_P) {
            if (!root.gameOver) { root.paused = !root.paused; root.lastTick = Date.now() }
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.gameOver) root.startGame()
            else if (root.paused) { root.paused = false; root.lastTick = Date.now() }
            event.accepted = true
          } else if (event.key === Qt.Key_R) {
            root.startGame()
            event.accepted = true
          }
        }

        Canvas {
          id: canvas
          anchors.fill: parent
          anchors.topMargin: card.contentTopInset
          anchors.rightMargin: card.contentRightInset
          anchors.bottomMargin: card.contentBottomInset
          anchors.leftMargin: card.contentLeftInset
          renderStrategy: Canvas.Cooperative

          onPaint: {
            if (!root.game) return
            var ctx = getContext("2d")
            Game.render(ctx, root.game, {
              width: canvas.width,
              height: canvas.height,
              camX: root.camX,
              camY: root.camY,
              zoom: root.zoom,
              fontFamily: root.fontFamily,
              background: String(root.background),
              grid: String(Util.alpha(root.foreground, 0.07)),
              border: String(root.border),
              rim: String(Util.alpha(root.background, 0.45)),
              text: String(root.background),
              virus: String(Util.alpha(Color.urgent, 0.85)),
              virusRim: String(Util.alpha(root.background, 0.5)),
              foodColors: root.foodColors
            })
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.CrossCursor
            onPositionChanged: function(mouse) {
              root.mouseSeen = true
              root.mouseX = mouse.x
              root.mouseY = mouse.y
            }
            onClicked: function(mouse) {
              // Swallow clicks so they do not reach the scrim dismisser.
              root.mouseSeen = true
              root.mouseX = mouse.x
              root.mouseY = mouse.y
            }
          }
        }

        // ---------------------------------------------------------- HUD

        Column {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.margins: root.contentMargin
          spacing: Style.spacing.xs

          Text {
            textFormat: Text.PlainText
            text: "Mass " + root.score
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            textFormat: Text.PlainText
            text: "Best " + root.highScore + (root.rank > 0 ? "   ·   #" + root.rank : "") + (root.cellCount > 1 ? "   ·   " + root.cellCount + " cells" : "")
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Column {
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: root.contentMargin
          spacing: Style.spacing.xs

          Text {
            textFormat: Text.PlainText
            text: "Leaderboard"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
          }
          Repeater {
            model: root.leaderboard
            delegate: Row {
              required property var modelData
              required property int index
              spacing: Style.spacing.sm
              anchors.right: parent.right

              Text {
                textFormat: Text.PlainText
                text: (index + 1) + ". " + modelData.name
                color: modelData.isPlayer ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: modelData.isPlayer
              }
              Rectangle {
                width: Style.space(10); height: Style.space(10)
                radius: width / 2
                color: modelData.color
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: String(modelData.mass)
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                horizontalAlignment: Text.AlignRight
                width: Style.space(44)
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: root.contentMargin
          text: "Move: mouse   ·   Space: split   ·   W: eject mass   ·   P: pause   ·   R: restart   ·   Esc: quit"
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        // ----------------------------------------------- pause / game over

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(root.background, 0.82)
          visible: root.paused || root.gameOver

          Column {
            anchors.centerIn: parent
            spacing: Style.spacing.md

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.gameOver ? "Eaten" + (root.killedBy ? " by " + root.killedBy : "") : "Paused"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.displayLarge
              font.bold: true
            }
            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              visible: root.gameOver
              text: "Peak mass " + root.score + (root.newBest ? "   ·   new best!" : "   ·   best " + root.highScore)
              color: root.newBest ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
            }
            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.gameOver ? "Enter: play again   ·   Esc: close" : "Enter or P: resume   ·   R: restart   ·   Esc: close"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }
}
