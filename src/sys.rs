//! Unix only: the socket daemon and self-install (systemd on Linux, launchd on macOS).

use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::{fs::PermissionsExt, net::UnixListener};
use std::process::{Command, Stdio};
use std::{env, fs, time::Duration};

#[cfg(not(target_os = "macos"))]
const UNIT: &str = "[Unit]
Description=Nepali (Bikram Sambat) date service

[Service]
ExecStart=%h/.local/bin/miti serve
Restart=on-failure

[Install]
WantedBy=default.target
";

// (path under $HOME, contents) for everything `install` writes besides the binary.
// The service file comes first. "@HOME@" in contents becomes $HOME.
#[cfg(not(target_os = "macos"))]
const FILES: [(&str, &str); 6] = [
    (".config/systemd/user/miti.service", UNIT),
    (".local/share/plasma/plasmoids/org.miti.widget/metadata.json", include_str!("../widgets/plasmoid/metadata.json")),
    (".local/share/plasma/plasmoids/org.miti.widget/contents/ui/main.qml", include_str!("../widgets/plasmoid/contents/ui/main.qml")),
    (".local/share/gnome-shell/extensions/miti@miti.org/metadata.json", include_str!("../widgets/gnome/metadata.json")),
    (".local/share/gnome-shell/extensions/miti@miti.org/extension.js", include_str!("../widgets/gnome/extension.js")),
    (".local/share/gnome-shell/extensions/miti@miti.org/stylesheet.css", include_str!("../widgets/gnome/stylesheet.css")),
];
#[cfg(not(target_os = "macos"))]
const NOTE: &str = "the KDE and GNOME widgets.
KDE: add 'Nepali Date' from the panel's Add Widgets list.
GNOME: log out and in, then run: gnome-extensions enable miti@miti.org";

// launchd does not expand ~, so the plist carries the absolute path.
#[cfg(target_os = "macos")]
const PLIST: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>org.miti</string>
    <key>ProgramArguments</key>
    <array><string>@HOME@/.local/bin/miti</string><string>serve</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
</dict>
</plist>
"#;
#[cfg(target_os = "macos")]
const FILES: [(&str, &str); 1] = [("Library/LaunchAgents/org.miti.plist", PLIST)];
#[cfg(target_os = "macos")]
const NOTE: &str = "no widget.\nMenu bar app: build macos/MitiBar (see README).";

const BIN: &str = ".local/bin/miti";


fn err(e: impl ToString) -> String {
    e.to_string()
}

pub fn serve() -> Result<String, String> {
    // macOS has no XDG_RUNTIME_DIR; its per-user $TMPDIR plays that role.
    let dir = env::var("XDG_RUNTIME_DIR").or_else(|_| env::var("TMPDIR")).map_err(|_| "XDG_RUNTIME_DIR or TMPDIR not set")?;
    let path = format!("{}/miti.sock", dir.trim_end_matches('/'));
    let _ = fs::remove_file(&path); // stale socket from a previous run
    let listener = UnixListener::bind(&path).map_err(|e| format!("{path}: {e}"))?;
    // shortcut: one client at a time with a 2s read timeout, go threaded if clients ever queue up
    for mut conn in listener.incoming().flatten() {
        let _ = conn.set_read_timeout(Some(Duration::from_secs(2)));
        let mut line = String::new();
        if BufReader::new(&conn).take(256).read_line(&mut line).is_ok() {
            let args: Vec<&str> = line.split_whitespace().collect();
            let out = crate::run(&args).unwrap_or_else(|e| format!("error: {e}"));
            let _ = writeln!(conn, "{out}");
        }
    }
    Ok(String::new())
}

fn cmd(prog: &str, args: &[&str]) -> Result<(), String> {
    let ok = Command::new(prog).args(args).status().map_err(|e| format!("{prog}: {e}"))?.success();
    ok.then_some(()).ok_or(format!("{prog} {} failed", args.join(" ")))
}

/// Start (or restart) the daemon and enable it at login.
#[cfg(not(target_os = "macos"))]
fn start_service(_home: &str) -> Result<(), String> {
    cmd("systemctl", &["--user", "daemon-reload"])?;
    cmd("systemctl", &["--user", "enable", "miti.service"])?;
    cmd("systemctl", &["--user", "restart", "miti.service"])
}

#[cfg(target_os = "macos")]
fn start_service(home: &str) -> Result<(), String> {
    let plist = format!("{home}/{}", FILES[0].0);
    // Unload first so a reinstall restarts the daemon; fails harmlessly when nothing is loaded.
    let _ = cmd("launchctl", &["unload", &plist]);
    cmd("launchctl", &["load", "-w", &plist])
}

/// `daemon`: also install and start the login service. Off by default: no widget uses the
/// daemon, it is only for other programs that want the socket.
pub fn install(daemon: bool) -> Result<String, String> {
    let home = env::var("HOME").map_err(err)?;
    let write = |rel: &str, f: &dyn Fn(&str) -> std::io::Result<()>| {
        let path = format!("{home}/{rel}");
        fs::create_dir_all(path.rsplit_once('/').unwrap().0).and_then(|_| f(&path)).map_err(|e| format!("{path}: {e}"))
    };
    // Copy then rename: the daemon may be running the old binary, which cannot be written in place.
    let me = env::current_exe().map_err(err)?;
    write(BIN, &|p| {
        let tmp = format!("{p}.new");
        fs::copy(&me, &tmp).and_then(|_| fs::rename(&tmp, p))
    })?;
    // FILES[0] is the service file. Without --daemon it is not even written: on macOS
    // a plist in LaunchAgents starts at the next login whether or not it was loaded.
    for (rel, text) in FILES.into_iter().skip(if daemon { 0 } else { 1 }) {
        write(rel, &|p| {
            fs::write(p, text.replace("@HOME@", &home))?;
            let mode = if rel.ends_with(".sh") { 0o755 } else { 0o644 };
            fs::set_permissions(p, fs::Permissions::from_mode(mode))
        })?;
    }
    if daemon {
        start_service(&home)?;
    }
    let extra = if daemon { ", the miti daemon (running)" } else { "" };
    Ok(format!("installed ~/{BIN}{extra} and {NOTE}"))
}

/// Runs the bundled `uninstall.sh`, the one list of everything miti installs, so
/// uninstalling with or without this binary removes exactly the same things.
pub fn uninstall() -> Result<String, String> {
    let mut sh = Command::new("sh").arg("-s").stdin(Stdio::piped()).spawn().map_err(|e| format!("sh: {e}"))?;
    sh.stdin.take().unwrap().write_all(include_bytes!("../scripts/uninstall.sh")).map_err(err)?;
    sh.wait().map_err(err)?;
    Ok(String::new())
}
