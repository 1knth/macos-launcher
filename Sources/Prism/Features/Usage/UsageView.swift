import AppKit
import SwiftUI
import PrismCore

struct UsageView: View {
    @ObservedObject private var model = UsageModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subscription limits")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Spacer()
                    if model.loading { ProgressView().controlSize(.small) }
                    Button { model.refresh(); model.refreshTokens(force: true) } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                        .buttonStyle(.borderless)
                        .disabled(model.loading)
                        .help("Refresh usage for both providers")
                }
                HStack(alignment: .top, spacing: 16) {
                    ForEach(UsageProvider.allCases) { provider in
                        providerPanel(provider)
                    }
                }
                TokenCalendar(days: model.tokenDays, loading: model.loadingTokens)

            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            model.refreshTokens()
            // The panel hides without removing this view, so only poll while it's on screen.
            repeat {
                if AppServices.shared.launcher?.isVisible == true { model.refreshIfStale() }
            } while (try? await Task.sleep(for: .seconds(15))) != nil
        }
    }

    private func providerPanel(_ provider: UsageProvider) -> some View {
        let result = model.results[provider]
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: provider == .claude ? "asterisk" : "circle.hexagongrid.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(provider == .claude ? Color.purple : Color.teal)
                    .frame(width: 36, height: 36)
                    .background((provider == .claude ? Color.purple : Color.teal).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                Text(provider == .claude ? "Claude" : "Codex")
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
                Link(destination: provider.dashboard) {
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary).padding(6)
                }.help("Open usage dashboard")
            }
            if let result, !result.windows.isEmpty {
                ForEach(result.windows) { window in
                    UsageWindowRow(window: window, accent: provider == .claude ? .purple : .teal)
                }
            }
            if let error = result?.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(result?.needsKeychainAccess == true ? "Access needed" : result?.windows.isEmpty == false ? "Couldn’t update" : "Usage unavailable")
                        .font(.system(size: 12, weight: .medium))
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if result?.needsSignIn == true, provider == .claude {
                        Button {
                            Paster.copy("claude auth login")
                            AppServices.shared.launcher?.state.flash("Copied sign-in command", symbol: "doc.on.doc")
                        } label: {
                            Label("Copy sign-in command", systemImage: "doc.on.doc")
                        }
                    }
                    if result?.needsKeychainAccess == true {
                        Button("Allow Keychain Access…") { model.refresh(allowKeychainPrompt: true) }
                            .disabled(model.loading)
                    }
                }
            } else if result?.windows.isEmpty != false {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Fetching usage…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
            }
            Hairline()
            HStack {
                Circle().fill(result?.error == nil ? Color.secondary.opacity(0.5) : Color.orange)
                    .frame(width: 4, height: 4)
                if let updated = result?.updated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 10))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct UsageWindowRow: View {
    let window: UsageWindow
    let accent: Color

    private var tint: Color {
        window.usedPercent >= 100 ? .red : window.usedPercent >= 90 ? .orange : accent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 6)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(window.usedPercent, specifier: "%.0f")%")
                        .font(.system(size: 25, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("used").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .foregroundStyle(tint)
            }
            GeometryReader { geometry in
                Capsule().fill(Color.primary.opacity(0.08))
                    .overlay(alignment: .leading) {
                        Capsule().fill(tint)
                            .frame(width: geometry.size.width * min(max(window.usedPercent, 0), 100) / 100)
                    }
            }
                .frame(height: 5)
                .accessibilityLabel(window.title)
                .accessibilityValue("\(window.usedPercent, specifier: "%.0f") percent used")
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if let reset = window.resetsAt {
                    if reset > context.date {
                        Text("Resets in \(UsageLimits.resetCountdown(until: reset, now: context.date))")
                            .help(reset.formatted(date: .complete, time: .shortened))
                    } else {
                        Text("Reset time reached · Refresh to update")
                    }
                } else {
                    Text("Reset time unavailable")
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

extension Calendar {
    /// First day shown in the token calendar: the start of the week 15 weeks ago, so columns are whole weeks.
    var tokenCalendarStart: Date {
        let week = dateInterval(of: .weekOfYear, for: Date())?.start ?? startOfDay(for: Date())
        return date(byAdding: .weekOfYear, value: -15, to: week) ?? week
    }
}

private struct TokenCalendar: View {
    let days: [TokenDay]
    let loading: Bool
    @State private var selected = Calendar.current.startOfDay(for: Date())
    @State private var source = "All"
    private let calendar = Calendar.current

    private func tokens(_ day: TokenDay?) -> Int {
        guard let day else { return 0 }
        switch source {
        case "Claude": return day.claude
        case "Codex": return day.codex
        case "Pi": return day.pi
        default: return day.total
        }
    }

    var body: some View {
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let today = calendar.startOfDay(for: Date())
        let start = calendar.tokenCalendarStart
        // Columns are weeks and rows are weekdays, oldest week first.
        let weeks = (0..<16).map { week in (0..<7).compactMap { calendar.date(byAdding: .day, value: week * 7 + $0, to: start) } }
        let peak = max(1, days.map { tokens($0) }.max() ?? 0)
        let day = byDate[selected]
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Token usage").font(.system(size: 14, weight: .semibold))
                if loading { ProgressView().controlSize(.small) }
                Spacer()
                Text("Last 16 weeks").foregroundStyle(.secondary)
                Text(days.reduce(0) { $0 + tokens($1) }, format: .number)
                    .fontWeight(.semibold).monospacedDigit()
                Text("tokens").foregroundStyle(.secondary)
            }
            Picker("Session source", selection: $source) {
                ForEach(["All", "Claude", "Codex", "Pi"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Text(start, format: .dateTime.month(.abbreviated).day())
                Spacer()
                Text(today, format: .dateTime.month(.abbreviated).day())
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(weeks, id: \.first) { week in
                    VStack(spacing: 5) {
                        ForEach(week, id: \.self) { date in
                            if date > today {
                                Color.clear.frame(height: 17)
                            } else {
                                cell(date, total: tokens(byDate[date]), peak: peak)
                            }
                        }
                    }
                }
            }
            HStack {
                Text(selected, format: .dateTime.month(.abbreviated).day()).fontWeight(.medium)
                Spacer()
                Text("\(tokens(day).formatted()) tokens").fontWeight(.semibold)
            }.monospacedDigit()
            HStack(spacing: 16) {
                Text("Claude Code: \((day?.claude ?? 0).formatted())")
                Text("Codex: \((day?.codex ?? 0).formatted())")
                Text("Pi: \((day?.pi ?? 0).formatted())")
            }.font(.system(size: 11)).monospacedDigit()
            Text("Local logs only. Pi is counted separately, including its Codex sessions. Totals include cached tokens; other devices and missing logs aren’t included. These counts don’t measure subscription limits.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .padding(14)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
    }

    private func cell(_ date: Date, total: Int, peak: Int) -> some View {
        Button { selected = date } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(total > 0 ? Color.accentColor.opacity(0.2 + 0.8 * sqrt(Double(total) / Double(peak))) : Color.primary.opacity(0.07))
                .frame(height: 17)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(date == selected ? Color.primary : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.formatted(date: .complete, time: .omitted)), \(total) locally recorded tokens")
        .help("\(date.formatted(date: .abbreviated, time: .omitted)): \(total.formatted()) tokens")
    }
}
