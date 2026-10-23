import Foundation

/// Who a UPI QR code pays, and how much when the shop fixed it.
public struct UPIPayee: Equatable, Codable, Sendable {
    /// The UPI ID, like "sharmakirana@ybl".
    public var address: String
    /// The name the code gives, if any.
    public var name: String?
    /// Set by the shop on a code for one bill; nil on a shop's everyday code.
    public var amountPaise: Int?
    /// The code's own note ("Table 4", an order number), if any.
    public var note: String?
    /// The code's own parameters, passed on to the payment app as they
    /// were, so it sees exactly what its own scanner would.
    public var query: String

    public init(address: String, name: String? = nil, amountPaise: Int? = nil, note: String? = nil, query: String) {
        self.address = address
        self.name = name
        self.amountPaise = amountPaise
        self.note = note
        self.query = query
    }

    /// The name, or the UPI ID when the code has none.
    public var displayName: String { name ?? address }

    /// The payment as a link into one app: "phonepe://pay?" + the code's
    /// parameters. A `note` goes along as the UPI remark (`tn`), in place
    /// of the code's own, so the payment app shows it too.
    public func link(prefix: String, note: String? = nil) -> URL? {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return URL(string: prefix + query) }
        let kept = query.split(separator: "&").filter { !$0.lowercased().hasPrefix("tn=") }
        // The remark is plain text; UPI apps allow letters, digits and spaces.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " .,-_"))
        let cleaned = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let remark = String(cleaned.prefix(50))
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        return URL(string: prefix + (kept + ["tn=\(remark)"]).joined(separator: "&"))
    }
}

public enum UPIQR {
    /// Reads a scanned code: a UPI link (`upi://pay?pa=...`) or a Bharat QR
    /// code that carries a UPI ID. Nil for anything else.
    public static func parse(_ payload: String) -> UPIPayee? {
        let text = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.lowercased().hasPrefix("upi://pay?") {
            return link(text)
        }
        if text.hasPrefix("000201") {
            return bharatQR(text)
        }
        return nil
    }

    /// "name@bank": letters, digits, dots, dashes and underscores, then a
    /// handle that starts with a letter.
    public static func isAddress(_ text: String) -> Bool {
        text.wholeMatch(of: #/[A-Za-z0-9._\-]{2,256}@[A-Za-z][A-Za-z0-9._\-]{1,64}/#) != nil
    }

    // MARK: UPI links

    private static func link(_ text: String) -> UPIPayee? {
        // Some printed codes leave spaces in the name unencoded.
        let query = String(text.dropFirst("upi://pay?".count)).replacingOccurrences(of: " ", with: "%20")
        guard let items = URLComponents(string: "upi://pay?" + query)?.queryItems else { return nil }
        func value(_ key: String) -> String? {
            items.first { $0.name.lowercased() == key }?.value
        }
        guard let address = value("pa").map(cleaned), isAddress(address) else { return nil }
        return UPIPayee(
            address: address,
            name: value("pn").flatMap(name),
            amountPaise: value("am").flatMap(paise),
            note: value("tn").flatMap(name),
            query: query
        )
    }

    // MARK: Bharat QR

    /// EMV merchant codes, as banks print them: two-digit tags and lengths.
    /// The UPI ID sits in one of the merchant account templates (26–51),
    /// the name in 59 and a fixed amount in 54.
    private static func bharatQR(_ text: String) -> UPIPayee? {
        guard let fields = tlv(text) else { return nil }
        var address: String?
        for tag in 26...51 {
            guard let template = fields[tag], let inner = tlv(template) else { continue }
            if let found = inner.values.map(cleaned).first(where: isAddress) {
                address = found
                break
            }
        }
        guard let address else { return nil }
        let name = fields[59].flatMap(name)
        let amount = fields[54].flatMap(paise)
        var items = [URLQueryItem(name: "pa", value: address)]
        if let name { items.append(URLQueryItem(name: "pn", value: name)) }
        if let code = fields[52], code != "0000" { items.append(URLQueryItem(name: "mc", value: code)) }
        if amount != nil { items.append(URLQueryItem(name: "am", value: fields[54])) }
        items.append(URLQueryItem(name: "cu", value: "INR"))
        var components = URLComponents()
        components.queryItems = items
        return UPIPayee(address: address, name: name, amountPaise: amount, query: components.percentEncodedQuery ?? "")
    }

    /// Tag → value, or nil if the lengths don't add up.
    private static func tlv(_ text: String) -> [Int: String]? {
        var fields: [Int: String] = [:]
        var rest = Substring(text)
        while !rest.isEmpty {
            guard rest.count >= 4,
                  let tag = Int(rest.prefix(2)),
                  let length = Int(rest.dropFirst(2).prefix(2)),
                  rest.count >= 4 + length
            else { return nil }
            fields[tag] = String(rest.dropFirst(4).prefix(length))
            rest = rest.dropFirst(4 + length)
        }
        return fields
    }

    // MARK: Values

    private static func cleaned(_ address: String) -> String {
        address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A readable name, or nil for the placeholders some codes carry.
    /// Payment apps read "+" as a space, as web forms do.
    private static func name(_ raw: String) -> String? {
        let name = raw.replacingOccurrences(of: "+", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !name.isEmpty, !["null", "na", "n/a", "undefined"].contains(name.lowercased()) else { return nil }
        return name
    }

    /// "250", "250.5" or "250.00" as paise; nil for zero or anything else.
    private static func paise(_ raw: String) -> Int? {
        guard raw.wholeMatch(of: #/\d{1,9}(\.\d{0,2})?/#) != nil,
              let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), value > 0
        else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
}
