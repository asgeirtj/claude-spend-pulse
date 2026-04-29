import Foundation

struct CreditResponse: Decodable {
    let amount: Int
    let currency: String
    let autoReloadSettings: AutoReloadSettings
    let pendingInvoiceAmountCents: Int?
    let lastPaidPurchaseCents: Int?

    enum CodingKeys: String, CodingKey {
        case amount, currency
        case autoReloadSettings = "auto_reload_settings"
        case pendingInvoiceAmountCents = "pending_invoice_amount_cents"
        case lastPaidPurchaseCents = "last_paid_purchase_cents"
    }

    var balanceUSD: Double { Double(amount) / 100.0 }
}

struct AutoReloadSettings: Decodable {
    let enabled: Bool
    let thresholdInMinorUnits: Int
    let reloadToInMinorUnits: Int

    enum CodingKeys: String, CodingKey {
        case enabled
        case thresholdInMinorUnits = "threshold_in_minor_units"
        case reloadToInMinorUnits = "reload_to_in_minor_units"
    }

    var thresholdUSD: Double { Double(thresholdInMinorUnits) / 100.0 }
    var reloadToUSD: Double { Double(reloadToInMinorUnits) / 100.0 }
}

struct SpendResponse: Decodable {
    let amount: Int
    let resetsAt: Date

    enum CodingKeys: String, CodingKey {
        case amount
        case resetsAt = "resets_at"
    }

    var spentUSD: Double { Double(amount) / 100.0 }
}

struct RateLimitsResponse: Decodable {
    let rateLimitTier: String
    let spendThreshold: Int?

    enum CodingKeys: String, CodingKey {
        case rateLimitTier = "rate_limit_tier"
        case spendThreshold = "spend_threshold"
    }

    var spendThresholdUSD: Double? {
        guard let t = spendThreshold else { return nil }
        return Double(t) / 100.0
    }

    /// "auto_prepaid_tier_1" → "1"; falls back to raw if no trailing digits.
    var tierLabel: String {
        if let lastUnderscore = rateLimitTier.lastIndex(of: "_") {
            let after = rateLimitTier[rateLimitTier.index(after: lastUnderscore)...]
            if !after.isEmpty, after.allSatisfy({ $0.isNumber }) {
                return String(after)
            }
        }
        return rateLimitTier
    }
}
