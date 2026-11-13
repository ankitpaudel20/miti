// Nepali date in the macOS menu bar. All data comes from the `miti` CLI:
// `miti today -j` once per Nepal day, `miti month Y-M` once per month shown.
//
// Written without access to a Mac: it has never been compiled or run.

import AppKit
import SwiftUI

/// One day, as printed by `miti today -j`. Field names match the JSON keys.
struct Day: Decodable, Identifiable, Equatable {
    let bs, ad: String
    let year, month, day, weekday: Int
    let year_np, month_np, day_np, weekday_np, month_en, weekday_en, tithi: String
    let holiday: Bool
    let event_np, event_en: String

    var id: String { bs }
    var adDay: String { String(Int(ad.suffix(2)) ?? 0) }
    /// Saturdays and public holidays are drawn red.
    var red: Bool { holiday || weekday == 6 }
}

/// One month, as printed by `miti month Y-M`.
struct Month: Decodable {
    let year, month: Int
    let year_np, month_np, month_en: String
    let days: [Day]
}

@MainActor
final class Model: ObservableObject {
    @Published var today: Day?
    @Published var month: Month?
    @Published var selected: Day?
    @Published var convertError = ""
    private var timer: Timer?

    var title: String {
        guard let t = today else { return "नेपाली" }
        return "\(t.month_np) \(t.day_np)"
    }

    init() {
        refresh()
        // Poll the clock instead of one long timer: survives sleep and clock changes,
        // and retries if miti was missing. Spawns only on a new day.
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// The BS date rolls over at Nepal midnight (UTC+5:45).
    private static func nepalDay() -> String {
        let f = ISO8601DateFormatter() // formats in UTC
        f.formatOptions = [.withFullDate]
        return f.string(from: Date().addingTimeInterval(5 * 3600 + 45 * 60))
    }

    // shortcut: runs miti on the main thread (it exits in milliseconds); move off it if that ever stutters
    private static func run<T: Decodable>(_ args: [String]) -> T? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let places = ["\(home)/.local/bin/miti", "\(home)/.cargo/bin/miti", "/opt/homebrew/bin/miti", "/usr/local/bin/miti"]
        guard let bin = places.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: bin)
        process.arguments = args
        process.standardOutput = pipe
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func refresh() {
        guard today?.ad != Model.nepalDay() else { return }
        guard let d: Day = Model.run(["today", "-j"]) else { return }
        today = d
        show(year: d.year, month: d.month)
    }

    /// Month arithmetic wraps the year; a month outside the table fails in miti and the view stays put.
    /// `select`: BS date to select instead of today (from the converter).
    func show(year: Int, month: Int, select: String? = nil) {
        let n = year * 12 + month - 1
        guard let m: Month = Model.run(["month", "\(n / 12)-\(n % 12 + 1)"]) else { return }
        self.month = m
        selected = m.days.first { $0.bs == select } ?? m.days.first { $0.bs == today?.bs } ?? m.days.first
    }

    /// Converter: jump to the typed date; the details pane then shows it in both calendars.
    /// `command` is "ad2bs" or "bs2ad".
    func convert(_ command: String, _ text: String) {
        let date = text.trimmingCharacters(in: .whitespaces)
        guard let d: Day = Model.run([command, date, "-j"]) else {
            convertError = "No such date in the table (BS 1901–2199)"
            return
        }
        convertError = ""
        show(year: d.year, month: d.month, select: d.bs)
    }

    func showToday() {
        if let t = today { show(year: t.year, month: t.month) }
    }
}

struct DayCell: View {
    let day: Day
    let isToday: Bool
    let isSelected: Bool

    var body: some View {
        let ink: Color = isToday ? .white : (day.red ? .red : .primary)
        let ring: Color = !isSelected ? .clear : (isToday ? .white : .accentColor)
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Dot: the day has an event.
                Circle().frame(width: 4, height: 4).opacity(day.event_np.isEmpty ? 0 : 1)
                Spacer()
                Text(day.adDay).font(.caption2).opacity(0.7)
            }
            Text(day.day_np).font(.title3)
            Text(day.tithi.isEmpty ? " " : day.tithi).font(.caption2).lineLimit(1).opacity(0.7)
        }
        .foregroundColor(ink)
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(isToday ? Color.accentColor : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ring, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(day.day)) \(day.month_en), \(day.tithi) \(day.event_en)")
        .accessibilityAddTraits(.isButton)
    }
}

struct CalendarView: View {
    @ObservedObject var model: Model
    @State private var input = ""
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    private let weekdays = ["आइत", "सोम", "मंगल", "बुध", "बिही", "शुक्र", "शनि"]
    private let adMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let m = model.month, let sel = model.selected {
                header(m)
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        Text(weekdays[i]).font(.caption).foregroundColor(i == 6 ? .red : .secondary)
                    }
                    // Blank cells pad the first week up to day 1's weekday.
                    ForEach(0..<m.days[0].weekday, id: \.self) { _ in Color.clear }
                    ForEach(m.days) { day in
                        DayCell(day: day, isToday: day.bs == model.today?.bs, isSelected: day == sel)
                            .onTapGesture { model.selected = day }
                    }
                }
                Divider()
                details(sel)
                Divider()
                HStack {
                    TextField("Go to date: YYYY-MM-DD", text: $input)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.convert("ad2bs", input) } // Return converts AD to BS
                    Button("AD → BS") { model.convert("ad2bs", input) }
                    Button("BS → AD") { model.convert("bs2ad", input) }
                }
                if !model.convertError.isEmpty {
                    Text(model.convertError).foregroundColor(.red)
                }
            } else {
                Text("miti not found").font(.headline)
                Text("Build it, then run: miti install").foregroundColor(.secondary)
            }
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(12)
        .frame(width: 420)
        // Every open starts on today, never on a stale pick.
        .onAppear { model.showToday() }
    }

    private func header(_ m: Month) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("\(m.month_np) \(m.year_np)").font(.title2).bold()
                // String(Int): plain interpolation of an Int in Text adds a thousands separator.
                Text("\(m.month_en) \(String(m.year)) · \(adSpan(m))").foregroundColor(.secondary)
            }
            Spacer()
            Button { model.show(year: m.year, month: m.month - 1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Button("आज") { model.showToday() }
                .accessibilityLabel("Today")
            Button { model.show(year: m.year, month: m.month + 1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next month")
        }
        .buttonStyle(.borderless)
    }

    /// "Oct – Nov 2026" for the AD days the month spans.
    private func adSpan(_ m: Month) -> String {
        let a = m.days[0].ad.split(separator: "-"), b = m.days[m.days.count - 1].ad.split(separator: "-")
        let name = { (part: Substring) in adMonths[(Int(part) ?? 1) - 1] }
        return "\(name(a[1]))\(a[0] == b[0] ? "" : " \(a[0])") – \(name(b[1])) \(b[0])"
    }

    @ViewBuilder
    private func details(_ d: Day) -> some View {
        // English titles; Nepali only when the patro has no English one.
        let events = d.event_en.isEmpty ? d.event_np : d.event_en
        HStack {
            Text("\(d.year_np) \(d.month_np) \(d.day_np), \(d.weekday_np)").font(.headline)
            if d.holiday { Text("बिदा").foregroundColor(.red) }
        }
        Text("\(d.weekday_en), \(d.month_en) \(String(d.day)), \(String(d.year)) BS · \(d.ad) AD")
            .foregroundColor(.secondary)
        if !d.tithi.isEmpty { Text("तिथि: \(d.tithi)") }
        if !events.isEmpty {
            Text(events.replacingOccurrences(of: " / ", with: "\n")).fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu bar only, no Dock icon
    }
}

@main
struct MitiBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = Model()

    var body: some Scene {
        MenuBarExtra {
            CalendarView(model: model)
        } label: {
            Text(model.title)
        }
        .menuBarExtraStyle(.window)
    }
}
