import Foundation

enum Output {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func printJSON<T: Encodable>(_ value: T) throws {
        let data = try encoder.encode(value)
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }

    static func printError(_ error: CLIError, mode: OutputMode) {
        switch mode {
        case .json:
            let payload = ErrorEnvelope(error: ErrorRecord(code: error.code, message: error.message, details: error.details))
            try? printJSON(payload)
        case .plain, .quiet:
            fputs("calctl: \(error.message)\n", stderr)
            if let details = error.details, !details.isEmpty, !(details.count == 1 && details[0] == error.message) {
                for detail in details {
                    fputs("  - \(detail)\n", stderr)
                }
            }
        }
    }
}
