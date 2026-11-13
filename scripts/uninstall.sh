#!/bin/sh
# Remove everything miti puts on this machine, for the current user. Linux and macOS.
# Needs nothing but this file: no miti binary, no source checkout. Safe to run twice.
# `miti uninstall` runs this same script.
#
# It removes, where present:
#   both     ~/.local/bin/miti, the daemon's socket, any running daemon
#   Linux    the systemd user service, the KDE widget, the GNOME extension
#   macOS    the launchd agents, the menu bar app
# Paths that are symlinks (a developer's checkout) lose only the link.
set -u

gone() { # remove a file, directory or symlink, and say so
    if [ -e "$1" ] || [ -L "$1" ]; then
        rm -rf -- "$1" && echo "removed $1"
    fi
}

uid=$(id -u)

if [ "$(uname -s)" = Darwin ]; then
    for agent in org.miti org.miti.bar; do
        plist=$HOME/Library/LaunchAgents/$agent.plist
        [ -e "$plist" ] && launchctl unload "$plist" 2>/dev/null
        gone "$plist"
    done
    pkill -u "$uid" -x MitiBar 2>/dev/null
    gone "$HOME/.local/bin/MitiBar"
    gone "$HOME/Library/Preferences/MitiBar.plist"
    gone "$HOME/Library/Application Support/miti" # menu bar plugin of early versions
    runtime=${TMPDIR:-/tmp}
else
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user disable --now miti.service >/dev/null 2>&1
    fi
    gone "$HOME/.config/systemd/user/miti.service"
    gone "$HOME/.config/systemd/user/default.target.wants/miti.service"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl --user daemon-reload >/dev/null 2>&1
        systemctl --user reset-failed miti.service >/dev/null 2>&1
    fi
    # Disabling drops the extension from GNOME's enabled list; it must happen before the files go.
    if command -v gnome-extensions >/dev/null 2>&1; then
        gnome-extensions disable miti@miti.org >/dev/null 2>&1
    fi
    gone "$HOME/.local/share/gnome-shell/extensions/miti@miti.org"
    gone "$HOME/.local/share/plasma/plasmoids/org.miti.widget"
    runtime=${XDG_RUNTIME_DIR:-/run/user/$uid}
fi

# A daemon started by hand, outside systemd or launchd.
pkill -u "$uid" -f '(^|/)miti serve$' 2>/dev/null
gone "${runtime%/}/miti.sock"

gone "$HOME/.local/bin/miti"
gone "$HOME/.local/bin/miti.new" # left behind only if an install was interrupted

# Folders the install may have created, removed only if now empty.
for dir in .local/share/gnome-shell/extensions .local/share/gnome-shell \
    .local/share/plasma/plasmoids .local/share/plasma .config/systemd/user/default.target.wants; do
    rmdir "$HOME/$dir" 2>/dev/null
done

echo "miti is uninstalled."
if [ "$(uname -s)" != Darwin ]; then
    echo "If the KDE widget was on a panel, an empty slot stays there: right-click it and remove it."
fi
