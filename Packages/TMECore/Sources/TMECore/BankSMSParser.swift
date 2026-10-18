import Foundation

/// What a bank alert says happened.
public struct BankSMS: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case expense
        case income
    }

    public var kind: Kind
    /// Amount in paise: ₹250.50 is 25050.
    public var amountPaise: Int
    /// Who was paid, or who paid you, when the message names them.
    public var counterparty: String?
    /// Last digits of the account or card, such as "1234".
    public var accountTail: String?
    /// UPI or bank reference number, used to spot the same payment twice.
    public var reference: String?

    public init(
        kind: Kind,
        amountPaise: Int,
        counterparty: String? = nil,
        accountTail: String? = nil,
        reference: String? = nil
    ) {
        self.kind = kind
        self.amountPaise = amountPaise
        self.counterparty = counterparty
        self.accountTail = accountTail
        self.reference = reference
    }
}

/// Reads the debit and credit alerts Indian banks send by SMS.
///
/// Returns nil for anything that isn't a completed transaction: OTPs,
/// reminders, failed payments, card-bill confirmations and promotions.
public enum BankSMSParser {
    public static func parse(_ message: String) -> BankSMS? {
        let text = message.replacingOccurrences(of: "\r\n", with: "\n")
        guard !isNoise(text),
              let kind = kind(of: text),
              let amount = amountPaise(in: text), amount > 0
        else { return nil }

        return BankSMS(
            kind: kind,
            amountPaise: amount,
            counterparty: counterparty(in: text, kind: kind),
            accountTail: accountTail(in: text),
            reference: reference(in: text)
        )
    }

    static func isNoise(_ text: String) -> Bool {
        let noise = #/\b(?:otp|one[\s-]?time password|verification code|will be debited|to be debited|is due|due on|due date|payment due|requested|collect request|failed|declined|unsuccessful|offer|pre-?approved|apply now|thank you for (?:the |your )?payment|received (?:towards|on|for) your)\b/#
        return text.contains(noise.ignoresCase())
    }

    static func kind(of text: String) -> BankSMS.Kind? {
        let debit = #/\b(?:debited|spent|sent|paid|withdrawn|deducted|purchase|debit alert|txn of)\b/#
        let credit = #/\b(?:credited|received|deposited|refund(?:ed)?|credit alert)\b/#
        // Some banks mention both sides ("Acct debited; SWIGGY credited"),
        // so whichever comes first describes your account.
        let debitAt = text.firstRange(of: debit.ignoresCase())?.lowerBound
        let creditAt = text.firstRange(of: credit.ignoresCase())?.lowerBound
        switch (debitAt, creditAt) {
        case let (debit?, credit?): return debit < credit ? .expense : .income
        case (.some, nil): return .expense
        case (nil, .some): return .income
        case (nil, nil): return nil
        }
    }

    static func amountPaise(in text: String) -> Int? {
        // SBI writes "debited by 250.0" with no currency sign.
        let afterVerb = #/\b(?:debited|credited)\s+(?:by|for|with)\s+(?:(?:rs\.?|inr)\s*|₹\s*)?(\d[\d,]*(?:\.\d{1,2})?)/#
        if let match = text.firstMatch(of: afterVerb.ignoresCase()) {
            return paise(from: match.1)
        }
        let withCurrency = #/(?:\b(?:rs\.?|inr)|₹)\s*(\d[\d,]*(?:\.\d{1,2})?)/#
        for match in text.matches(of: withCurrency.ignoresCase()) {
            // Skip "Avl bal INR 1,23,456.00" and "Avl Limit: INR ...".
            let before = text[..<match.range.lowerBound].suffix(16).lowercased()
            if before.contains("bal") || before.contains("limit") || before.contains("avl") { continue }
            return paise(from: match.1)
        }
        return nil
    }

    static func paise(from digits: Substring) -> Int? {
        let parts = digits.replacingOccurrences(of: ",", with: "")
            .split(separator: ".", omittingEmptySubsequences: false)
        guard let rupees = Int(parts[0]) else { return nil }
        let fraction = parts.count > 1 ? String((parts[1] + "00").prefix(2)) : "00"
        guard let paise = Int(fraction) else { return nil }
        return rupees * 100 + paise
    }

    static func accountTail(in text: String) -> String? {
        let tail = #/\b(?:a/c|ac|acct|account|card)(?:\s*no\.?)?(?:\s*ending)?\s*[x*]*\s*(\d{3,4})\b/#
        return text.firstMatch(of: tail.ignoresCase()).map { String($0.1) }
    }

    static func reference(in text: String) -> String? {
        let axis = #/upi/p2[am]/(\d{6,})/#
        if let match = text.firstMatch(of: axis.ignoresCase()) {
            return String(match.1)
        }
        let labelled = #/\b(?:ref(?:erence)?(?:\s*no)?|rrn|utr|upi(?:\s*ref)?(?:\s*no)?)\b[\s:.\-]*(\d{6,})/#
        return text.firstMatch(of: labelled.ignoresCase()).map { String($0.1) }
    }

    static func counterparty(in text: String, kind: BankSMS.Kind) -> String? {
        let patterns: [Regex<(Substring, Substring)>]
        switch kind {
        case .expense:
            patterns = [
                #/upi/p2[am]/\d+/([^/\n]+)/#,                              // Axis: UPI/P2M/<ref>/SWIGGY
                #/\bto\s+vpa\s+([^\s(]+)/#,                                // to VPA swiggy@icici
                #/\bat\s+(.+?)\s+on\s+\d/#,                                // card: at AMAZON on 17/10/26
                #/\btrf\s+to\s+(.+?)\s+ref/#,                              // SBI: trf to SWIGGY Refno
                #/;\s*(.+?)\s+credited/#,                                  // ICICI: ; SWIGGY credited
                #/\bon\s+([a-z][^.\n]*?)\.(?:\s|$)/#,                      // ICICI card: on AMAZON.
                #/\bto\s+(.+?)(?:\s+on\s+\d|\s+ref\b|\s*\(|\.\s|\n)/#,     // To SWIGGY\nOn 17/10/26
            ]
        case .income:
            patterns = [
                #/\bfrom\s+vpa\s+([^\s(]+)/#,                              // from VPA abc@okaxis
                #/neft\s+cr-[a-z0-9]+-(.+?)-/#,                            // NEFT Cr-IFSC-ACME PVT LTD-...
                #/\bfrom\s+(.+?)(?:\s+on\s+\d|\s+credited\b|\s*\(|\.\s|\.$|\s+upi\b|\s+ref\b|\n)/#,
            ]
        }
        for pattern in patterns {
            if let match = text.firstMatch(of: pattern.ignoresCase()), let name = cleanName(match.1) {
                return name
            }
        }
        return nil
    }

    static func cleanName(_ raw: Substring) -> String? {
        var name = String(raw)
        // A UPI handle like swiggy@icici becomes "swiggy".
        if let at = name.firstIndex(of: "@") {
            name = String(name[..<at])
        }
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = name.lowercased()
        guard !name.isEmpty, name.count <= 40,
              !lower.contains("a/c"), !lower.contains("acct"), !lower.hasPrefix("your ")
        else { return nil }
        return name
    }
}
