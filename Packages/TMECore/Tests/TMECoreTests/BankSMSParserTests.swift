import Testing
@testable import TMECore

// Sample alerts follow each bank's published format. Account numbers,
// references and names are made up.

struct SMSCase: CustomTestStringConvertible, Sendable {
    let label: String
    let sms: String
    let expected: BankSMS
    var testDescription: String { label }
}

@Suite("Bank SMS parser")
struct BankSMSParserTests {
    static let transactions: [SMSCase] = [
        SMSCase(
            label: "HDFC UPI sent",
            sms: "Sent Rs.250.00\nFrom HDFC Bank A/C *1234\nTo SWIGGY\nOn 17/10/26\nRef 629012345678\nNot You?\nCall 18002586161/SMS BLOCK UPI to 7308080808",
            expected: BankSMS(kind: .expense, amountPaise: 25000, counterparty: "SWIGGY", accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "HDFC UPI debit, older format",
            sms: "Rs.250.00 debited from a/c **1234 on 17-10-26 to VPA swiggy@icici(UPI Ref No 629012345678). Not you? Call on 18002586161 to report",
            expected: BankSMS(kind: .expense, amountPaise: 25000, counterparty: "swiggy", accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "HDFC card spend",
            sms: "Spent Rs.1,234.00 On HDFC Bank Card 1234 At AMAZON On 2026-10-17:12:34:56.Not You? To Block+Reissue Call 18002323232/SMS BLOCK CC 1234 to 7308080808",
            expected: BankSMS(kind: .expense, amountPaise: 123400, counterparty: "AMAZON", accountTail: "1234")
        ),
        SMSCase(
            label: "HDFC UPI credit",
            sms: "Credit Alert!\nRs.5,000.00 credited to HDFC Bank A/c XX1234 on 17-10-26 from VPA abc@okaxis (UPI 629012345678)",
            expected: BankSMS(kind: .income, amountPaise: 500000, counterparty: "abc", accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "HDFC salary by NEFT",
            sms: "Update! INR 50,000.00 deposited in HDFC Bank A/c XX1234 on 17-OCT-26 for NEFT Cr-HDFC0000001-ACME PVT LTD-RAHUL K-HDFCN52026101712345678.Avl bal INR 1,23,456.00. Cheque deposits in A/C are subject to clearing",
            expected: BankSMS(kind: .income, amountPaise: 5000000, counterparty: "ACME PVT LTD", accountTail: "1234")
        ),
        SMSCase(
            label: "SBI UPI debit",
            sms: "Dear UPI user A/C X1234 debited by 250.0 on date 17Oct26 trf to SWIGGY Refno 629012345678. If not u? call 1800111109. -SBI",
            expected: BankSMS(kind: .expense, amountPaise: 25000, counterparty: "SWIGGY", accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "SBI UPI credit",
            sms: "Dear SBI UPI User, ur A/cX1234 credited by Rs500 on 17Oct26 by (Ref no 629012345678)",
            expected: BankSMS(kind: .income, amountPaise: 50000, accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "SBI credit card spend",
            sms: "Rs.1,234.00 spent on your SBI Credit Card ending 1234 at AMAZON on 17/10/26. Trxn. not done by you? Report at https://sbicard.com/Dispute",
            expected: BankSMS(kind: .expense, amountPaise: 123400, counterparty: "AMAZON", accountTail: "1234")
        ),
        SMSCase(
            label: "ICICI UPI debit",
            sms: "ICICI Bank Acct XX123 debited for Rs 250.00 on 17-Oct-26; SWIGGY credited. UPI:629012345678. Call 18002662 for dispute. SMS BLOCK 123 to 9215676766.",
            expected: BankSMS(kind: .expense, amountPaise: 25000, counterparty: "SWIGGY", accountTail: "123", reference: "629012345678")
        ),
        SMSCase(
            label: "ICICI UPI credit",
            sms: "Dear Customer, Acct XX123 is credited with Rs 500.00 on 17-Oct-26 from ABC. UPI:629012345678-ICICI Bank.",
            expected: BankSMS(kind: .income, amountPaise: 50000, counterparty: "ABC", accountTail: "123", reference: "629012345678")
        ),
        SMSCase(
            label: "ICICI card spend",
            sms: "INR 1,234.00 spent using ICICI Bank Card XX1234 on 17-Oct-26 on AMAZON. Avl Limit: INR 1,00,000.00. If not you, call 1800 2662/SMS BLOCK 1234 to 9215676766",
            expected: BankSMS(kind: .expense, amountPaise: 123400, counterparty: "AMAZON", accountTail: "1234")
        ),
        SMSCase(
            label: "Axis UPI debit",
            sms: "INR 250.00 debited\nA/c no. XX1234\n17-10-26, 12:34:56\nUPI/P2M/629012345678/SWIGGY\nNot you? SMS BLOCKUPI Cust ID to 919951860002\nAxis Bank",
            expected: BankSMS(kind: .expense, amountPaise: 25000, counterparty: "SWIGGY", accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "Kotak UPI sent",
            sms: "Sent Rs.250.00 from Kotak Bank AC X1234 to swiggy@icici on 17-10-26.UPI Ref 629012345678. Not you, https://kotak.com/KBANKT/Fraud",
            expected: BankSMS(kind: .expense, amountPaise: 25000, counterparty: "swiggy", accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "Kotak UPI received",
            sms: "Received Rs.500.00 in your Kotak Bank AC X1234 from abc@okaxis on 17-10-26.UPI Ref:629012345678.",
            expected: BankSMS(kind: .income, amountPaise: 50000, counterparty: "abc", accountTail: "1234", reference: "629012345678")
        ),
        SMSCase(
            label: "Card refund",
            sms: "Refund of Rs 499.00 from AMAZON credited to your HDFC Bank Card 1234 on 17-10-26",
            expected: BankSMS(kind: .income, amountPaise: 49900, counterparty: "AMAZON", accountTail: "1234")
        ),
    ]

    @Test(arguments: transactions)
    func readsTransaction(_ testCase: SMSCase) {
        #expect(BankSMSParser.parse(testCase.sms) == testCase.expected)
    }

    static let notTransactions: [String] = [
        "123456 is the OTP for your transaction of Rs.2,500.00 at AMAZON on HDFC Bank Card 1234. Valid for 10 mins. Do not share it with anyone",
        "Your HDFC Bank Credit Card bill of Rs.12,345.00 is due on 25-10-26. Pay now to avoid charges.",
        "Your UPI transaction of Rs.250.00 to SWIGGY has failed. Amount if debited will be refunded within 3 working days.",
        "ABC has requested money from you on Google Pay. On approving the request, INR 500.00 will be debited from your account.",
        "Get a pre-approved personal loan of Rs 5,00,000 instantly. Apply now!",
        "Thank you for your payment of Rs.12,345.00 towards your HDFC Bank Credit Card ending 1234.",
        "Payment of Rs 12,345.00 received towards your SBI Credit Card ending 1234 on 17/10/26.",
        "Your A/c XX1234 balance is Rs 12,345.00 as on 17-10-26.",
        "Rs.499.00 will be debited from your A/c XX1234 on 20-10-26 towards NETFLIX mandate.",
    ]

    @Test(arguments: notTransactions)
    func ignoresNonTransaction(_ sms: String) {
        #expect(BankSMSParser.parse(sms) == nil)
    }
}

@Suite("Formatting")
struct FormattingTests {
    @Test func wholeRupees() {
        #expect(Rupees.format(paise: 25000) == "₹250")
    }

    @Test func rupeesAndPaise() {
        #expect(Rupees.format(paise: 25050) == "₹250.50")
    }

    @Test func indianGrouping() {
        #expect(Rupees.format(paise: 12_345_600) == "₹1,23,456")
    }

    @Test(arguments: [
        ("SWIGGY", "swiggy"),
        ("swiggy", "swiggy"),
        ("Swiggy Ltd", "swiggy"),
        ("ACME PVT LTD", "acme"),
        ("Zomato", "zomato"),
    ])
    func merchantKey(_ name: String, _ key: String) {
        #expect(MerchantKey.make(name) == key)
    }
}
