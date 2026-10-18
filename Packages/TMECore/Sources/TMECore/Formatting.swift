import Foundation

public enum Rupees {
    /// "₹250" for whole rupees, "₹250.50" otherwise, with Indian digit
    /// grouping ("₹1,23,456").
    public static func format(paise: Int) -> String {
        let value = Decimal(paise) / 100
        let digits = paise % 100 == 0 ? 0 : 2
        return value.formatted(
            .currency(code: "INR")
                .locale(Locale(identifier: "en_IN"))
                .precision(.fractionLength(digits))
        )
    }
}

public enum MerchantKey {
    /// Folds the ways banks spell one merchant into a single key, so a
    /// category chosen for "SWIGGY" also applies to "Swiggy Ltd".
    public static func make(_ name: String) -> String {
        var key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        for suffix in ["privatelimited", "pvtltd", "limited", "ltd"] where key.hasSuffix(suffix) && key.count > suffix.count {
            key.removeLast(suffix.count)
            break
        }
        return key
    }
}
