import SwiftUI
import UIKit
import VLESSKitTunnel

struct ContentView: View {
    @State private var model = DemoModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Header()
                ProtocolPicker(selection: $model.proto, locked: model.status != .off)
                ConnectButton(model: model)
                ServerList(model: model)
                TrafficStats(traffic: model.traffic)
                LogPanel(lines: model.log)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Palette.screen.ignoresSafeArea())
        .foregroundStyle(Palette.text)
        .preferredColorScheme(.dark)
    }
}

private struct Header: View {
    var body: some View {
        HStack {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Palette.accentDim)
                    .frame(width: 36, height: 36)
                    .overlay(LogoMark().stroke(Palette.accent, style: .init(lineWidth: 2.2, lineCap: .round, lineJoin: .round)).frame(width: 20, height: 20))
                VStack(alignment: .leading, spacing: 0) {
                    Text("VLESSKit").font(.system(size: 20, weight: .bold)).tracking(-0.3)
                    Text("framework demo").font(.mono(11)).foregroundStyle(Palette.muted)
                }
            }
            Spacer()
            Text("v0.2.0")
                .font(.mono(11))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(Capsule().stroke(Palette.line))
        }
    }
}

/// The "V" from the design's 24×24 logo.
private struct LogoMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 4 * s, y: 5 * s))
        path.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
        path.addLine(to: CGPoint(x: 20 * s, y: 5 * s))
        path.move(to: CGPoint(x: 8.5 * s, y: 5 * s))
        path.addLine(to: CGPoint(x: 15.5 * s, y: 5 * s))
        return path
    }
}

private struct ProtocolPicker: View {
    @Binding var selection: ProxyLink.Proto
    let locked: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach([ProxyLink.Proto.vless, .shadowsocks, .hysteria2], id: \.self) { proto in
                Segment(title: proto == .vless ? "VLESS" : proto.rawValue, active: selection == proto) {
                    guard !locked else { return }
                    withAnimation(.easeOut(duration: 0.2)) { selection = proto }
                }
            }
        }
        .padding(3)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
        .opacity(locked ? 0.6 : 1)
    }
}

private struct Segment: View {
    let title: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(active ? Palette.text : Palette.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(active ? Palette.card2 : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }
}

private struct ConnectButton: View {
    let model: DemoModel
    @State private var spin = false

    private var tint: Color {
        switch model.status {
        case .off: Palette.muted
        case .connecting: Palette.warn
        case .on: Palette.accent
        }
    }

    private var label: String {
        switch model.status {
        case .off: "Disconnected"
        case .connecting: "Connecting"
        case .on: "Protected"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: model.toggle) {
                ZStack {
                    Circle().stroke(Palette.line, lineWidth: 14)
                    Circle()
                        .trim(from: 0, to: model.status == .connecting ? 0.3 : (model.status == .on ? 1 : 0))
                        .stroke(tint, style: .init(lineWidth: 14))
                        .rotationEffect(.degrees(spin ? 270 : -90))
                    Circle().fill(Palette.ringCore).padding(7)
                    VStack(spacing: 8) {
                        PowerIcon().stroke(tint, style: .init(lineWidth: 2, lineCap: .round)).frame(width: 40, height: 40)
                        Text(label.uppercased())
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 170, height: 170)
                .padding(7)
                .shadow(color: model.status == .on ? Palette.accent.opacity(0.18) : .clear, radius: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .onChange(of: model.status) { _, status in
                if status == .connecting {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) { spin = false }
                }
            }
            .animation(.easeInOut(duration: 0.4), value: model.status)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(elapsed(at: context.date))
                    .font(.mono(26, .medium))
                    .tracking(1)
                    .padding(.top, 14)
            }
            Text(model.ipLine)
                .font(.mono(12))
                .foregroundStyle(Palette.muted)
                .padding(.top, 4)
        }
        .padding(.top, 8)
    }

    private func elapsed(at now: Date) -> String {
        let seconds = model.connectedSince.map { Int(now.timeIntervalSince($0)) } ?? 0
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}

/// The design's power glyph on a 24×24 grid.
private struct PowerIcon: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 24
        var path = Path()
        path.move(to: CGPoint(x: 12 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 12 * s, y: 12 * s))
        path.move(to: CGPoint(x: 6.3 * s, y: 7.2 * s))
        path.addArc(center: CGPoint(x: 12 * s, y: 13 * s), radius: 8.1 * s,
                    startAngle: .degrees(225), endAngle: .degrees(315), clockwise: true)
        return path
    }
}

private struct ServerList: View {
    let model: DemoModel

    var body: some View {
        VStack(spacing: 10) {
            ForEach(model.visibleServers) { server in
                ServerCard(server: server, latency: model.latency[server.id] ?? nil, measured: model.latency[server.id] != nil,
                           selected: server == model.selected)
                    .onTapGesture { if model.status == .off { model.selected = server } }
                    .contextMenu {
                        Button("Copy link") { UIPasteboard.general.string = server.link }
                        Button("Remove", role: .destructive) { model.remove(server) }
                    }
            }
            Button {
                model.paste(UIPasteboard.general.string)
            } label: {
                Label(model.visibleServers.isEmpty ? "Paste a \(model.proto.rawValue.lowercased()) link" : "Paste link", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line, style: .init(lineWidth: 1, dash: [4, 4])))
            }
            .buttonStyle(.plain)
            .disabled(model.status != .off)
        }
    }
}

private struct ServerCard: View {
    let server: DemoServer
    let latency: Int?
    let measured: Bool
    let selected: Bool

    private var failed: Bool { latency == nil && measured }

    var body: some View {
        HStack(spacing: 12) {
            Text(server.flag)
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                Text(server.details).font(.mono(12)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Text(latency.map { "\($0) ms" } ?? (measured ? "timeout" : "…"))
                .font(.mono(12))
                .foregroundStyle(failed ? Palette.off : Palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(failed ? Palette.off.opacity(0.14) : Palette.accentDim, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Palette.accent.opacity(0.6) : Palette.line))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct TrafficStats: View {
    let traffic: XrayTraffic

    var body: some View {
        HStack(spacing: 10) {
            stat("↓ Download", traffic.downlink)
            stat("↑ Upload", traffic.uplink)
        }
    }

    private func stat(_ title: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 11)).tracking(0.8).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                let mb = bytes >= 1_048_576
                Text(String(format: "%.1f", Double(bytes) / (mb ? 1_048_576 : 1024))).font(.mono(19, .medium))
                Text(mb ? "MB" : "KB").font(.mono(12)).foregroundStyle(Palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
    }
}

private struct LogPanel: View {
    let lines: [LogLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines) { line in
                Text(line.text)
                    .font(.mono(10.5))
                    .lineLimit(1)
                    .foregroundStyle(line.kind == .ok ? Palette.accent : line.kind == .warn ? Palette.warn : Palette.muted)
                    .frame(height: 18, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
    }
}

#Preview {
    ContentView()
}
