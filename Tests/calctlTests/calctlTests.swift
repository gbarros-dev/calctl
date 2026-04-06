import Foundation
import Testing
@testable import calctl

@Test func resolvesTodayByDefault() throws {
    let now = Date(timeIntervalSince1970: 1_775_490_000)
    let timeZone = TimeZone(secondsFromGMT: 7_200)!
    let range = try DateRangeResolver.resolve(arguments: [], now: now, timeZone: timeZone)

    #expect(range.label == "today")
    #expect(range.end.timeIntervalSince(range.start) == 86_400)
}

@Test func resolvesExplicitDateRange() throws {
    let timeZone = TimeZone(secondsFromGMT: 0)!
    let range = try DateRangeResolver.resolve(
        arguments: ["--from", "2026-04-06", "--to", "2026-04-13"],
        timeZone: timeZone
    )

    #expect(range.label == "2026-04-06...2026-04-13")
    #expect(range.end.timeIntervalSince(range.start) == 8 * 86_400)
}

@Test func rejectsInvalidDateInput() throws {
    #expect(throws: CLIError.self) {
        try DateRangeResolver.resolve(arguments: ["--from", "2026-04-99", "--to", "2026-04-13"])
    }
}

@Test func parsesFlexibleLocalDateTime() throws {
    let parser = DateParser(timeZone: TimeZone(secondsFromGMT: 0)!)
    let date = try parser.parseFlexible("2026-04-06 18:30", flag: "--start")
    let iso = ISO8601DateFormatter()
    iso.timeZone = TimeZone(secondsFromGMT: 0)

    #expect(iso.string(from: date) == "2026-04-06T18:30:00Z")
}

@Test func preservesDateOnlyInput() throws {
    let parser = DateParser(timeZone: TimeZone(secondsFromGMT: 0)!)
    let date = try parser.parseFlexible("2026-04-06", flag: "--start")
    let iso = ISO8601DateFormatter()
    iso.timeZone = TimeZone(secondsFromGMT: 0)

    #expect(iso.string(from: date) == "2026-04-06T00:00:00Z")
}

@Test func extractsPositionalArguments() throws {
    let parser = ArgumentParser(arguments: ["dentist", "--calendar", "Personal", "--from", "2026-04-01", "--json"])
    #expect(parser.positionalArguments() == ["dentist"])
}

@Test func searchMatcherHandlesExactPhrase() throws {
    let matches = SearchMatcher.matches(
        query: "calctl smoke 2026-04-06 01",
        fields: ["calctl smoke 2026-04-06 01", nil, nil, nil]
    )
    #expect(matches)
}

@Test func searchMatcherHandlesTokenizedMatchAcrossWhitespace() throws {
    let matches = SearchMatcher.matches(
        query: "project kickoff review",
        fields: ["Project   kickoff", "Review room", nil, nil]
    )
    #expect(matches)
}

@Test func searchMatcherNormalizesCaseAndDiacritics() throws {
    let matches = SearchMatcher.matches(
        query: "cafe planning",
        fields: ["Café Planning", nil, nil, nil]
    )
    #expect(matches)
}

@Test func searchMatcherIgnoresPunctuationBoundaries() throws {
    let matches = SearchMatcher.matches(
        query: "probe 2026-04-06",
        fields: ["calctl exact search probe 2026-04-06", nil, nil, nil]
    )
    #expect(matches)
}
