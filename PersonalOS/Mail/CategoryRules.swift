import Foundation
import SwiftData

// MARK: - Merchant → 카테고리
//
// Two layers. User rules (POSMerchantRule, taught from the review queue) win;
// then a keyword table tuned to the merchants that actually show up in
// Sihoon's Chase alerts. Anything unmatched lands in 기타 and stays unreviewed
// so it's easy to find and teach.

enum CategoryRules {

    /// Ordered on purpose: the first table whose keyword appears in the raw
    /// merchant string wins, so put the specific groups before the broad ones.
    private static let table: [(category: String, keywords: [String])] = [
        ("구독", [
            "OPENAI", "CHATGPT", "ANTHROPIC", "CLAUDE", "NETFLIX", "SPOTIFY", "YOUTUBE",
            "APPLE.COM/BILL", "APPLE MUSIC", "APPLECARE", "ICLOUD", "ADOBE", "GITHUB",
            "NOTION", "FIGMA", "DISNEY", "HULU", "PATREON", "MIDJOURNEY", "CURSOR",
        ]),
        ("주거/공과금", [
            "CANOOCHEE", "ELECTR", "GEORGIA POWER", "WATER", "COMCAST", "XFINITY",
            "T-MOBILE", "TMOBILE", "VERIZON", "AT&T", "BILT PAYMENT", "RENT", "APARTMENT",
            "PROPERTY", "INSURANCE", "GEICO", "PROGRESSIVE", "STATE FARM",
        ]),
        ("교통/차", [
            "MTA", "NYCT", "NJT", "NJTRANSIT", "TRANSIT", "AMTRAK", "LYFT", "UBER TRIP",
            "TESLA", "SHELL", "EXXON", "CHEVRON", "BP#", "QUIKTRIP", "RACETRAC", "ENMARKET",
            "CIRCLE K", "PARKING", "TOLL", "PEACH PASS", "AIRPORT", "UNITED", "DELTA",
            "AMERICAN AIR", "SOUTHWEST", "AUTO LEASE", "DMV", "CAR WASH", "DISCOUNT TIRE",
        ]),
        ("식비", [
            "TST", "TOAST", "DOORDASH", "GRUBHUB", "UBER EATS", "UBEREATS", "STARBUCKS",
            "COFFEE", "CAFE", "CAFFE", "DALKOM", "BAKERY", "CHICKEN", "BB.Q", "BBQ",
            "PIZZA", "SUSHI", "RAMEN", "GOPCHANG", "HWANGSO", "SORIMMARA", "TOFU",
            "KIMBAP", "H MART", "HMART", "A-REUM", "MARKET", "GROCERY", "PUBLIX",
            "KROGER", "TRADER JOE", "WHOLE FOODS", "MCDONALD", "CHIPOTLE", "SUBWAY",
            "PANDA", "BURGER", "TACO", "RESTAURANT", "KITCHEN", "BAR & GRILL", "DELI",
            "SNACK", "BOBA", "JUICE", "DONUT", "BASKIN", "CHICK-FIL-A",
        ]),
        ("의료", [
            "PHARMACY", "CVS", "WALGREENS", "DENTAL", "DENTIST", "CLINIC", "HOSPITAL",
            "MEDICAL", "HEALTH", "OPTOMETR", "VISION CENTER", "URGENT CARE",
        ]),
        ("금융", [
            "ZELLE", "VENMO", "CASH APP", "PAYPAL", "TRANSFER", "WIRE", "ATM",
            "PAYMENT THANK YOU", "COINBASE", "ROBINHOOD", "FIDELITY", "VANGUARD",
        ]),
        ("쇼핑", [
            "AMAZON", "AMZN", "TARGET", "WALMART", "COSTCO", "TJ MAXX", "TJMAXX",
            "MARSHALLS", "ROSS", "BEST BUY", "HOME DEPOT", "LOWES", "IKEA", "UNIQLO",
            "NIKE", "ADIDAS", "STUSSY", "SP ALO", "QUINCE", "MOMA", "GIFTS", "APPLE STORE",
            "SEPHORA", "ULTA", "ETSY", "SHOPIFY", "STORE", "BOUTIQUE", "OLIVE YOUNG",
        ]),
    ]

    /// Resolves the category for a merchant string, consulting the user's
    /// learned rules first.
    @MainActor
    static func category(for merchantRaw: String, context: ModelContext) -> String {
        let haystack = merchantRaw.uppercased()

        var descriptor = FetchDescriptor<POSMerchantRule>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        if let rules = try? context.fetch(descriptor) {
            for rule in rules where !rule.pattern.isEmpty && haystack.contains(rule.pattern) {
                return rule.category
            }
        }

        return builtInCategory(for: merchantRaw)
    }

    /// The keyword table alone — no database access, handy for previews.
    static func builtInCategory(for merchantRaw: String) -> String {
        let haystack = merchantRaw.uppercased()
        for group in table {
            for keyword in group.keywords where haystack.contains(keyword) {
                return group.category
            }
        }
        return "기타"
    }

    /// A prettier title if the user taught one for this merchant.
    @MainActor
    static func displayName(for merchantRaw: String, fallback: String, context: ModelContext) -> String {
        let haystack = merchantRaw.uppercased()
        var descriptor = FetchDescriptor<POSMerchantRule>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        guard let rules = try? context.fetch(descriptor) else { return fallback }
        for rule in rules where !rule.pattern.isEmpty
            && !rule.displayName.isEmpty
            && haystack.contains(rule.pattern) {
            return rule.displayName
        }
        return fallback
    }

    /// Remembers "this merchant is always that category". Replaces an existing
    /// rule for the same pattern instead of stacking duplicates.
    @MainActor
    static func teach(pattern: String, category: String, displayName: String = "", context: ModelContext) {
        let normalized = pattern.trimmingCharacters(in: .whitespaces).uppercased()
        guard !normalized.isEmpty else { return }

        if let existing = try? context.fetch(FetchDescriptor<POSMerchantRule>()) {
            for rule in existing where rule.pattern == normalized {
                context.delete(rule)
            }
        }
        context.insert(POSMerchantRule(pattern: normalized, category: category, displayName: displayName))
        try? context.save()
    }
}
