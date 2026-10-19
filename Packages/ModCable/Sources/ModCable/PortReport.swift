import Foundation
import WhatCableCore

/// Structured, UI-ready version of what WhatCable's CLI prints per port (`TextFormatter.renderPort`),
/// built from the same Core diagnostics so wording and verdicts match WhatCable exactly.
struct PortReport: Identifiable, Equatable {
    struct Verdict: Equatable {
        let title: String
        let summary: String
        let detail: String
        let isWarning: Bool
    }

    struct Group: Equatable {
        let header: String
        let subtitle: String?
        let lines: [String]
    }

    struct TreeRow: Equatable {
        let label: String
        let depth: Int
    }

    struct Flag: Equatable {
        let title: String
        let detail: String
        let isWarning: Bool
    }

    let id: String
    let name: String
    let isConnected: Bool
    let headline: String
    let subtitle: String
    let groups: [Group]
    let verdicts: [Verdict]
    let thunderboltFabric: [TreeRow]
    let tunnels: [String]
    let connectedDevices: [TreeRow]
    let trustFlags: [Flag]

    var hasWarning: Bool {
        verdicts.contains(where: \.isWarning) || trustFlags.contains(where: \.isWarning)
    }

    static func build(from snapshot: CableSnapshot) -> [PortReport] {
        let context = CableSnapshotContext(snapshot: snapshot)
        return context.portContexts.map { build($0, context: context) }
    }

    private static func build(_ portContext: CableSnapshotContext.PortContext, context: CableSnapshotContext) -> PortReport {
        let port = portContext.port
        let switches = context.thunderboltSwitches
        let summary = PortSummary(
            port: port,
            sources: portContext.portSources,
            identities: portContext.portIdentities,
            devices: portContext.matchedDevices,
            thunderboltSwitches: switches,
            federatedIdentities: context.federatedIdentities,
            usb3Transports: portContext.portUSB3,
            trmTransports: portContext.portTRM,
            cioCapability: portContext.portCIO,
            accessoryIdentity: portContext.portAccessory,
            chargerWattageSource: portContext.chargerWattageSource,
            batteryFullyCharged: context.batteryFullyCharged,
            batteryIsCharging: context.batteryIsCharging,
            batteryChargeState: context.batteryChargeState,
            adapter: context.adapter
        )

        var verdicts: [Verdict] = []
        if let charging = ChargingDiagnostic(
            port: port, sources: portContext.portSources, identities: portContext.portIdentities,
            adapter: context.adapter, wattageSource: portContext.chargerWattageSource,
            batteryFullyCharged: context.batteryFullyCharged, batteryIsCharging: context.batteryIsCharging,
            batteryChargeState: context.batteryChargeState,
            anotherPortActivelyCharging: portContext.anotherPortActivelyCharging,
            federatedIdentities: context.federatedIdentities
        ) {
            verdicts.append(Verdict(title: "충전", summary: charging.summary, detail: charging.detail, isWarning: charging.isWarning))
        }
        if let data = DataLinkDiagnostic(
            port: port, identities: portContext.portIdentities, devices: portContext.matchedDevices,
            usb3Transports: portContext.portUSB3, cio: portContext.portCIO, thunderboltSwitches: switches
        ) {
            verdicts.append(Verdict(title: "데이터", summary: data.summary, detail: data.detail, isWarning: data.isWarning))
        }
        for displayPort in portContext.portDisplayPorts {
            guard let display = DisplayDiagnostic(dp: displayPort, cable: portContext.cableEmarker, port: port) else { continue }
            let detail = ([display.detail] + display.statementReceipts()).joined(separator: "\n")
            verdicts.append(Verdict(title: "디스플레이", summary: display.summary, detail: detail, isWarning: display.isWarning))
        }

        var fabric: [TreeRow] = []
        var tunnels: [String] = []
        if let socketID = ThunderboltTopology.socketID(for: port),
           let root = ThunderboltTopology.hostRoot(forSocketID: socketID, in: switches) {
            fabric = ThunderboltTopology.flatten(ThunderboltTopology.tree(from: root, in: switches)).map { node in
                let name = ThunderboltLabels.deviceName(for: node.sw)
                let link = ThunderboltTopology.connectionLanePort(node.sw, in: switches)
                    .flatMap { ThunderboltLabels.linkLabel(for: $0, on: node.sw) }
                return TreeRow(label: link.map { "\(name) - \($0)" } ?? name, depth: node.depth)
            }
            tunnels = ActiveTunnelPresentation.lines(
                tunnels: ThunderboltTopology.tunnels(from: root, in: switches),
                switches: switches,
                bundle: _coreLocalizedBundle
            )
        }

        let devices = ConnectedDeviceTree.rows(
            devices: portContext.matchedDevices,
            tunnelledDevices: portContext.structurallyScopedTunnelledDevices,
            port: port,
            thunderboltSwitches: switches,
            displayPorts: portContext.portDisplayPorts,
            cioCapability: portContext.portCIO
        ).map { TreeRow(label: $0.label, depth: $0.depth) }

        var flags: [Flag] = []
        if let cable = portContext.cableEmarker {
            let partner = portContext.portIdentities.first { $0.endpoint == .sop }
            flags = CableTrustReport(identity: cable, partner: partner).flags.map {
                Flag(title: $0.title, detail: $0.detail, isWarning: $0.severity == .warning)
            }
        }

        return PortReport(
            id: port.serviceName,
            name: port.portDescription ?? port.serviceName,
            isConnected: summary.status != .empty,
            headline: summary.headline,
            subtitle: summary.subtitle,
            groups: summary.groups.map { Group(header: $0.header, subtitle: $0.subtitle, lines: $0.lines) },
            verdicts: verdicts,
            thunderboltFabric: fabric,
            tunnels: tunnels,
            connectedDevices: devices,
            trustFlags: flags
        )
    }
}

/// One-line popover summary, e.g. "1개 연결 · 90W ⚠︎".
struct CableSummary: Equatable {
    let connectedCount: Int
    let chargingWatts: Int?
    let hasWarning: Bool

    init(reports: [PortReport], chargingWatts: Int?) {
        connectedCount = reports.filter(\.isConnected).count
        self.chargingWatts = chargingWatts
        hasWarning = reports.contains(where: \.hasWarning)
    }

    var text: String {
        guard connectedCount > 0 else { return "연결 없음" }
        var parts = ["\(connectedCount)개 연결"]
        if let chargingWatts { parts.append("\(chargingWatts)W") }
        return parts.joined(separator: " · ")
    }

    /// Highest negotiated charger wattage across ports, from the Core charging diagnostics.
    static func chargingWatts(from snapshot: CableSnapshot) -> Int? {
        let context = CableSnapshotContext(snapshot: snapshot)
        return context.portContexts.compactMap { portContext in
            ChargingDiagnostic(
                port: portContext.port, sources: portContext.portSources, identities: portContext.portIdentities,
                adapter: context.adapter, wattageSource: portContext.chargerWattageSource,
                batteryFullyCharged: context.batteryFullyCharged, batteryIsCharging: context.batteryIsCharging,
                batteryChargeState: context.batteryChargeState,
                anotherPortActivelyCharging: portContext.anotherPortActivelyCharging,
                federatedIdentities: context.federatedIdentities
            )?.chargerW
        }.max()
    }
}
