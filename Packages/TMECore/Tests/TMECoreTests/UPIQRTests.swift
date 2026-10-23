import Foundation
import Testing
@testable import TMECore

// Shops, names and UPI IDs are made up.

@Suite("UPI QR codes")
struct UPIQRTests {
    @Test func readsAShopsEverydayCode() throws {
        let payee = try #require(UPIQR.parse("upi://pay?pa=sharmakirana@ybl&pn=Sharma%20Kirana&mc=5411&cu=INR"))
        #expect(payee.address == "sharmakirana@ybl")
        #expect(payee.name == "Sharma Kirana")
        #expect(payee.amountPaise == nil)
        #expect(payee.displayName == "Sharma Kirana")
    }

    @Test func readsAFixedAmount() throws {
        let payee = try #require(UPIQR.parse("upi://pay?pa=cafe.blue@okicici&pn=Blue%20Cafe&am=245.50&cu=INR&tr=ORD1234"))
        #expect(payee.amountPaise == 24550)
        let whole = try #require(UPIQR.parse("upi://pay?pa=cafe.blue@okicici&am=300"))
        #expect(whole.amountPaise == 30000)
    }

    @Test func zeroOrOddAmountsMeanTypeItYourself() throws {
        #expect(try #require(UPIQR.parse("upi://pay?pa=a.b@ybl&am=0.00")).amountPaise == nil)
        #expect(try #require(UPIQR.parse("upi://pay?pa=a.b@ybl&am=abc")).amountPaise == nil)
        #expect(try #require(UPIQR.parse("upi://pay?pa=a.b@ybl&am=")).amountPaise == nil)
    }

    @Test func toleratesHowCodesAreActuallyPrinted() throws {
        // Upper case, spaces left in, "+" for spaces, keys in any case.
        let shouting = try #require(UPIQR.parse("UPI://PAY?PA=RAMESH.TEA@PAYTM&PN=Ramesh Tea Stall"))
        #expect(shouting.address == "RAMESH.TEA@PAYTM")
        #expect(shouting.name == "Ramesh Tea Stall")
        let plus = try #require(UPIQR.parse("  upi://pay?pa=9876543210@ybl&pn=Anita+Rao\n"))
        #expect(plus.name == "Anita Rao")
    }

    @Test func placeholderNamesFallBackToTheUPIID() throws {
        let payee = try #require(UPIQR.parse("upi://pay?pa=paytmqr2810050501abcd@paytm&pn=null"))
        #expect(payee.name == nil)
        #expect(payee.displayName == "paytmqr2810050501abcd@paytm")
    }

    @Test func handsTheAppTheCodesOwnParameters() throws {
        let code = "upi://pay?pa=cafe.blue@okicici&pn=Blue%20Cafe&am=245.50&cu=INR&tr=ORD1234&sign=AbC%2Bd%3D"
        let payee = try #require(UPIQR.parse(code))
        #expect(payee.link(prefix: "phonepe://pay?")?.absoluteString == "phonepe://pay?pa=cafe.blue@okicici&pn=Blue%20Cafe&am=245.50&cu=INR&tr=ORD1234&sign=AbC%2Bd%3D")
        #expect(payee.link(prefix: "tez://upi/pay?")?.absoluteString == "tez://upi/pay?pa=cafe.blue@okicici&pn=Blue%20Cafe&am=245.50&cu=INR&tr=ORD1234&sign=AbC%2Bd%3D")
        // Spaces the printer left in are encoded on the way out.
        let spaced = try #require(UPIQR.parse("upi://pay?pa=ramesh.tea@paytm&pn=Ramesh Tea"))
        #expect(spaced.link(prefix: "paytmmp://pay?")?.absoluteString == "paytmmp://pay?pa=ramesh.tea@paytm&pn=Ramesh%20Tea")
    }

    @Test func readsTheCodesOwnNote() throws {
        let payee = try #require(UPIQR.parse("upi://pay?pa=bluecafe@okicici&pn=Blue%20Cafe&tn=Table%204"))
        #expect(payee.note == "Table 4")
        #expect(try #require(UPIQR.parse("upi://pay?pa=bluecafe@okicici&tn=null")).note == nil)
        #expect(try #require(UPIQR.parse("upi://pay?pa=bluecafe@okicici")).note == nil)
    }

    @Test func aTypedNoteGoesAlongAsTheRemark() throws {
        let payee = try #require(UPIQR.parse("upi://pay?pa=bluecafe@okicici&pn=Blue%20Cafe&tn=Table%204&cu=INR"))
        #expect(payee.link(prefix: "phonepe://pay?", note: "Lunch with Riya")?.absoluteString
            == "phonepe://pay?pa=bluecafe@okicici&pn=Blue%20Cafe&cu=INR&tn=Lunch%20with%20Riya")
        // Blank notes leave the code as it was; odd characters are dropped.
        #expect(payee.link(prefix: "phonepe://pay?", note: "  ")?.absoluteString == "phonepe://pay?pa=bluecafe@okicici&pn=Blue%20Cafe&tn=Table%204&cu=INR")
        #expect(payee.link(prefix: "tez://upi/pay?", note: "Rent & deposit #3 😀")?.absoluteString
            == "tez://upi/pay?pa=bluecafe@okicici&pn=Blue%20Cafe&cu=INR&tn=Rent%20deposit%203")
        let plain = try #require(UPIQR.parse("upi://pay?pa=sharmakirana@ybl"))
        #expect(plain.link(prefix: "paytmmp://pay?", note: "Milk")?.absoluteString == "paytmmp://pay?pa=sharmakirana@ybl&tn=Milk")
    }

    @Test func readsBharatQRWithAUPIID() throws {
        let code = Self.bharatQR(upi: "sharmakirana@ybl", name: "SHARMA KIRANA", amount: nil)
        let payee = try #require(UPIQR.parse(code))
        #expect(payee.address == "sharmakirana@ybl")
        #expect(payee.name == "SHARMA KIRANA")
        #expect(payee.amountPaise == nil)
        #expect(payee.query == "pa=sharmakirana@ybl&pn=SHARMA%20KIRANA&mc=5411&cu=INR")

        let billed = try #require(UPIQR.parse(Self.bharatQR(upi: "sharmakirana@ybl", name: "SHARMA KIRANA", amount: "120.00")))
        #expect(billed.amountPaise == 12000)
        #expect(billed.query.contains("am=120.00"))
    }

    @Test func ignoresCodesThatArentUPIPayments() {
        let notPayments = [
            "https://example.com/menu",
            "upi://mandate?pa=netflix@icici&am=499",
            "upi://pay?pn=No%20ID",
            "upi://pay?pa=not-an-id",
            "upi://pay?pa=@ybl",
            "WIFI:S:Cafe;T:WPA;P:secret;;",
            // A Bharat QR code for cards only, with no UPI ID.
            Self.bharatQR(upi: nil, name: "CARD ONLY", amount: nil),
            // Lengths that don't add up.
            "000201010211261000",
            "",
        ]
        for code in notPayments {
            #expect(UPIQR.parse(code) == nil, "\(code)")
        }
    }

    /// A Bharat QR code as a bank prints it: card network IDs, a UPI
    /// template, the shop's category, country, name and city.
    static func bharatQR(upi: String?, name: String, amount: String?) -> String {
        func field(_ tag: String, _ value: String) -> String {
            tag + String(format: "%02d", value.count) + value
        }
        var code = field("00", "01") + field("01", amount == nil ? "11" : "12")
        code += field("02", "4111110000012345")
        if let upi {
            code += field("26", field("00", "A000000677010111") + field("01", upi) + field("02", "0000"))
        }
        code += field("52", "5411") + field("53", "356")
        if let amount { code += field("54", amount) }
        code += field("58", "IN") + field("59", name) + field("60", "BENGALURU")
        return code + field("63", "1A2B")
    }
}
