import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum CSVExport {
    static func csv(for entries: [LedgerEntry]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = ["Date,Type,Amount,Category,Merchant,Note,Source"]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let fields = [
                formatter.string(from: entry.date),
                entry.flow.rawValue,
                String(format: "%d.%02d", entry.amountPaise / 100, entry.amountPaise % 100),
                entry.category?.name ?? "",
                entry.merchant ?? "",
                entry.note,
                entry.source.rawValue,
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// A CSV the share sheet can save or send.
struct CSVFile: Transferable {
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { file in
            Data(file.text.utf8)
        }
        .suggestedFileName("tme-export.csv")
    }
}
