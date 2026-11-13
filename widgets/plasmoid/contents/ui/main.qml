import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.plasma5support as P5Support
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root

    // Parsed `miti today -j`: today's day object.
    property var d: ({})
    // Parsed `miti month Y-M`: the month on screen, `days` holds one day object each.
    property var m: ({})
    // The day object whose details are shown.
    property var sel: null
    // BS date a conversion asked for; selected once its month has loaded.
    property string want: ""
    property string convError: ""

    readonly property string miti: 'PATH="$HOME/.local/bin:$PATH" miti '
    readonly property string title: d.bs ? `${d.month_np} ${d.day_np}` : "…"
    readonly property string full: d.bs ? `${d.year_np} ${d.month_np} ${d.day_np}, ${d.weekday_np}` : "miti not found"
    readonly property string detail: d.bs ? [d.tithi, d.event_np, d.ad].filter(s => s).join("\n") : "run: miti install"

    // The BS date rolls over at Nepal midnight (UTC+5:45).
    function nepalDay() {
        return new Date(Date.now() + 20700000).toISOString().slice(0, 10);
    }

    // Month arithmetic wraps the year; a month outside the table fails in miti and the view stays put.
    function show(year, month) {
        const n = year * 12 + month - 1;
        exec.connectSource(`${miti} month ${Math.floor(n / 12)}-${n % 12 + 1}`);
    }

    // "Oct – Nov 2026" for the AD days the shown month spans.
    function adRange() {
        const names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        const a = m.days[0].ad.split("-"), b = m.days[m.days.length - 1].ad.split("-");
        return `${names[a[1] - 1]}${a[0] === b[0] ? "" : " " + a[0]} – ${names[b[1] - 1]} ${b[0]}`;
    }

    // Converter: jump to the typed date; the details pane then shows it in both calendars.
    // The text goes into a shell command, so nothing but digits and dashes may pass.
    function convert(command, typed) {
        const text = typed.trim().replace(/[\/.]/g, "-"); // 2026/11/13 and 2026.11.13 work too
        if (/^\d{1,4}-\d{1,2}-\d{1,2}$/.test(text))
            exec.connectSource(`${miti} ${command} ${text} -j`);
        else
            convError = "Type a date as YYYY-MM-DD";
    }

    preferredRepresentation: compactRepresentation
    toolTipMainText: full
    toolTipSubText: detail

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source);
            const converting = / (ad2bs|bs2ad) /.test(source);
            if (data["exit code"] !== 0) {
                if (converting)
                    root.convError = "No such date in the table (BS 1901–2199)";
                return;
            }
            const out = JSON.parse(data.stdout);
            if (out.days) {
                root.m = out;
                root.sel = out.days.find(x => x.bs === root.want) || out.days.find(x => x.bs === root.d.bs) || out.days[0];
                root.want = "";
            } else if (converting) {
                root.convError = "";
                root.want = out.bs;
                root.show(out.year, out.month);
            } else {
                root.d = out;
                root.show(out.year, out.month);
            }
        }
    }

    // Check the clock every minute instead of one long timer: survives suspend
    // and clock changes, and retries if miti was missing. Spawns only on a new day.
    Timer {
        interval: 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (root.d.ad !== root.nepalDay())
            exec.connectSource(root.miti + "today -j")
    }

    // Popup closed for 10 s: back to today, so the next open does not show a stale pick.
    Timer {
        interval: 10000
        running: !root.expanded && root.d.bs !== undefined && root.sel?.bs !== root.d.bs
        onTriggered: root.show(root.d.year, root.d.month)
    }

    compactRepresentation: MouseArea {
        Layout.minimumWidth: label.implicitWidth + Kirigami.Units.smallSpacing * 2
        onClicked: root.expanded = !root.expanded

        PlasmaComponents.Label {
            id: label
            anchors.centerIn: parent
            text: root.title
            color: root.d.holiday ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 26
        Layout.minimumHeight: implicitHeight
        Layout.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            ColumnLayout {
                spacing: 0
                Kirigami.Heading {
                    text: root.m.days ? `${root.m.month_np} ${root.m.year_np}` : root.full
                }
                PlasmaComponents.Label {
                    opacity: 0.7
                    text: root.m.days ? `${root.m.month_en} ${root.m.year} · ${root.adRange()}` : root.detail
                }
            }
            Item {
                Layout.fillWidth: true
            }
            PlasmaComponents.ToolButton {
                icon.name: "go-previous"
                Accessible.name: "Previous month"
                onClicked: root.show(root.m.year, root.m.month - 1)
            }
            PlasmaComponents.ToolButton {
                text: "आज"
                Accessible.name: "Today"
                onClicked: root.show(root.d.year, root.d.month)
            }
            PlasmaComponents.ToolButton {
                icon.name: "go-next"
                Accessible.name: "Next month"
                onClicked: root.show(root.m.year, root.m.month + 1)
            }
        }

        GridLayout {
            columns: 7
            rowSpacing: 2
            columnSpacing: 2
            uniformCellWidths: true

            Repeater {
                model: ["आइत", "सोम", "मंगल", "बुध", "बिही", "शुक्र", "शनि"]
                PlasmaComponents.Label {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: index === 6 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    opacity: 0.8
                }
            }

            Repeater {
                // Blank cells pad the first week up to day 1's weekday.
                model: root.m.days ? Array(root.m.days[0].weekday).fill(null).concat(root.m.days) : []

                Rectangle {
                    id: cell
                    required property var modelData
                    readonly property var day: modelData || ({})
                    readonly property bool isToday: day.bs !== undefined && day.bs === root.d.bs
                    readonly property bool isSel: root.sel !== null && day.bs === root.sel.bs
                    readonly property color ink: isToday ? Kirigami.Theme.highlightedTextColor
                        : day.holiday || day.weekday === 6 ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor

                    Layout.fillWidth: true
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 3.2
                    visible: modelData !== null
                    radius: Kirigami.Units.cornerRadius
                    color: isToday ? Kirigami.Theme.highlightColor
                        : hover.hovered ? Qt.alpha(Kirigami.Theme.textColor, 0.1) : "transparent"
                    border.width: isSel ? 2 : 0
                    border.color: isToday ? Kirigami.Theme.textColor : Kirigami.Theme.highlightColor

                    Accessible.role: Accessible.Button
                    Accessible.name: `${cell.day.day} ${root.m.month_en}, ${cell.day.tithi} ${cell.day.event_en}`

                    HoverHandler {
                        id: hover
                    }
                    TapHandler {
                        onTapped: root.sel = cell.modelData
                    }
                    // Dot: the day has an event.
                    Rectangle {
                        visible: !!cell.day.event_np
                        anchors { left: parent.left; top: parent.top; margins: 5 }
                        width: 5
                        height: 5
                        radius: 3
                        color: cell.ink
                    }
                    PlasmaComponents.Label {
                        anchors { right: parent.right; top: parent.top; rightMargin: 4; topMargin: 1 }
                        text: cell.day.ad ? +cell.day.ad.slice(8) : ""
                        font: Kirigami.Theme.smallFont
                        color: cell.ink
                        opacity: 0.7
                    }
                    PlasmaComponents.Label {
                        anchors.centerIn: parent
                        text: cell.day.day_np || ""
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.4
                        color: cell.ink
                    }
                    PlasmaComponents.Label {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 1 }
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: cell.day.tithi || ""
                        font: Kirigami.Theme.smallFont
                        color: cell.ink
                        opacity: 0.7
                    }
                }
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // Details of the selected day. Fixed minimum height so the popup does not jump.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: Kirigami.Units.gridUnit * 7
            visible: root.sel !== null
            spacing: 2

            RowLayout {
                Kirigami.Heading {
                    level: 3
                    text: root.sel ? `${root.sel.year_np} ${root.sel.month_np} ${root.sel.day_np}, ${root.sel.weekday_np}` : ""
                }
                PlasmaComponents.Label {
                    visible: !!root.sel?.holiday
                    text: "बिदा"
                    color: Kirigami.Theme.negativeTextColor
                }
            }
            PlasmaComponents.Label {
                opacity: 0.7
                text: root.sel ? `${root.sel.weekday_en}, ${root.sel.month_en} ${root.sel.day}, ${root.sel.year} BS · ${root.sel.ad} AD` : ""
            }
            PlasmaComponents.Label {
                visible: !!root.sel?.tithi
                text: `तिथि: ${root.sel?.tithi}`
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                visible: text !== ""
                wrapMode: Text.Wrap
                // English titles; Nepali only when the patro has no English one.
                text: (root.sel?.event_en || root.sel?.event_np || "").split(" / ").join("\n")
            }
            Item {
                Layout.fillHeight: true
            }
        }

        Kirigami.Separator {
            Layout.fillWidth: true
        }

        // Converter. Enter converts AD to BS.
        RowLayout {
            PlasmaComponents.TextField {
                id: convInput
                Layout.fillWidth: true
                placeholderText: "Go to date: YYYY-MM-DD"
                Accessible.name: "Date to convert, year-month-day"
                onAccepted: root.convert("ad2bs", text)
                onTextEdited: root.convError = ""
            }
            PlasmaComponents.Button {
                text: "AD → BS"
                onClicked: root.convert("ad2bs", convInput.text)
            }
            PlasmaComponents.Button {
                text: "BS → AD"
                onClicked: root.convert("bs2ad", convInput.text)
            }
        }
        PlasmaComponents.Label {
            visible: root.convError !== ""
            text: root.convError
            color: Kirigami.Theme.negativeTextColor
        }
    }
}
