import AppKit

@main
enum PanelPlacementChecks {
    static func main() {
        let panel = NSSize(width: 348, height: 480)
        let main = NSRect(x: 0, y: 72, width: 1512, height: 886)
        check("居中并贴着按钮下边",
              button: NSRect(x: 720, y: 944, width: 64, height: 26), visible: main, size: panel,
              expected: NSRect(x: 578, y: 458, width: 348, height: 480))
        check("屏幕右侧留出边距",
              button: NSRect(x: 1444, y: 958, width: 64, height: 24), visible: main, size: panel,
              expected: NSRect(x: 1158, y: 472, width: 348, height: 480))
        check("避开左侧 Dock",
              button: NSRect(x: 18, y: 958, width: 64, height: 24),
              visible: NSRect(x: 82, y: 0, width: 1430, height: 958), size: panel,
              expected: NSRect(x: 88, y: 472, width: 348, height: 480))
        check("避开右侧 Dock",
              button: NSRect(x: 1444, y: 958, width: 64, height: 24),
              visible: NSRect(x: 0, y: 0, width: 1430, height: 958), size: panel,
              expected: NSRect(x: 1076, y: 472, width: 348, height: 480))
        check("外接屏在主屏左下方",
              button: NSRect(x: -1890, y: 933, width: 64, height: 26),
              visible: NSRect(x: -1920, y: -96, width: 1920, height: 1030), size: panel,
              expected: NSRect(x: -1914, y: 447, width: 348, height: 480))
        check("外接屏在主屏右上方且面板顶边不越过可用区",
              button: NSRect(x: 2280, y: 1280, width: 64, height: 26),
              visible: NSRect(x: 1512, y: 100, width: 1680, height: 1175), size: panel, gap: 8,
              expected: NSRect(x: 2138, y: 787, width: 348, height: 480))
        check("窄屏和较高内容仍留出边距",
              button: NSRect(x: 340, y: 295, width: 40, height: 25),
              visible: NSRect(x: 0, y: 50, width: 380, height: 240),
              size: NSSize(width: 420, height: 500),
              expected: NSRect(x: 6, y: 56, width: 368, height: 228))
        print("面板定位通过 7 项检查")
    }

    private static func check(_ name: String, button: NSRect, visible: NSRect, size: NSSize, gap: CGFloat = 6,
                              expected: NSRect) {
        let actual = anchoredWeatherPanelFrame(button: button, visibleFrame: visible, panelSize: size, gap: gap)
        precondition(actual == expected, "\(name)未通过，预期 \(expected)，实际 \(actual)")
    }
}
