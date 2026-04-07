import Foundation

struct ArgumentParser {
    let arguments: [String]

    func contains(_ flag: String) -> Bool {
        arguments.contains(flag)
    }

    func value(for flag: String) throws -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }
        guard index + 1 < arguments.count else {
            throw CLIError.missingValue("Missing value for \(flag)")
        }
        return arguments[index + 1]
    }

    func intValue(for flag: String) throws -> Int? {
        guard let rawValue = try value(for: flag) else {
            return nil
        }
        guard let parsed = Int(rawValue) else {
            throw CLIError.invalidValue("Invalid integer for \(flag): \(rawValue)")
        }
        return parsed
    }

    func positionalArguments() -> [String] {
        var result: [String] = []
        var skipNext = false

        for (index, argument) in arguments.enumerated() {
            if skipNext {
                skipNext = false
                continue
            }

            if argument.hasPrefix("--") {
                if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                    skipNext = true
                }
                continue
            }

            result.append(argument)
        }

        return result
    }
}
