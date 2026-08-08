import Foundation

// MARK: - Mail importer settings
//
// Credentials live in the Keychain; everything else in UserDefaults so the
// settings screen can bind with @AppStorage using the same keys.

enum MailSettings {

    static let addressKey = "mailAddress"
    static let hostKey = "mailHost"
    static let portKey = "mailPort"
    static let mailboxKey = "mailMailbox"
    static let backfillDaysKey = "mailBackfillDays"
    static let lastSyncKey = "mailLastSyncAt"
    static let autoSyncKey = "mailAutoSync"
    static let notifyKey = "mailNotify"
    static let disabledRulesKey = "mailDisabledRules"

    static let defaultHost = "imap.gmail.com"
    static let defaultPort = 993
    /// Empty means "ask the server for the \All mailbox, fall back to INBOX".
    static let defaultMailbox = ""
    static let defaultBackfillDays = 90

    static var address: String {
        get { UserDefaults.standard.string(forKey: addressKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: addressKey) }
    }

    static var host: String {
        let value = UserDefaults.standard.string(forKey: hostKey) ?? ""
        return value.isEmpty ? defaultHost : value
    }

    static var port: Int {
        let value = UserDefaults.standard.integer(forKey: portKey)
        return value == 0 ? defaultPort : value
    }

    static var mailbox: String {
        UserDefaults.standard.string(forKey: mailboxKey) ?? defaultMailbox
    }

    static var backfillDays: Int {
        let value = UserDefaults.standard.integer(forKey: backfillDaysKey)
        return value == 0 ? defaultBackfillDays : value
    }

    static var autoSync: Bool {
        get { UserDefaults.standard.object(forKey: autoSyncKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoSyncKey) }
    }

    static var notify: Bool {
        UserDefaults.standard.object(forKey: notifyKey) as? Bool ?? true
    }

    static var lastSyncAt: Date? {
        get {
            let raw = UserDefaults.standard.double(forKey: lastSyncKey)
            return raw == 0 ? nil : Date(timeIntervalSince1970: raw)
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: lastSyncKey)
        }
    }

    static var password: String? {
        get { KeychainStore.get(KeychainStore.mailPasswordKey) }
        set {
            if let newValue, !newValue.isEmpty {
                KeychainStore.set(newValue, key: KeychainStore.mailPasswordKey)
            } else {
                KeychainStore.delete(KeychainStore.mailPasswordKey)
            }
        }
    }

    static var isConfigured: Bool {
        !address.isEmpty && !(password ?? "").isEmpty
    }

    // MARK: Per-rule enablement

    private static var disabledRules: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: disabledRulesKey) ?? MailRuleDefaults.disabledByDefault) }
        set { UserDefaults.standard.set(Array(newValue), forKey: disabledRulesKey) }
    }

    static func isEnabled(_ ruleID: String) -> Bool {
        !disabledRules.contains(ruleID)
    }

    static func setEnabled(_ enabled: Bool, for ruleID: String) {
        var rules = disabledRules
        if enabled { rules.remove(ruleID) } else { rules.insert(ruleID) }
        disabledRules = rules
    }

    /// The window to search on the next run: the backfill window on a first
    /// run, otherwise a couple of days of overlap so nothing slips through a
    /// clock skew. Duplicates are filtered by Message-ID anyway.
    static var searchSince: Date {
        guard let last = lastSyncAt else {
            return Calendar.current.date(byAdding: .day, value: -backfillDays, to: .now) ?? .now
        }
        return Calendar.current.date(byAdding: .day, value: -2, to: last) ?? last
    }

    static func reset() {
        password = nil
        lastSyncAt = nil
        UserDefaults.standard.removeObject(forKey: addressKey)
    }
}

enum MailRuleDefaults {
    /// Apple receipts overlap with the Chase card alert for the same charge,
    /// so the source group ships off until the user opts in.
    static let disabledByDefault = ["apple"]
}
