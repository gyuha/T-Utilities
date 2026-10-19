import AppKit
import SwiftUI

/// Native menu: one item per port; connected ports open a submenu holding the full detail card.
@MainActor
enum CableMenu {
    static let detailWidth: CGFloat = 380

    static func make(reports: [PortReport]) -> NSMenu {
        let menu = NSMenu()
        if reports.isEmpty {
            let item = NSMenuItem(title: "포트 정보를 읽는 중…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        for report in reports {
            let item = NSMenuItem(title: "\(report.name) · \(report.headline)", action: nil, keyEquivalent: "")
            if report.hasWarning {
                item.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "경고")
            }
            if report.isConnected {
                let submenu = NSMenu()
                submenu.addItem(detailItem(for: report))
                item.submenu = submenu
            } else {
                item.isEnabled = false
            }
            menu.addItem(item)
        }
        return menu
    }

    private static func detailItem(for report: PortReport) -> NSMenuItem {
        let hosting = NSHostingView(rootView: PortDetailView(report: report).frame(width: detailWidth))
        hosting.frame = NSRect(origin: .zero, size: hosting.fittingSize)
        let item = NSMenuItem()
        item.view = hosting
        return item
    }
}

/// Mirrors the sections of WhatCable's per-port report.
struct PortDetailView: View {
    let report: PortReport

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(report.headline).font(.headline)
                if !report.subtitle.isEmpty {
                    Text(report.subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(report.verdicts, id: \.title) { verdict in
                VStack(alignment: .leading, spacing: 2) {
                    Label {
                        Text("\(verdict.title): \(verdict.summary)").fontWeight(.medium)
                    } icon: {
                        Image(systemName: verdict.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(verdict.isWarning ? .orange : .green)
                    }
                    Text(verdict.detail).font(.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(report.groups, id: \.header) { group in
                section(group.header) {
                    if let subtitle = group.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(group.lines, id: \.self) { Text("• \($0)").font(.callout) }
                }
            }

            if !report.thunderboltFabric.isEmpty {
                section("Thunderbolt 토폴로지") { tree(report.thunderboltFabric) }
            }
            if !report.tunnels.isEmpty {
                section("활성 터널") {
                    ForEach(report.tunnels, id: \.self) { Text("• \($0)").font(.callout) }
                }
            }
            if !report.connectedDevices.isEmpty {
                section("연결된 장치") { tree(report.connectedDevices) }
            }
            if !report.trustFlags.isEmpty {
                section("케이블 신뢰 신호") {
                    ForEach(report.trustFlags, id: \.title) { flag in
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(flag.isWarning ? "⚠︎" : "•") \(flag.title)").font(.callout)
                            Text(flag.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(12)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
        }
    }

    private func tree(_ rows: [PortReport.TreeRow]) -> some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
            Text("\(String(repeating: "   ", count: row.depth))\(row.depth > 0 ? "↳" : "•") \(row.label)")
                .font(.callout)
        }
    }
}
