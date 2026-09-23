import Foundation

/// The web page's rule for typed euro amounts: digits, optionally a dot or
/// comma and one or two decimals, spaces ignored. Returns cents.
public func parseEuroInput(_ raw: String) -> Int? {
    let trimmed = raw.filter { !$0.isWhitespace }
    guard !trimmed.isEmpty else { return nil }
    let parts = trimmed.split(separator: trimmed.contains(",") ? "," : ".", omittingEmptySubsequences: false)
    guard parts.count <= 2,
          let whole = parts.first, !whole.isEmpty, whole.allSatisfy(\.isASCII), whole.allSatisfy(\.isNumber),
          let wholeValue = Int(whole)
    else { return nil }
    var cents = 0
    if parts.count == 2 {
        let frac = parts[1]
        guard (1...2).contains(frac.count), frac.allSatisfy(\.isASCII), frac.allSatisfy(\.isNumber),
              let value = Int(frac.padding(toLength: 2, withPad: "0", startingAt: 0))
        else { return nil }
        cents = value
    }
    let (total, overflow) = wholeValue.multipliedReportingOverflow(by: 100)
    guard !overflow else { return nil }
    return total + cents
}

public enum MoneyWarning: Sendable, Equatable {
    case noAccounts
    case stale(days: Int, since: String)
    case foreignCurrency([String])
    case overReserved
}

/// In the order the web page shows them. Without an account there are no
/// numbers at all, so no other warning applies.
public func moneyWarnings(for kid: KidMoney) -> [MoneyWarning] {
    guard kid.hasAccounts else { return [.noAccounts] }
    var out: [MoneyWarning] = []
    if let days = kid.staleDays, let since = kid.lastActivity {
        out.append(.stale(days: days, since: since))
    }
    if !kid.foreignCurrencies.isEmpty { out.append(.foreignCurrency(kid.foreignCurrencies)) }
    if kid.overReserved { out.append(.overReserved) }
    return out
}

public struct GoalGroups: Sendable, Equatable {
    public let active: [MoneyGoal]
    public let archived: [MoneyGoal]
}

public func goalGroups(_ goals: [MoneyGoal]) -> GoalGroups {
    GoalGroups(active: goals.filter { !$0.archived }, archived: goals.filter(\.archived))
}

public struct SpendPoint: Sendable, Hashable {
    public let kid: String
    public let month: String
    public let cents: Int

    public init(kid: String, month: String, cents: Int) {
        self.kid = kid
        self.month = month
        self.cents = cents
    }
}

/// Spending per child for the last `months` months any child has data for,
/// zero where a child has none, children in the given order.
public func spendSeries(_ kids: [KidMoney], months: Int) -> [SpendPoint] {
    let allMonths = Set(kids.flatMap { $0.monthly.map(\.month) }).sorted().suffix(months)
    return kids.flatMap { kid in
        let byMonth = Dictionary(kid.monthly.map { ($0.month, $0.spentCents) }, uniquingKeysWith: { a, _ in a })
        return allMonths.map { SpendPoint(kid: kid.displayName, month: $0, cents: byMonth[$0] ?? 0) }
    }
}

/// Codes the server answers with; the app words the known ones itself.
public enum MoneyErrorCode: String, Sendable {
    case forbidden
    case goalTitleRequired = "goal_title_required"
    case goalTitleTooLong = "goal_title_too_long"
    case goalTargetInvalid = "goal_target_invalid"
    case goalUnknown = "goal_unknown"
    case amountInvalid = "amount_invalid"
    case depositRejected = "deposit_rejected"
    case emailInvalid = "email_invalid"
    case passwordTooShort = "password_too_short"
    case displayNameRequired = "display_name_required"
    case kidUnknown = "kid_unknown"
    case noAccountsSelected = "no_accounts_selected"
    case badRequest = "bad_request"
    case createUserFailed = "create_user_failed"
}
