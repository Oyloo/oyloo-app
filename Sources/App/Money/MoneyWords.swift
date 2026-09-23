import Foundation

/// The person-facing text for a failed money action: known server codes in
/// the app's own words, anything else as the server phrased it.
func moneyFailureText(_ error: Error) -> String {
    if case let AppAPI.Failure.server(code, message) = error {
        switch MoneyErrorCode(rawValue: code) {
        case .goalTitleRequired: return String(localized: "Give the goal a name.")
        case .goalTitleTooLong: return String(localized: "The name is too long: 60 characters at most.")
        case .goalTargetInvalid: return String(localized: "Enter how much the goal needs.")
        case .amountInvalid: return String(localized: "Enter an amount above zero.")
        case .depositRejected: return String(localized: "Nothing moved: there is not that much in the goal.")
        case .emailInvalid: return String(localized: "That e-mail does not look right.")
        case .passwordTooShort: return String(localized: "The password needs at least 8 characters.")
        case .displayNameRequired: return String(localized: "Enter the child's name.")
        case .noAccountsSelected: return String(localized: "Pick at least one account.")
        case .forbidden: return String(localized: "This account has no access here.")
        case .createUserFailed: return String(localized: "The account was not created: \(message)")
        case .goalUnknown, .kidUnknown, .badRequest, .none: return message
        }
    }
    return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
}

func warningText(_ warning: MoneyWarning) -> String {
    switch warning {
    case .noAccounts:
        String(localized: "No bank account is linked to this account yet, so there are no numbers here — zeros would look like a real balance. Ask a parent to link one.")
    case let .stale(days, since):
        String(localized: "No data since \(since) — \(days) days. Either nothing happened on the account, or the bank sync has stopped.")
    case let .foreignCurrency(codes):
        String(localized: "A non-euro currency is linked (\(codes.joined(separator: ", "))). Everything is added up as euros, so the sums above cannot be trusted.")
    case .overReserved:
        String(localized: "More is set aside for goals than the account holds. The bank does not reserve it — the goals are only on paper, so some of them are not covered yet.")
    }
}
