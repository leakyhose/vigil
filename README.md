# Vigil

A menu bar app that keeps your Mac awake while your coding agents work, then lets it sleep when they're done.

Built for T3 Code: Vigil watches T3's threads and stays awake while any turn is running **or** while a thread is paused on a usage limit that T3 will auto-resume. Without that, your Mac sleeps during the wait and the resume never happens. It also tracks Claude Code sessions you run in a terminal.

## Install

1. Download `Vigil-x.y.z.zip` from [Releases](../../releases/latest) and unzip it.
2. Drag **Vigil.app** into **Applications**.
3. Open it. The app isn't notarized, so the first time macOS will block it. Go to **System Settings → Privacy & Security**, scroll down and click **Open Anyway**. (Or run `xattr -dr com.apple.quarantine /Applications/Vigil.app`.)

Requires macOS 13 or later. Works on Apple Silicon and Intel.

## Use

Click the icon in the menu bar:

| Icon | Meaning |
| --- | --- |
| ☾ dim moon | **Off.** Vigil does nothing; your Mac sleeps normally. |
| ☕ outline cup | **On**, but nothing is running. Your Mac can sleep. |
| ☕ **orange cup + number** | **Keeping your Mac awake.** The number is how many agents are working or waiting on a limit reset. |
| 🔋 red battery | On, but paused because the battery is at 10% or below. |

- **Turn On / Turn Off** (⌘T in the menu) switches between off and your last mode.
- **Keep Awake While Agents Work** (default): awake only while something is running or waiting on a limit reset.
- **Keep Awake Always**: awake until you turn it off.

The menu lists which threads are running and when limited threads will resume.

### Lid closed and on battery

Out of the box Vigil keeps the Mac awake with the lid **open**, on battery or plugged in. To also keep it awake with the lid **closed**, choose **Settings → Enable Lid-Closed Support…** and enter your password once. This installs a sudoers rule (`/etc/sudoers.d/vigil`) that lets your user run exactly `pmset -a disablesleep 0|1` without a password. Vigil sets it while holding and clears it when done. If the lid is already closed when your agents finish, the Mac goes to sleep right away.

Don't leave a Mac with the lid closed in a bag while Vigil is holding it awake. It will get hot.

### Settings

- **Track Claude Code Outside T3**: installs hooks in `~/.claude/settings.json` so Claude Code sessions in a terminal count as working. Sessions started by T3 are already tracked without this.
- **Let Mac Sleep at 10% Battery** (on by default): so a dead battery doesn't take your work with it.
- **Launch at Login**
- **Open Log**: everything Vigil does is logged to `~/Library/Logs/Vigil.log`.

## How it works

Every 15 seconds Vigil checks:

- **T3 Code** (`~/.t3/userdata/statev2.sqlite`, opened read-only): threads with a turn in progress, and threads whose limit recovery has auto-resume on and a reset within the next 12 hours. It keeps counting for 10 minutes past the reset so the resumed turn has time to start.
- **Claude Code hooks**: a marker file per busy session in `~/.claude/keepawake/active`, written on prompt submit and removed when the turn stops. Markers from crashed sessions are cleaned up.

While anything is active, Vigil holds an IOKit power assertion (visible in `pmset -g assertions`), plus `disablesleep` if lid-closed support is enabled. When you quit, turn it off, or it crashes and restarts, everything is released.

T3's database format is internal and undocumented. If a T3 update changes it, Vigil fails safe: it sees no T3 activity rather than crashing.

## Uninstall

1. If enabled: **Settings → Remove Lid-Closed Support…** and turn off **Track Claude Code Outside T3**.
2. Quit Vigil and delete it from Applications.

## Build from source

```sh
scripts/build-app.sh 0.1.0   # → dist/Vigil.app and dist/Vigil-0.1.0.zip
swift test                   # needs Xcode
```

## License

MIT
