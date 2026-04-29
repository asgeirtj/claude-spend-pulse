import Foundation
import SwiftUI
import Combine

@MainActor
final class CreditStore: ObservableObject {
    @Published var balance: CreditResponse?
    @Published var spend: SpendResponse?
    @Published var rateLimits: RateLimitsResponse?
    @Published var error: String?
    @Published var isLoading: Bool = false
    @Published var isImporting: Bool = false
    @Published var lastUpdated: Date?

    @AppStorage("orgId") var orgId: String = ""
    @AppStorage("refreshIntervalSeconds") var refreshIntervalSeconds: Int = 300
    @AppStorage("lastSignInTimestamp") var lastSignInTimestamp: Double = 0
    @AppStorage("showStats") var showStats: Bool = false
    @AppStorage("showAdvanced") var showAdvanced: Bool = false

    @AppStorage("dailyBaselineCents") private var dailyBaselineCents: Int = -1
    @AppStorage("dailyBaselineTimestamp") private var dailyBaselineTimestamp: Double = 0

    private let service = CreditService()
    private var timer: Timer?

    init() {
        scheduleTimer()
        Task { await refresh() }
    }

    var lastSignInAt: Date? {
        lastSignInTimestamp > 0 ? Date(timeIntervalSince1970: lastSignInTimestamp) : nil
    }

    var menuBarLabel: String {
        if let b = balance { return String(format: "$%.2f", b.balanceUSD) }
        return ""
    }

    var dailyBaselineDate: Date? {
        dailyBaselineTimestamp > 0 ? Date(timeIntervalSince1970: dailyBaselineTimestamp) : nil
    }

    var dailySpendUSD: Double? {
        guard let s = spend, dailyBaselineCents >= 0,
              let baseline = dailyBaselineDate,
              Calendar.current.isDate(baseline, inSameDayAs: Date()) else {
            return nil
        }
        let cents = max(0, s.amount - dailyBaselineCents)
        return Double(cents) / 100.0
    }

    var avgDailyUSD: Double? {
        guard let s = spend, s.spentUSD > 0 else { return nil }
        let day = Calendar.current.component(.day, from: Date())
        guard day > 0 else { return nil }
        return s.spentUSD / Double(day)
    }

    var daysRemaining: Double? {
        guard let b = balance, let avg = avgDailyUSD, avg > 0 else { return nil }
        return b.balanceUSD / avg
    }

    func refresh() async {
        guard let sessionKey = KeychainStore.load(key: "sessionKey"), !sessionKey.isEmpty,
              !orgId.isEmpty else {
            error = "Not signed in. Open Settings."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let bal = service.fetchBalance(orgId: orgId, sessionKey: sessionKey)
            async let spd = service.fetchSpend(orgId: orgId, sessionKey: sessionKey)
            async let rl  = service.fetchRateLimits(orgId: orgId, sessionKey: sessionKey)
            balance = try await bal
            spend = try? await spd
            rateLimits = try? await rl
            updateDailyBaseline()
            lastUpdated = Date()
            error = nil
        } catch let err as CreditServiceError {
            error = err.errorDescription
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func updateDailyBaseline() {
        guard let s = spend else { return }
        let now = Date()
        if dailyBaselineCents < 0 {
            dailyBaselineCents = s.amount
            dailyBaselineTimestamp = now.timeIntervalSince1970
            return
        }
        let baselineDate = Date(timeIntervalSince1970: dailyBaselineTimestamp)
        if !Calendar.current.isDate(baselineDate, inSameDayAs: now) {
            dailyBaselineCents = s.amount
            dailyBaselineTimestamp = now.timeIntervalSince1970
        } else if s.amount < dailyBaselineCents {
            // monthly cycle just rolled over
            dailyBaselineCents = s.amount
            dailyBaselineTimestamp = now.timeIntervalSince1970
        }
    }

    func signInWithChrome() async -> Result<Void, Error> {
        isImporting = true
        defer { isImporting = false }
        let result: ChromeImportResult
        do {
            result = try await Task.detached(priority: .userInitiated) {
                try ChromeCookieImporter.importCookies()
            }.value
        } catch {
            return .failure(error)
        }
        KeychainStore.save(key: "sessionKey", value: result.sessionKey)
        orgId = result.orgId
        lastSignInTimestamp = Date().timeIntervalSince1970
        await refresh()
        return .success(())
    }

    func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(60, refreshIntervalSeconds))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }
}
