<div align="center">

# Claude Usage for macOS

**Your Claude limits and token usage, one click away in the menu bar.**

A tiny native menu bar app that shows your **5-hour session limit**, your **weekly limits**
and how many tokens you have used **per model since day one**.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![Dependencies](https://img.shields.io/badge/dependencies-none-2ea44f)
![License: MIT](https://img.shields.io/badge/license-MIT-blue)

<img src="docs/panel-light.png" alt="Claude Usage panel, light mode" width="360">&nbsp;&nbsp;<img src="docs/panel-dark.png" alt="Claude Usage panel, dark mode" width="360">

*Screenshots use made-up numbers.*

</div>

---

## Features

- **Icon only in the menu bar.** No text, no clutter. Hover for a one-line summary, click for the panel.
- **Session (5h) and Weekly limits** with progress bars and live "resets in 1h 12m (12:39)" countdowns.
  The bar turns red above 90%.
- **Model usage since your first message.** One stacked bar shows each model's share of everything you
  have used, with a legend of per-model totals. Hover a model to see the input / output / cache breakdown.
- **Two data modes.** Works fully offline from Claude Code's own logs, or (opt-in) shows your *exact*
  limits straight from Claude. See [How it works](#how-it-works).
- **Native and light.** One Swift file, no dependencies, no Dock icon, follows light and dark mode.

## Install

Short version, for people who have done this before:

```bash
xcode-select --install        # skip if you already have Xcode or the command line tools
git clone https://github.com/L33N0tL33/claude-usage-menubar.git
cd claude-usage-menubar
./build.sh
```

The script compiles the app (under a minute), puts **Claude Usage.app** in `~/Applications` and opens it.
Look for the small bar-chart icon in the top right of your menu bar. New to Terminal? Follow the
[step-by-step guide](#installation-guide-step-by-step) below.

**Want your own icon?** Put a square, transparent `logo.png` next to `build.sh` before building and it
becomes the menu bar and panel icon. Without one, a plain bar-chart symbol is used.

## Installation guide (step by step)

### Before you start

| You need | How to check |
|---|---|
| A Mac on **macOS 13 Ventura or newer** (Apple silicon or Intel) | Apple menu, **About This Mac**. Or run `sw_vers -productVersion` in Terminal. |
| **Claude Code** installed and used at least once on this Mac | Run `claude --version` in Terminal. The app reads its session logs. |
| About **5 minutes** and an internet connection | |

Nothing else is needed: no Xcode app, no Homebrew, no account.

### Step 1: open Terminal

Press **⌘ Space**, type `Terminal`, press **Return**. Every command below is typed (or pasted) there,
followed by **Return**.

### Step 2: install Apple's command line tools

These give you `git` and the Swift compiler. Check whether you already have them:

```bash
xcode-select -p
```

- If it prints a path such as `/Library/Developer/CommandLineTools`, you have them. Go to step 3.
- If it says *"unable to get active developer directory"*, install them:

  ```bash
  xcode-select --install
  ```

  A window pops up. Click **Install** and wait for it to finish (a few minutes, depending on your
  connection). Then run `swiftc --version` once to confirm it prints a version.

### Step 3: download the project

**With git (recommended):**

```bash
cd ~
git clone https://github.com/L33N0tL33/claude-usage-menubar.git
cd claude-usage-menubar
```

**Without git:** on the [repository page](https://github.com/L33N0tL33/claude-usage-menubar) click the green
**Code** button, then **Download ZIP**. Double-click the ZIP to unpack it, then in Terminal:

```bash
cd ~/Downloads/claude-usage-menubar-main
```

### Step 4: build and install

```bash
./build.sh
```

(If it says *permission denied*, which happens with the ZIP download, run `zsh build.sh` instead.)

The first build takes up to a minute and prints `built /Users/you/Applications/Claude Usage.app`. The
script then opens the app. It has **no window and no Dock icon**, so nothing seems to happen: that is normal.

### Step 5: find it and check it works

1. Look at the **top right of the menu bar**, near the clock. You should see a small bar-chart icon.
   (A crowded menu bar can hide it. Hold **⌘** and drag other icons away to make room.)
2. **Click it.** The panel opens with a **Session (5h)** row, a **Weekly** row and **Model usage**.
3. If you see only token counts and no percentages, that is expected: continue to step 6.

For a command line check that the app can read your Claude Code logs, run:

```bash
"$HOME/Applications/Claude Usage.app/Contents/MacOS/ClaudeUsage" --dump
```

You should see a line per model with message and token counts. If it prints nothing useful, see
[Troubleshooting](#troubleshooting).

### Step 6 (optional): turn on exact limits

Click the icon, then the **gear**, then **Exact limits from Claude**. Read the explanation, click
**Turn on**, and when macOS asks for access to *Claude Code-credentials*, choose **Always Allow**. The panel
switches to **source: API** and shows your real percentages. Details and risks:
[How it works](#how-it-works) and [Privacy and security](#privacy-and-security).

### Step 7 (optional): start it at login

Click the icon, the **gear**, then **Start at login**. macOS may show a notice that a login item was
added.

### Updating

```bash
cd ~/claude-usage-menubar     # or wherever you cloned it
git pull
./build.sh
```

The script quits the running copy, rebuilds and reopens it. Your settings are kept. After an update macOS
may ask once more to allow Keychain access, because each build is a new binary: choose **Always Allow**.
(If you used the ZIP download, download the new ZIP and run steps 3 and 4 again.)

### Install troubleshooting

| Problem | Fix |
|---|---|
| `xcrun: error: invalid active developer path` or `swiftc: command not found` | The command line tools are missing or broken. Run `xcode-select --install` (step 2). |
| `zsh: permission denied: ./build.sh` | Run `zsh build.sh`, or `chmod +x build.sh` once and try again. |
| Build errors mentioning `ImageRenderer` or `SMAppService` being unavailable | Your macOS is older than 13. Update macOS, then build again. |
| The build looks stuck | The first Swift build can take a minute. Wait, then check for the `built …` line. |
| `./build.sh: No such file or directory` | You are in the wrong folder. Run `cd ~/claude-usage-menubar` (or the folder you unpacked) first. |
| The app is built but there is no icon | It is running without a window by design. Look top right, and make room by holding **⌘** and dragging icons. To start it again: `open "$HOME/Applications/Claude Usage.app"`. |
| The panel shows no models or zero tokens | There are no Claude Code logs on this Mac yet. Use Claude Code once, then press the refresh button. |
| macOS says the app "is damaged" after you copied it to another Mac | Run `xattr -cr "/Applications/Claude Usage.app"` there, or right-click it and choose **Open**. Building on that Mac avoids this. |

## Using it

Click the icon to open the panel. Click the gear for settings:

| Menu item | What it does |
|---|---|
| **Exact limits from Claude** | Turns on the exact 5-hour and weekly percentages (off by default, see below). |
| **Set 5-hour limit… / Set weekly limit…** | Your own limits for the offline mode, for example `3m` or `800k`. |
| **Start at login** | Launches the app when you sign in. |
| **Quit** | Closes the app. |

The refresh button (circular arrow) re-reads everything immediately. Otherwise it refreshes once a minute.

## How it works

### Local mode (the default)

Claude Code writes a log of every session to `~/.claude/projects/**/*.jsonl`, including the token counts
of each reply. The app reads those files **on your Mac only** and nothing leaves your machine.

- Resumed sessions copy earlier messages, so every message is counted **once** (matched by message id and
  request id).
- **Counted tokens = input + output + cache writes.** Cache reads are shown in the model totals but not
  counted toward a limit.
- **5-hour window:** starts on the hour of your first message after the previous window ended and lasts
  five hours.
- **Weekly:** a rolling window over the last seven days.
- Percentages only appear if you set your own limits in the gear menu, because the real limit sizes
  are not stored on your computer. Without limits you see token counts.
- It only knows about Claude Code usage **on this Mac**.

### Exact limits (opt-in)

Turn on **Exact limits from Claude** in the gear menu and the panel shows the same percentages and reset
times Claude itself uses, for your whole account (including claude.ai), plus your plan name.

To do that the app:

1. reads the sign-in token Claude Code already keeps in your login Keychain (item
   `Claude Code-credentials`), and macOS asks you to allow it,
2. asks Anthropic's usage endpoint `https://api.anthropic.com/api/oauth/usage` for your current usage
   (at most once every two minutes),
3. shows the result, and falls back to local mode if anything goes wrong.

The code for this is the single function `fetchApi()` in [`main.swift`](main.swift), about 40 lines.
Please read it before you turn the feature on.

## Privacy and security

- **Off by default.** Until you switch on exact limits the app makes **no network requests** and never
  touches your Keychain.
- The token is held in memory just long enough to make one request. It is **never written to disk, never
  logged, and never sent anywhere except Anthropic's API.**
- The app **never refreshes or modifies** the token, so it cannot sign Claude Code out. If the token has
  expired, the panel says so and falls back to local numbers. Use Claude Code once to renew it.
- There is no analytics, no telemetry and no account.

## Good to know

- **This is unofficial.** It is not made, endorsed or supported by Anthropic.
- The usage endpoint is **undocumented** and could change or disappear at any time. If it does, exact
  mode will stop working and the app falls back to local mode. Use it at your own risk.
- Plans and limits change. The panel shows whatever rows the service returns, for example a separate
  weekly row for a single model.

## Troubleshooting

| Problem | Fix |
|---|---|
| macOS asks to use "Claude Code-credentials" | That is exact mode asking permission. Choose **Always Allow**, or turn the feature off in the gear menu. |
| Only token counts, no percentages | Turn on **Exact limits from Claude**, or set your own limits in the gear menu. |
| Orange note: "login token expired" | Open Claude Code once so it renews its sign-in, then press refresh. |
| "no Claude login found" | Sign in with `claude` first. Exact mode needs Claude Code's login. |
| The icon is missing | A crowded menu bar can hide it. Hold ⌘ and drag icons to make room. |
| Numbers look low | Local mode only sees logs on this Mac. Exact mode covers your whole account. |

## Development

```
main.swift     the whole app (scanner, usage service client, SwiftUI panel, menu bar item)
build.sh       compiles into "Claude Usage.app" (OUT=/folder ./build.sh builds elsewhere, no launch)
Info.plist     bundle info (LSUIElement, so there is no Dock icon)
docs/          README screenshots
```

Diagnostics built into the binary:

```bash
APP="$HOME/Applications/Claude Usage.app/Contents/MacOS/ClaudeUsage"
"$APP" --dump                                   # print the local numbers and exit
"$APP" --selftest out.png                       # render the panel to a PNG and exit
"$APP" --selftest out.png --demo --dark         # the same with made-up numbers, in dark mode
```

That is how the screenshots above were made.

## Uninstall

Choose **Quit** in the gear menu, then:

```bash
rm -rf "$HOME/Applications/Claude Usage.app"
defaults delete com.l33n0tl33.claude-usage      # forget your saved settings
```

If you used **Start at login**, turn it off first in the gear menu, or remove it in
System Settings, General, Login Items.

## Credits and licence

Layout inspired by the Claude usage widget in the [Omarchy](https://omarchy.org) bar.

Released under the [MIT License](LICENSE).

*Claude is a trademark of Anthropic, PBC. This project is an independent tool and is not affiliated with
Anthropic.*
