#!/bin/sh
# Install miti for the current user. No root needed.
# Run from an extracted release archive, or from a source checkout (builds with cargo).
#
#   ./install.sh            the miti binary plus the desktop widgets
#   ./install.sh --daemon   also run the date daemon at login (no widget needs it)
#
# Undo with ./uninstall.sh or `miti uninstall`.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
os=$(uname -s)

if [ -x "$here/miti" ]; then
    bin=$here/miti
elif [ -f "$here/Cargo.toml" ]; then
    echo "building miti from source..."
    (cd "$here" && cargo build --release)
    bin=$here/target/release/miti
else
    echo "install.sh: no miti binary beside this script, and no source to build" >&2
    exit 1
fi

if [ "$os" = Darwin ]; then
    # Downloaded builds are unsigned; Gatekeeper refuses to run them while quarantined.
    xattr -dr com.apple.quarantine "$here" 2>/dev/null || true
fi

# Linux: binary, KDE and GNOME widgets. macOS: binary. --daemon is passed through.
"$bin" install "$@"

if [ "$os" = Darwin ]; then
    bar=$here/MitiBar
    if [ ! -x "$bar" ] && [ -d "$here/widgets/macos/MitiBar" ]; then
        echo "building the menu bar app..."
        swift build -c release --package-path "$here/widgets/macos/MitiBar"
        bar=$here/widgets/macos/MitiBar/.build/release/MitiBar
    fi
    if [ -x "$bar" ]; then
        agent=$HOME/Library/LaunchAgents/org.miti.bar.plist
        mkdir -p "$HOME/Library/LaunchAgents"
        launchctl unload "$agent" 2>/dev/null || true # stops a running copy before it is replaced
        cp "$bar" "$HOME/.local/bin/MitiBar"
        cat > "$agent" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>org.miti.bar</string>
    <key>ProgramArguments</key>
    <array><string>$HOME/.local/bin/MitiBar</string></array>
    <key>RunAtLoad</key><true/>
</dict>
</plist>
PLIST
        launchctl load -w "$agent"
        echo "installed the menu bar app: running now, and at every login"
    else
        echo "MitiBar not found beside this script: menu bar app not installed"
    fi
fi

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "note: add ~/.local/bin to your PATH to use 'miti' in a terminal" ;;
esac
