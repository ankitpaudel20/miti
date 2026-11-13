// Nepali date in the GNOME top bar. All data comes from the `miti` CLI:
// `miti today -j` once per Nepal day, `miti month Y-M` once per month shown.

import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import St from 'gi://St';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';

const WEEKDAYS = ['आइत', 'सोम', 'मंगल', 'बुध', 'बिही', 'शुक्र', 'शनि'];
const AD_MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

// The BS date rolls over at Nepal midnight (UTC+5:45).
function nepalDay() {
    return new Date(Date.now() + 20700000).toISOString().slice(0, 10);
}

/** Run miti and hand its parsed JSON to `done`. Failures are logged and dropped. */
function miti(args, done, failed = () => {}) {
    const bin = GLib.find_program_in_path('miti') ??
        GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'miti']);
    try {
        const proc = Gio.Subprocess.new([bin, ...args], Gio.SubprocessFlags.STDOUT_PIPE);
        proc.communicate_utf8_async(null, null, (p, res) => {
            try {
                const [, out] = p.communicate_utf8_finish(res);
                if (p.get_successful())
                    done(JSON.parse(out));
                else
                    failed();
            } catch (e) {
                console.error(`miti: ${e}`);
            }
        });
    } catch (e) {
        console.error(`miti: ${e}`);
    }
}

// St.BoxLayout's `vertical` is deprecated since 48 and `orientation` is missing before it;
// the layout manager's property works on both.
function box(vertical, props = {}) {
    const b = new St.BoxLayout(props);
    b.layout_manager.orientation = vertical ? Clutter.Orientation.VERTICAL : Clutter.Orientation.HORIZONTAL;
    return b;
}

function label(text, style_class = '', props = {}) {
    return new St.Label({text, style_class, ...props});
}

const Indicator = GObject.registerClass(
class Indicator extends PanelMenu.Button {
    _init() {
        super._init(0.5, 'Nepali Date');
        this._today = null; // day object of today
        this._month = null; // month object on screen
        this._sel = null;   // day object whose details are shown
        this._alive = true;

        this._panelLabel = label('…', '', {y_align: Clutter.ActorAlign.CENTER});
        this.add_child(this._panelLabel);

        // One non-reactive menu item holds the whole calendar, so clicks reach the cells.
        const item = new PopupMenu.PopupBaseMenuItem({reactive: false, can_focus: false});
        // The calendar is rebuilt on every month change; the converter below it is built once.
        const outer = box(true, {style_class: 'miti-box', x_expand: true});
        this._box = box(true, {style_class: 'miti-box', x_expand: true});
        outer.add_child(this._box);
        outer.add_child(new PopupMenu.PopupSeparatorMenuItem());
        outer.add_child(this._converter());
        this._convError = label('', 'miti-red');
        outer.add_child(this._convError);
        item.add_child(outer);
        this.menu.addMenuItem(item);

        // Every open starts on today, never on a stale pick.
        this.menu.connect('open-state-changed', (_menu, open) => {
            if (open && this._today)
                this._show(this._today.year, this._today.month);
        });

        // Poll the clock instead of one long timer: survives suspend and clock changes,
        // and retries if miti was missing. Spawns only on a new day.
        this._refresh();
        this._timer = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 60, () => {
            this._refresh();
            return GLib.SOURCE_CONTINUE;
        });
    }

    destroy() {
        this._alive = false;
        GLib.source_remove(this._timer);
        super.destroy();
    }

    _refresh() {
        if (this._today?.ad === nepalDay())
            return;
        miti(['today', '-j'], d => {
            if (!this._alive)
                return;
            this._today = d;
            this._panelLabel.text = `${d.month_np} ${d.day_np}`;
            this._show(d.year, d.month);
        });
    }

    // Month arithmetic wraps the year; a month outside the table fails in miti and the view stays put.
    // `want`: BS date to select once the month has loaded (from the converter).
    _show(year, month, want = null) {
        const n = year * 12 + month - 1;
        miti(['month', `${Math.floor(n / 12)}-${n % 12 + 1}`], m => {
            if (!this._alive)
                return;
            this._month = m;
            this._sel = m.days.find(x => x.bs === want) ?? m.days.find(x => x.bs === this._today?.bs) ?? m.days[0];
            this._render();
        });
    }

    // Converter: jump to the typed date; the details pane then shows it in both calendars.
    _converter() {
        const entry = new St.Entry({hint_text: 'Go to date: YYYY-MM-DD', can_focus: true, x_expand: true, style_class: 'miti-entry'});
        const convert = command => miti([command, entry.text.trim(), '-j'], d => {
            if (!this._alive)
                return;
            this._convError.text = '';
            this._show(d.year, d.month, d.bs);
        }, () => {
            if (this._alive)
                this._convError.text = 'No such date in the table (BS 1901–2199)';
        });
        entry.clutter_text.connect('activate', () => convert('ad2bs')); // Enter converts AD to BS
        const row = box(false, {style: 'spacing: 6px;'});
        row.add_child(entry);
        row.add_child(this._navButton('AD → BS', 'Convert AD to BS', () => convert('ad2bs')));
        row.add_child(this._navButton('BS → AD', 'Convert BS to AD', () => convert('bs2ad')));
        return row;
    }

    _navButton(text, name, onClick) {
        const b = new St.Button({label: text, style_class: 'miti-nav', can_focus: true, accessible_name: name});
        b.connect('clicked', onClick);
        return b;
    }

    _render() {
        const m = this._month;
        this._box.destroy_all_children();
        this._cells = new Map(); // bs date -> cell button

        // Header: month, AD span, navigation.
        const first = m.days[0].ad.split('-'), last = m.days.at(-1).ad.split('-');
        const span = `${AD_MONTHS[first[1] - 1]}${first[0] === last[0] ? '' : ` ${first[0]}`} – ${AD_MONTHS[last[1] - 1]} ${last[0]}`;
        const titles = box(true, {x_expand: true});
        titles.add_child(label(`${m.month_np} ${m.year_np}`, 'miti-title'));
        titles.add_child(label(`${m.month_en} ${m.year} · ${span}`, 'miti-dim'));
        const header = box(false);
        header.add_child(titles);
        header.add_child(this._navButton('←', 'Previous month', () => this._show(m.year, m.month - 1)));
        header.add_child(this._navButton('आज', 'Today', () => this._show(this._today.year, this._today.month)));
        header.add_child(this._navButton('→', 'Next month', () => this._show(m.year, m.month + 1)));
        this._box.add_child(header);

        // Grid: weekday names, then the days, offset to day 1's weekday.
        const layout = new Clutter.GridLayout({column_homogeneous: true, column_spacing: 2, row_spacing: 2});
        const grid = new St.Widget({layout_manager: layout, x_expand: true});
        WEEKDAYS.forEach((name, col) => layout.attach(
            label(name, col === 6 ? 'miti-dim miti-red' : 'miti-dim', {x_align: Clutter.ActorAlign.CENTER}), col, 0, 1, 1));
        for (const day of m.days) {
            const slot = m.days[0].weekday + day.day - 1;
            layout.attach(this._cell(day), slot % 7, 1 + Math.floor(slot / 7), 1, 1);
        }
        this._box.add_child(grid);
        this._box.add_child(new PopupMenu.PopupSeparatorMenuItem());
        this._details = box(true);
        this._box.add_child(this._details);
        this._renderDetails();
    }

    // Details of the selected day.
    _renderDetails() {
        const sel = this._sel;
        this._details.destroy_all_children();
        const heading = box(false, {style: 'spacing: 8px;'});
        heading.add_child(label(`${sel.year_np} ${sel.month_np} ${sel.day_np}, ${sel.weekday_np}`, 'miti-heading'));
        if (sel.holiday)
            heading.add_child(label('बिदा', 'miti-red', {y_align: Clutter.ActorAlign.CENTER}));
        this._details.add_child(heading);
        this._details.add_child(label(`${sel.weekday_en}, ${sel.month_en} ${sel.day}, ${sel.year} BS · ${sel.ad} AD`, 'miti-dim'));
        if (sel.tithi)
            this._details.add_child(label(`तिथि: ${sel.tithi}`));
        // English titles; Nepali only when the patro has no English one.
        const events = sel.event_en || sel.event_np;
        if (events) {
            const l = label(events.split(' / ').join('\n'));
            l.clutter_text.line_wrap = true;
            this._details.add_child(l);
        }
    }

    _cell(day) {
        const classes = ['miti-cell'];
        if (day.holiday || day.weekday === 6)
            classes.push('miti-red');
        if (day.bs === this._today?.bs)
            classes.push('miti-today');
        if (day.bs === this._sel.bs)
            classes.push('miti-selected');

        const content = box(true);
        // Top line: a dot when the day has an event, and the AD day.
        content.add_child(label(`${day.event_np ? '• ' : ''}${Number(day.ad.slice(8))}`, 'miti-small miti-dim',
            {x_align: Clutter.ActorAlign.END}));
        content.add_child(label(day.day_np, 'miti-day', {x_align: Clutter.ActorAlign.CENTER}));
        content.add_child(label(day.tithi || ' ', 'miti-small miti-dim', {x_align: Clutter.ActorAlign.CENTER}));

        const cell = new St.Button({
            child: content,
            style_class: classes.join(' '),
            can_focus: true,
            x_expand: true,
            accessible_name: `${day.day} ${day.month_en}, ${day.tithi} ${day.event_en}`,
        });
        // Move the selection mark instead of rebuilding the grid: a full rebuild
        // would destroy this button inside its own click handler.
        cell.connect('clicked', () => {
            this._cells.get(this._sel.bs)?.remove_style_class_name('miti-selected');
            cell.add_style_class_name('miti-selected');
            this._sel = day;
            this._renderDetails();
        });
        this._cells.set(day.bs, cell);
        return cell;
    }
});

export default class MitiExtension extends Extension {
    enable() {
        this._indicator = new Indicator();
        Main.panel.addToStatusArea(this.uuid, this._indicator);
    }

    disable() {
        this._indicator.destroy();
        this._indicator = null;
    }
}
