use miti::{Bs, MONTHS_EN, MONTHS_NP, WEEKDAYS_NP, ad_str, days_in_month, np_digits};
use std::env;

// Daemon and self-install need unix sockets and systemd/launchd.
#[cfg(unix)]
mod sys;
#[cfg(not(unix))]
mod sys {
    const NO: &str = "not available on this platform; the query commands are";
    pub fn serve() -> Result<String, String> {
        Err(NO.into())
    }
    pub fn install(_daemon: bool) -> Result<String, String> {
        serve()
    }
    pub use serve as uninstall;
}

const HELP: &str = "miti - Nepali (Bikram Sambat) calendar

  miti [today] [-j]        today's date in Nepal (-j: JSON)
  miti ad2bs YYYY-MM-DD [-j]
  miti bs2ad YYYY-MM-DD [-j]
  miti cal [YYYY-MM]       BS month grid, today marked *
  miti month [YYYY-MM]     every day of a BS month as JSON
  miti serve               answer the commands above on $XDG_RUNTIME_DIR/miti.sock
                             ($TMPDIR on macOS; one command line per connection, reply, close)
  miti install [--daemon]  install the binary, plus the KDE and GNOME widgets on Linux.
                             --daemon also runs `serve` at login (systemd or launchd);
                             no widget needs it
  miti uninstall";

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let args: Vec<&str> = args.iter().map(String::as_str).collect();
    let res = match args.first().copied() {
        Some("serve") => sys::serve(),
        Some("install") => sys::install(args.contains(&"--daemon")),
        Some("uninstall") => sys::uninstall(),
        _ => run(&args),
    };
    match res {
        Ok(out) if out.is_empty() => {}
        Ok(out) => println!("{out}"),
        Err(e) => {
            eprintln!("miti: {e}");
            std::process::exit(1);
        }
    }
}

/// The pure queries, shared by the CLI and the daemon.
pub(crate) fn run(args: &[&str]) -> Result<String, String> {
    let json = args.contains(&"-j");
    let pos: Vec<&str> = args.iter().copied().filter(|a| *a != "-j").collect();
    let today = || {
        Bs::today().ok_or("today is outside the date table".to_string())
    };
    match pos[..] {
        [] | ["today"] => Ok(describe(today()?, json)),
        ["ad2bs", s] => {
            let p: Vec<&str> = s.split('-').collect();
            let ad = match p[..] {
                [y, m, d] => (|| Some((y.parse().ok()?, m.parse().ok()?, d.parse().ok()?)))(),
                _ => None,
            };
            let (y, m, d) = ad.ok_or_else(|| format!("bad date '{s}', want YYYY-MM-DD"))?;
            let bs =
                Bs::from_ad(y, m, d).ok_or_else(|| format!("no such AD date in table: {s}"))?;
            Ok(describe(bs, json))
        }
        ["bs2ad", s] => {
            let bs = s.parse()?;
            Ok(if json { describe(bs, true) } else { ad_str(bs) })
        }
        ["cal"] => Ok(cal(today()?, today().ok())),
        ["cal", ym] => Ok(cal(format!("{ym}-01").parse()?, today().ok())),
        ["month"] => Ok(month(today()?)),
        ["month", ym] => Ok(month(format!("{ym}-01").parse()?)),
        _ => Ok(HELP.to_string()),
    }
}

fn describe(bs: Bs, json: bool) -> String {
    let (m, w) = (bs.month as usize - 1, bs.weekday().unwrap() as usize);
    let (year_np, day_np) = (np_digits(bs.year as u32), np_digits(bs.day as u32));
    let i = bs.info();
    let (tithi, ev_np) = i.map_or(("", ""), |i| (i.tithi, i.event_np));
    if !json {
        let extra: Vec<&str> = [tithi, ev_np]
            .into_iter()
            .filter(|s| !s.is_empty())
            .collect();
        let mut s = format!(
            "{year_np} {} {day_np}, {}\n{bs} BS | {} AD",
            MONTHS_NP[m],
            WEEKDAYS_NP[w],
            ad_str(bs)
        );
        if !extra.is_empty() {
            s += &format!("\n{}", extra.join(" · "));
        }
        return s;
    }
    miti::day_json(bs)
}

fn month(of: Bs) -> String {
    miti::month_json(of.year, of.month).unwrap() // `of` came from a parsed or current date
}

fn cal(of: Bs, today: Option<Bs>) -> String {
    let first = Bs { day: 1, ..of };
    let mut s = format!(
        "  {} {}\nSu  Mo  Tu  We  Th  Fr  Sa\n",
        MONTHS_EN[of.month as usize - 1],
        of.year
    );
    s += &"    ".repeat(first.weekday().unwrap() as usize);
    for day in 1..=days_in_month(of.year, of.month).unwrap() {
        let d = Bs { day, ..of };
        let mark = if Some(d) == today { '*' } else { ' ' };
        let end = if d.weekday() == Some(6) { '\n' } else { ' ' };
        s += &format!("{day:>2}{mark}{end}");
    }
    s.trim_end().to_string()
}
