# miti

Nepali (Bikram Sambat) calendar for the terminal, other programs, and the desktop.

- **CLI**: today's date, BS ⇄ AD conversion, month grids, JSON output.
- **Daemon**: a tiny unix-socket service any program can ask for the date.
- **Library**: a Rust crate with no dependencies.
- **Widgets**: KDE Plasma, GNOME Shell, macOS menu bar, Windows tray.

```
$ miti
२०८३ कार्तिक २७, शुक्रवार
2083-07-27 BS = 2026-11-13 AD
चतुर्थी
```

Covers BS 1901–2199 (AD 1844–2143). Dates are Nepal time (UTC+5:45) whatever your timezone is.
Tithi, holidays and events are included for about 2075–2084.

## Design

miti is built to make the final binary fast, lean and simple.

- **Lean:** the CLI is one binary of about 765 kB with no dependencies, not even for JSON, which
  is written by hand. The idle daemon uses about 140 kB of private RAM.
- **Fast:** a run takes about 1 ms including process start (measured over 300 runs of
  `miti today -j`). Conversion is a table walk with no allocation.
- **Simple:** BS month lengths follow no formula, so the whole calendar is one lookup table
  compiled into the binary as read-only data. The OS pages it in from disk on demand and it
  takes no heap. There is no config file, no cache and no network access.
- **Small surface:** the widgets and the desktop app run the CLI or link the library. The daemon
  is optional and off by default; its serve loop is under 20 lines.

Inspired by [NepDate](https://github.com/sanamhub/nepdate).

## Install

Download your platform's build from the release page, or from the artifacts of a
[build](.github/workflows/build.yml) run. Artifact names end in the commit hash they were built
from. GitHub's artifact download wraps everything in a `.zip`, so unzip once first.

| Platform             | File                                  | Contains                                     |
| -------------------- | ------------------------------------- | -------------------------------------------- |
| Linux x86_64         | `miti-linux-x86_64-<commit>.tar.gz` | `miti` (carries the KDE and GNOME widgets), `miti-gui` (window app) |
| macOS, Apple silicon | `miti-macos-arm64-<commit>.tar.gz`  | `miti`, `MitiBar` (menu bar app), `miti-gui` (window app) |
| Windows x86_64       | `miti-windows-x86_64-<commit>`      | `miti.exe`, `MitiTray.exe` (tray app), `miti-gui.exe` (window app) |

### Linux

```bash
tar xzf miti-linux-x86_64-*.tar.gz
./install.sh
```

This copies the binary to `~/.local/bin/miti` (put that on your `PATH`) and installs both desktop
widgets. Nothing needs root. You can delete the extracted files afterwards. The daemon is not
started; no widget needs it. For that, run `./install.sh --daemon` and see [Daemon](#daemon).

- **KDE Plasma 6**: right-click the panel → Add or Manage Widgets → "Nepali Date".
- **GNOME Shell 45+**: log out and in, then `gnome-extensions enable miti@miti.org`.

### macOS

macOS 13 or newer, Apple silicon.

```bash
tar xzf miti-macos-arm64-*.tar.gz
./install.sh
```

This clears the download quarantine (the builds are not signed), copies `miti` and `MitiBar` to
`~/.local/bin`, and starts the menu bar app now and at every login through a launchd agent.

### Windows

Windows 10/11 with the [.NET 8 Desktop Runtime](https://dotnet.microsoft.com/download/dotnet/8.0).
Unzip, then in that folder:

```powershell
powershell -ExecutionPolicy Bypass -File install.ps1
```

This copies everything to `%LOCALAPPDATA%\Programs\miti`, adds that folder to your user `PATH`,
starts the tray app and makes it start at login. Nothing needs admin rights. The daemon does not
exist on Windows; every query command works.

### From source

```bash
./install.sh            # Linux and macOS: builds with cargo (and swift on macOS), then installs
```

On Windows, build with `cargo build --release` and
`dotnet publish widgets/windows/MitiTray -c Release -o dist`, copy `target\release\miti.exe`,
`install.ps1` and `uninstall.ps1` into `dist`, and run `install.ps1` there.

## Uninstall

Any one of these removes everything. None needs the files you installed from.

| Platform                          | Command                                                                                      |
| --------------------------------- | -------------------------------------------------------------------------------------------- |
| Linux, macOS                      | `miti uninstall`                                                                           |
| Linux, macOS, binary already gone | `sh uninstall.sh` (from a release archive or this repository)                                |
| Windows                           | `powershell -ExecutionPolicy Bypass -File "$env:LOCALAPPDATA\Programs\miti\uninstall.ps1"` |

`miti uninstall` runs the same `uninstall.sh`, so both remove exactly the same things.

### By hand

This is the complete list of what miti puts on a machine. It writes nothing outside your user
account, and no settings, cache or log files.

**Linux**

```bash
systemctl --user disable --now miti.service      # only if you used --daemon
gnome-extensions disable miti@miti.org         # only on GNOME
rm -f  ~/.config/systemd/user/miti.service ~/.config/systemd/user/default.target.wants/miti.service
rm -f  "$XDG_RUNTIME_DIR/miti.sock"
rm -rf ~/.local/share/plasma/plasmoids/org.miti.widget
rm -rf ~/.local/share/gnome-shell/extensions/miti@miti.org
rm -f  ~/.local/bin/miti ~/.local/bin/miti.new
systemctl --user daemon-reload
```

If the KDE widget was on a panel, an empty slot stays there: right-click it and remove it.

**macOS**

```bash
launchctl unload ~/Library/LaunchAgents/org.miti.bar.plist   # menu bar app
launchctl unload ~/Library/LaunchAgents/org.miti.plist       # only if you used --daemon
rm -f ~/Library/LaunchAgents/org.miti.bar.plist ~/Library/LaunchAgents/org.miti.plist
rm -f "$TMPDIR/miti.sock"
rm -f ~/.local/bin/miti ~/.local/bin/miti.new ~/.local/bin/MitiBar
```

**Windows**

1. Right-click the tray icon → Exit.
2. Delete the folder `%LOCALAPPDATA%\Programs\miti`.
3. Win+R → `shell:startup` → delete the "Nepali Date" shortcut.
4. Settings → System → About → Advanced system settings → Environment Variables → your user
   `Path` → remove the `...\Programs\miti` entry.

Windows 11 also remembers each tray icon under the registry key
`HKCU\Control Panel\NotifyIconSettings`; `uninstall.ps1` deletes miti's entry there too.

## CLI

```
miti [today] [-j]            today's date (-j: JSON)
miti ad2bs 2026-11-13 [-j]   AD to BS
miti bs2ad 2083-07-27 [-j]   BS to AD
miti cal [2083-07]           month grid, today marked *
miti month [2083-07]         every day of a month as JSON
miti serve                   run the daemon
miti install [--daemon]     Linux and macOS; --daemon also runs `serve` at login
miti uninstall              remove everything, see Uninstall
```

`-j` prints one JSON object: `bs`, `ad`, `year`, `month`, `day`, `weekday` (0 = Sunday), Nepali
and English names, `tithi`, `holiday`, `event_np`, `event_en`. Dates outside 1901–2199 BS are an
error with exit code 1.

## Daemon

`miti serve` listens on a unix socket: `$XDG_RUNTIME_DIR/miti.sock` on Linux, `$TMPDIR/miti.sock`
on macOS. It is off by default, since no widget uses it. `miti install --daemon` runs it at login,
as a systemd user service on Linux or a launchd agent on macOS.

The protocol is one line in, one reply out:

1. Connect.
2. Send a CLI command line, such as `today -j` or `bs2ad 2083-07-27`, ending in `\n`.
3. Read until the server closes the connection. Failures arrive as text starting with `error: `.

```bash
echo 'today -j' | socat - UNIX-CONNECT:$XDG_RUNTIME_DIR/miti.sock
```

It serves one client at a time and gives each 2 seconds to send its line.

## Library

```toml
[dependencies]
miti = { git = "https://github.com/<you>/miti" }
```

```rust
use miti::Bs;

let today = Bs::today().unwrap();              // Nepal time
let ad = today.to_ad();                        // Some((2026, 11, 13))
let bs = Bs::from_ad(2026, 11, 13).unwrap();   // 2083-07-27
let weekday = bs.weekday();                    // Some(5), Friday
let tithi = bs.info().map(|i| i.tithi);        // Some("चतुर्थी")
```

BS month lengths follow no formula, so conversion walks a lookup table compiled into the binary as
read-only data. The OS pages it in from disk on demand and it takes no heap.

## Widgets

Each widget shows today's BS date. Clicking opens a month grid with tithi, holidays in red, month
navigation, and details for the clicked day. They get data by running the CLI, once per Nepal day
and once per month viewed, not from the daemon.

| Platform        | Source                                                   | State                          |
| --------------- | -------------------------------------------------------- | ------------------------------ |
| KDE Plasma 6    | [widgets/plasmoid](widgets/plasmoid)                     | used daily                     |
| GNOME Shell 45+ | [widgets/gnome](widgets/gnome)                           | syntax-checked only, never run |
| macOS 13+       | [widgets/macos/MitiBar](widgets/macos/MitiBar)       | never run                      |
| Windows 10/11   | [widgets/windows/MitiTray](widgets/windows/MitiTray) | never run                      |

The last three were written without access to those systems. Fixes welcome.

## Desktop app

[gui/](gui) is a small Tauri window with the same month view as the widgets: grid, tithi, holidays
in red, month navigation, details for the clicked day, and a BS ⇄ AD converter. It links the `miti` library directly, so it
needs neither the CLI nor the daemon. The page is plain HTML with no npm step.

```bash
cargo run -p miti-gui
```

Linux needs WebKitGTK (`libwebkit2gtk-4.1-dev` on Debian and Ubuntu, `webkit2gtk-4.1` on Arch). Windows needs
the WebView2 runtime, which Windows 11 ships with. Release archives include the built `miti-gui` next to `miti`;
run it from the extracted folder. The install scripts do not install it, and `cargo build` at the repo root
does not build it.

## Data

- **Month lengths** (BS 1901–2199) are in [data/bs-calendar.json](data/bs-calendar.json), under the
  licence in [data/NOTICE](data/NOTICE). [scripts/gen_months.py](scripts/gen_months.py) turns it
  into `src/months.rs`; run it and rebuild after changing the JSON. Official calendars exist only up
  to about 2089; later years are projections that vary between sources, so treat dates past 2089
  as approximate.
- **Tithi, holidays and events** are in `data/days.tsv`, one row per day with data:
  `bs-date`, tithi, `H` for a holiday or `-`, then the event in Nepali and in English.

## Development

```bash
cargo test
python scripts/smoke_test.py          # needs a built binary: cargo build first
```

[test.yml](.github/workflows/test.yml) runs both on Linux, macOS and Windows, builds the Windows
and macOS widgets, and lints the KDE and GNOME ones. [build.yml](.github/workflows/build.yml) runs
it first, then produces the artifacts above.

## License

MIT
