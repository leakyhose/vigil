# Vigil

A menu bar app that keeps your Mac awake while your coding agents work, including while T3 Code waits for a usage limit to reset. When everything is done, it lets the Mac sleep.

## Install

1. Download the zip from [Releases](../../releases/latest), unzip, and drag **Vigil.app** into Applications.
2. Open it. The first time, macOS blocks it because it isn't notarized: go to **System Settings → Privacy & Security → Open Anyway**.

Requires macOS 13+.

## Use

Click the menu bar icon and choose a mode. Choose the checked one again to turn Vigil off.

- **Keep Awake While Agents Work**: awake while agents are running or waiting on a limit reset
- **Keep Awake Always**: awake until you turn it off

The icon shows what it's doing:

- **Dim moon**: off
- **Outline cup**: on, nothing running
- **Orange cup + number**: keeping the Mac awake
- **Red battery**: paused at 10% battery

To keep the Mac awake with the lid closed, choose **Settings → Enable Lid-Closed Support…** and enter your password once.

Logs are in `~/Library/Logs/Vigil.log`.

## Build

```sh
scripts/build-app.sh 0.1.0   # needs Xcode
```

MIT License
