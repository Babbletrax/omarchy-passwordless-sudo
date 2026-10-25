import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "passwordless-sudo-toggle"

  // The helper ships next to this file, wherever the plugin is installed.
  readonly property string helperPath:
    decodeURIComponent(Qt.resolvedUrl("toggle-passwordless-sudo").toString().replace(/^file:\/\//, ""))
  property bool passwordless: false
  property bool busy: false
  property int requestedState: -1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!busy && !statusProcess.running) statusProcess.running = true
  }

  function toggle() {
    if (busy || toggleProcess.running) return
    requestedState = passwordless ? 0 : 1
    busy = true
    toggleProcess.running = true
  }

  function notify(summary, body, urgency) {
    notificationProcess.command = [
      "/usr/bin/notify-send",
      "--app-name=Passwordless sudo",
      "--urgency=" + urgency,
      summary,
      body
    ]
    notificationProcess.running = true
  }

  Process {
    id: statusProcess
    command: [root.helperPath, "--status"]
    onExited: function(exitCode) {
      root.passwordless = exitCode === 0
    }
  }

  Process {
    id: toggleProcess
    command: [root.helperPath, "--toggle"]
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.passwordless = root.requestedState === 1
        root.notify(
          root.passwordless ? "Passwordless sudo enabled" : "Passwordless sudo disabled",
          root.passwordless
            ? "sudo will not ask for a password until you turn this toggle off."
            : "sudo password authentication has been restored.",
          root.passwordless ? "critical" : "normal"
        )
      } else {
        root.notify(
          "Passwordless sudo was not changed",
          "Authentication was cancelled or the sudoers safety check failed.",
          "critical"
        )
      }
      root.requestedState = -1
      root.busy = false
      root.refresh()
    }
  }

  Process {
    id: notificationProcess
    running: false
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.busy ? "\uf110" : (root.passwordless ? "\uf09c" : "\uf023")
    active: root.passwordless
    interactive: !root.busy
    tooltipText: root.busy
      ? "Changing passwordless sudo…"
      : (root.passwordless
          ? "Passwordless sudo enabled — click to disable"
          : "Passwordless sudo disabled — click to enable")
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.refresh()
      else if (mouseButton === Qt.LeftButton) root.toggle()
    }
  }
}
