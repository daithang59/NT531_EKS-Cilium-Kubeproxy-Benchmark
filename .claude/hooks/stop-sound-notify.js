#!/usr/bin/env node
"use strict";

const { spawnSync } = require("child_process");

function notifyWindowsToastWithSound() {
  const psScript = [
    "$ErrorActionPreference='SilentlyContinue'",
    "try {",
    "  [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] > $null",
    "  [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType=WindowsRuntime] > $null",
    "  $xml = New-Object Windows.Data.Xml.Dom.XmlDocument",
    "  $xml.LoadXml(\"<toast><visual><binding template='ToastGeneric'><text>Claude Code</text><text>Task complete.</text></binding></visual><audio src='ms-winsoundevent:Notification.Default'/></toast>\")",
    "  $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)",
    "  [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show($toast)",
    "} catch {",
    "  [console]::beep(880,140); [console]::beep(988,160)",
    "}"
  ].join(";");

  const result = spawnSync("pwsh", ["-NoProfile", "-Command", psScript], {
    stdio: "ignore"
  });

  return result.status === 0;
}

function playFallbackSound() {
  try {
    if (process.platform === "win32") {
      const result = spawnSync(
        "pwsh",
        [
          "-NoProfile",
          "-Command",
          "[console]::beep(880,140);[console]::beep(988,160)"
        ],
        { stdio: "ignore" }
      );

      if (result.status === 0) {
        return;
      }
    }
  } catch {
    // Fall back to terminal bell.
  }

  process.stdout.write("\u0007");
}

let rawInput = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => {
  rawInput += chunk;
});
process.stdin.on("end", () => {
  if (process.platform === "win32") {
    const notified = notifyWindowsToastWithSound();
    if (!notified) {
      playFallbackSound();
    }
  } else {
    playFallbackSound();
  }

  if (rawInput.length > 0) {
    process.stdout.write(rawInput);
  }
});
process.stdin.resume();
