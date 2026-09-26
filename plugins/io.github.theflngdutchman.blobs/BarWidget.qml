import QtQuick
import qs.Ui

// Bar button for Blobs. Its only job is to ask the shell to toggle this
// plugin's own overlay through the scoped shell facade — no processes,
// no IPC round-trip.
BarWidget {
  id: root
  moduleName: "io.github.theflngdutchman.blobs"

  readonly property int highScore: {
    var n = Number(setting("highScore", 0))
    return isFinite(n) && n > 0 ? Math.round(n) : 0
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function toggleGame() {
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.toggle !== "function") {
      console.warn("blobs: shell facade unavailable, cannot toggle overlay")
      return
    }
    root.bar.shell.toggle(root.moduleName, "{}")
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰊴"
    tooltipText: root.highScore > 0 ? "Blobs · best " + root.highScore : "Blobs"
    onPressed: function(mouseButton) { root.toggleGame() }
  }
}
