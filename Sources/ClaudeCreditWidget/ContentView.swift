import SwiftUI

struct ContentView: View {
    @ObservedObject var store: CreditStore
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = store.balance {
                balanceSection(b)
            } else if let err = store.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(err)
                        .font(.callout)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Sign in with Chrome") {
                        Task { _ = await store.signInWithChrome() }
                    }
                    .disabled(store.isImporting)
                }
            } else {
                ProgressView().controlSize(.small)
            }

            Divider()

            HStack {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
                Spacer()
                Button("Settings…") { onOpenSettings() }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 280)
    }

    @ViewBuilder
    private func balanceSection(_ b: CreditResponse) -> some View {
        Text(String(format: "$%.2f", b.balanceUSD))
            .font(.system(size: 36, weight: .semibold, design: .rounded))
            .monospacedDigit()
        Text("Remaining balance")
            .font(.caption)
            .foregroundColor(.secondary)

        Divider()

        HStack(alignment: .top, spacing: 6) {
            Image(systemName: b.autoReloadSettings.enabled ? "arrow.triangle.2.circlepath.circle.fill" : "pause.circle")
                .foregroundColor(b.autoReloadSettings.enabled ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                if b.autoReloadSettings.enabled {
                    Text("Auto-reload enabled")
                        .font(.caption)
                    Text(String(format: "Reload to $%.0f when below $%.0f",
                                b.autoReloadSettings.reloadToUSD,
                                b.autoReloadSettings.thresholdUSD))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Auto-reload off").font(.caption)
                }
            }
        }

        Divider()

        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                store.showStats.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: store.showStats ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                Text("Usage stats").font(.caption.bold())
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if store.showStats {
            statsSection
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if let updated = store.lastUpdated {
            Text("Updated \(Self.relativeFormatter.localizedString(for: updated, relativeTo: Date()))")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let today = store.dailySpendUSD {
                statRow(label: "Used today", value: String(format: "$%.2f", today))
            }
            if let s = store.spend {
                let value: String = {
                    if let cap = store.rateLimits?.spendThresholdUSD {
                        return String(format: "$%.2f / $%.0f", s.spentUSD, cap)
                    }
                    return String(format: "$%.2f", s.spentUSD)
                }()
                statRow(label: "This period", value: value)
                statRow(
                    label: "Resets",
                    value: s.resetsAt.formatted(.dateTime.month(.abbreviated).day())
                )
            }
            if let rl = store.rateLimits {
                statRow(label: "Tier", value: rl.tierLabel)
            }
            if store.spend == nil && store.rateLimits == nil {
                Text("Loading stats…").font(.caption2).foregroundColor(.secondary)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: store.showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Advanced").font(.caption2.bold())
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            if store.showAdvanced {
                advancedSection
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let avg = store.avgDailyUSD {
                statRow(label: "Avg / day this period", value: String(format: "$%.2f", avg))
            }
            if let days = store.daysRemaining {
                let txt = days >= 999
                    ? "999+ days"
                    : (days >= 1 ? String(format: "%.0f days", days) : String(format: "%.1f days", days))
                statRow(label: "Est. credit runway", value: txt)
            }
            if let rl = store.rateLimits, let cap = rl.spendThresholdUSD,
               let s = store.spend {
                let pct = min(100, max(0, Int((s.spentUSD / cap) * 100)))
                statRow(label: "Tier-cap usage", value: "\(pct)%")
            }
            if let baseline = store.dailyBaselineDate {
                Text("Today's spend tracked since \(baseline.formatted(.dateTime.hour().minute()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding(.leading, 12)
    }

    @ViewBuilder
    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}
