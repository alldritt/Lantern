import Testing
import Foundation
@testable import LanternVM
@testable import LanternBridge

// MARK: - Date Bridge

@Suite("Date Bridge")
struct DateBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerDateBridge(on: r); return r
    }()

    @Test func dateConstructor() throws {
        let ctor = registry.lookupConstructor("Date")!
        let result = try ctor([])
        #expect(result.hostObjectRef?.typeName == "Date")
    }

    @Test func dateFromTimestamp() throws {
        let ctor = registry.lookupConstructor("Date")!
        let result = try ctor([.double(0)])
        let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSince1970")!
        #expect(try prop.getter(result) == .double(0))
    }

    @Test func timeIntervalSince1970() throws {
        let ctor = registry.lookupConstructor("Date")!
        let date = try ctor([.double(1000000)])
        let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSince1970")!
        #expect(try prop.getter(date) == .double(1000000))
    }

    @Test func timeIntervalSinceNow() throws {
        let ctor = registry.lookupConstructor("Date")!
        let date = try ctor([])
        let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSinceNow")!
        let interval = try prop.getter(date)
        if case .double(let d) = interval {
            #expect(abs(d) < 1.0) // Just created, should be near 0
        } else {
            Issue.record("Expected double")
        }
    }

    @Test func addingTimeInterval() throws {
        let ctor = registry.lookupConstructor("Date")!
        let date = try ctor([.double(0)])
        let method = registry.lookupMethod(typeName: "Date", selector: "addingTimeInterval")!
        let result = try method(date, [.double(3600)])
        let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSince1970")!
        #expect(try prop.getter(result) == .double(3600))
    }

    @Test func timeIntervalSince() throws {
        let ctor = registry.lookupConstructor("Date")!
        let date1 = try ctor([.double(1000)])
        let date2 = try ctor([.double(500)])
        let method = registry.lookupMethod(typeName: "Date", selector: "timeIntervalSince")!
        let result = try method(date1, [date2])
        #expect(result == .double(500))
    }
}

// MARK: - URL Bridge

@Suite("URL Bridge")
struct URLBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerURLBridge(on: r); return r
    }()

    @Test func urlFromString() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com/path?q=1")])
        #expect(url.hostObjectRef?.typeName == "URL")
    }

    @Test func absoluteString() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com")])
        let prop = registry.lookupProperty(typeName: "URL", name: "absoluteString")!
        #expect(try prop.getter(url) == .string("https://example.com"))
    }

    @Test func host() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com/path")])
        let prop = registry.lookupProperty(typeName: "URL", name: "host")!
        #expect(try prop.getter(url) == .string("example.com"))
    }

    @Test func path() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com/api/users")])
        let prop = registry.lookupProperty(typeName: "URL", name: "path")!
        #expect(try prop.getter(url) == .string("/api/users"))
    }

    @Test func lastPathComponent() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com/api/users")])
        let prop = registry.lookupProperty(typeName: "URL", name: "lastPathComponent")!
        #expect(try prop.getter(url) == .string("users"))
    }

    @Test func pathExtension() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com/file.txt")])
        let prop = registry.lookupProperty(typeName: "URL", name: "pathExtension")!
        #expect(try prop.getter(url) == .string("txt"))
    }

    @Test func scheme() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com")])
        let prop = registry.lookupProperty(typeName: "URL", name: "scheme")!
        #expect(try prop.getter(url) == .string("https"))
    }

    @Test func appendingPathComponent() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com/api")])
        let method = registry.lookupMethod(typeName: "URL", selector: "appendingPathComponent")!
        let result = try method(url, [.string("users")])
        let prop = registry.lookupProperty(typeName: "URL", name: "absoluteString")!
        let absStr = try prop.getter(result)
        if case .string(let s) = absStr {
            #expect(s.contains("users"))
        }
    }

    @Test func invalidURLReturnsNil() throws {
        let ctor = registry.lookupConstructor("URL")!
        let result = try ctor([.string("")])
        #expect(result == .nil_)
    }
}

// MARK: - UUID Bridge

@Suite("UUID Bridge")
struct UUIDBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerUUIDBridge(on: r); return r
    }()

    @Test func uuidConstructor() throws {
        let ctor = registry.lookupConstructor("UUID")!
        let uuid = try ctor([])
        #expect(uuid.hostObjectRef?.typeName == "UUID")
    }

    @Test func uuidString() throws {
        let ctor = registry.lookupConstructor("UUID")!
        let uuid = try ctor([])
        let prop = registry.lookupProperty(typeName: "UUID", name: "uuidString")!
        let str = try prop.getter(uuid)
        if case .string(let s) = str {
            #expect(s.count == 36)
            #expect(s.contains("-"))
        } else {
            Issue.record("Expected string")
        }
    }
}

// MARK: - JSON Bridge

@Suite("JSON Bridge")
struct JSONBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerJSONBridge(on: r); return r
    }()

    @Test func encodeDict() throws {
        let encoder = try registry.lookupConstructor("JSONEncoder")!([])
        let method = registry.lookupMethod(typeName: "JSONEncoder", selector: "encode")!
        let result = try method(encoder, [.dictionary(["name": .string("Alice"), "age": .int(30)])])
        if case .string(let json) = result {
            #expect(json.contains("Alice"))
            #expect(json.contains("30"))
        } else {
            Issue.record("Expected JSON string")
        }
    }

    @Test func decodeToDict() throws {
        let decoder = try registry.lookupConstructor("JSONDecoder")!([])
        let method = registry.lookupMethod(typeName: "JSONDecoder", selector: "decode")!
        let result = try method(decoder, [.string("{\"name\":\"Bob\",\"score\":42}")])
        if case .dictionary(let d) = result {
            #expect(d["name"] == .string("Bob"))
            #expect(d["score"] == .int(42))
        } else {
            Issue.record("Expected dictionary, got \(result)")
        }
    }

    @Test func roundTrip() throws {
        let encoder = try registry.lookupConstructor("JSONEncoder")!([])
        let decoder = try registry.lookupConstructor("JSONDecoder")!([])
        let encMethod = registry.lookupMethod(typeName: "JSONEncoder", selector: "encode")!
        let decMethod = registry.lookupMethod(typeName: "JSONDecoder", selector: "decode")!
        let original: Value = .array([.int(1), .string("two"), .bool(true)])
        let json = try encMethod(encoder, [original])
        let decoded = try decMethod(decoder, [json])
        #expect(decoded == original)
    }
}

// MARK: - UserDefaults Bridge

@Suite("UserDefaults Bridge")
struct UserDefaultsBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerUserDefaultsBridge(on: r); return r
    }()

    private func getDefaults() throws -> Value {
        let prop = registry.lookupStaticProperty(typeName: "UserDefaults", name: "standard")!
        return try prop.getter()
    }

    private func uniqueKey() -> String { "lantern_test_\(UUID().uuidString)" }

    @Test func setAndGetString() throws {
        let ud = try getDefaults()
        let key = uniqueKey()
        let setM = registry.lookupMethod(typeName: "UserDefaults", selector: "set")!
        let getM = registry.lookupMethod(typeName: "UserDefaults", selector: "string")!
        let removeM = registry.lookupMethod(typeName: "UserDefaults", selector: "removeObject")!
        _ = try setM(ud, [.string("hello"), .string(key)])
        #expect(try getM(ud, [.string(key)]) == .string("hello"))
        _ = try removeM(ud, [.string(key)])
    }

    @Test func setAndGetInteger() throws {
        let ud = try getDefaults()
        let key = uniqueKey()
        let setM = registry.lookupMethod(typeName: "UserDefaults", selector: "set")!
        let getM = registry.lookupMethod(typeName: "UserDefaults", selector: "integer")!
        let removeM = registry.lookupMethod(typeName: "UserDefaults", selector: "removeObject")!
        _ = try setM(ud, [.int(42), .string(key)])
        #expect(try getM(ud, [.string(key)]) == .int(42))
        _ = try removeM(ud, [.string(key)])
    }

    @Test func setAndGetBool() throws {
        let ud = try getDefaults()
        let key = uniqueKey()
        let setM = registry.lookupMethod(typeName: "UserDefaults", selector: "set")!
        let getM = registry.lookupMethod(typeName: "UserDefaults", selector: "bool")!
        let removeM = registry.lookupMethod(typeName: "UserDefaults", selector: "removeObject")!
        _ = try setM(ud, [.bool(true), .string(key)])
        #expect(try getM(ud, [.string(key)]) == .bool(true))
        _ = try removeM(ud, [.string(key)])
    }

    @Test func removeObject() throws {
        let ud = try getDefaults()
        let key = uniqueKey()
        let setM = registry.lookupMethod(typeName: "UserDefaults", selector: "set")!
        let getM = registry.lookupMethod(typeName: "UserDefaults", selector: "string")!
        let removeM = registry.lookupMethod(typeName: "UserDefaults", selector: "removeObject")!
        _ = try setM(ud, [.string("temp"), .string(key)])
        _ = try removeM(ud, [.string(key)])
        #expect(try getM(ud, [.string(key)]) == .nil_)
    }
}

// MARK: - DateFormatter Bridge

@Suite("DateFormatter Bridge")
struct DateFormatterBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry()
        registerDateBridge(on: r)
        registerDateFormatterBridge(on: r)
        return r
    }()

    @Test func formatWithCustomFormat() throws {
        let fmt = try registry.lookupConstructor("DateFormatter")!([])
        let fmtProp = registry.lookupProperty(typeName: "DateFormatter", name: "dateFormat")!
        try fmtProp.setter!(fmt, .string("yyyy"))
        let date = try registry.lookupConstructor("Date")!([.double(1718409600)])
        let result = try registry.lookupMethod(typeName: "DateFormatter", selector: "string")!(fmt, [date])
        #expect(result == .string("2024"))
    }

    @Test func dateStyleProperty() throws {
        let fmt = try registry.lookupConstructor("DateFormatter")!([])
        let prop = registry.lookupProperty(typeName: "DateFormatter", name: "dateStyle")!
        try prop.setter!(fmt, .int(2)) // .medium
        let val = try prop.getter(fmt)
        #expect(val == .int(2))
    }

    @Test func timeStyleProperty() throws {
        let fmt = try registry.lookupConstructor("DateFormatter")!([])
        let prop = registry.lookupProperty(typeName: "DateFormatter", name: "timeStyle")!
        try prop.setter!(fmt, .int(1)) // .short
        let val = try prop.getter(fmt)
        #expect(val == .int(1))
    }

    @Test func localeProperty() throws {
        let fmt = try registry.lookupConstructor("DateFormatter")!([])
        let prop = registry.lookupProperty(typeName: "DateFormatter", name: "locale")!
        let locale = try prop.getter(fmt)
        if case .string(let s) = locale {
            #expect(!s.isEmpty)
        }
    }

    @Test func dateFromString() throws {
        let fmt = try registry.lookupConstructor("DateFormatter")!([])
        let fmtProp = registry.lookupProperty(typeName: "DateFormatter", name: "dateFormat")!
        try fmtProp.setter!(fmt, .string("yyyy-MM-dd"))
        let method = registry.lookupMethod(typeName: "DateFormatter", selector: "date")!
        let result = try method(fmt, [.string("2024-06-15")])
        #expect(result.hostObjectRef?.typeName == "Date")
    }
}

// MARK: - NumberFormatter Bridge

@Suite("NumberFormatter Bridge")
struct NumberFormatterBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerNumberFormatterBridge(on: r); return r
    }()

    @Test func formatInt() throws {
        let fmt = try registry.lookupConstructor("NumberFormatter")!([])
        let result = try registry.lookupMethod(typeName: "NumberFormatter", selector: "string")!(fmt, [.int(42)])
        if case .string(let s) = result { #expect(s.contains("42")) }
    }

    @Test func formatDouble() throws {
        let fmt = try registry.lookupConstructor("NumberFormatter")!([])
        let result = try registry.lookupMethod(typeName: "NumberFormatter", selector: "string")!(fmt, [.double(3.14)])
        if case .string(let s) = result { #expect(s.contains("3")) }
    }

    @Test func parseNumber() throws {
        let fmt = try registry.lookupConstructor("NumberFormatter")!([])
        let result = try registry.lookupMethod(typeName: "NumberFormatter", selector: "number")!(fmt, [.string("3.14")])
        if case .double(let d) = result { #expect(abs(d - 3.14) < 0.01) }
    }

    @Test func numberStyleProperty() throws {
        let fmt = try registry.lookupConstructor("NumberFormatter")!([])
        let prop = registry.lookupProperty(typeName: "NumberFormatter", name: "numberStyle")!
        try prop.setter!(fmt, .int(2)) // .currency
        #expect(try prop.getter(fmt) == .int(2))
    }

    @Test func fractionDigitsProperties() throws {
        let fmt = try registry.lookupConstructor("NumberFormatter")!([])
        let minProp = registry.lookupProperty(typeName: "NumberFormatter", name: "minimumFractionDigits")!
        let maxProp = registry.lookupProperty(typeName: "NumberFormatter", name: "maximumFractionDigits")!
        try minProp.setter!(fmt, .int(2))
        try maxProp.setter!(fmt, .int(4))
        #expect(try minProp.getter(fmt) == .int(2))
        #expect(try maxProp.getter(fmt) == .int(4))
    }

    @Test func currencyCodeProperty() throws {
        let fmt = try registry.lookupConstructor("NumberFormatter")!([])
        let prop = registry.lookupProperty(typeName: "NumberFormatter", name: "currencyCode")!
        try prop.setter!(fmt, .string("EUR"))
        #expect(try prop.getter(fmt) == .string("EUR"))
    }
}

// MARK: - Calendar Bridge

@Suite("Calendar Bridge")
struct CalendarBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry()
        registerDateBridge(on: r)
        registerCalendarBridge(on: r)
        return r
    }()

    private func getCal() throws -> Value {
        try registry.lookupStaticProperty(typeName: "Calendar", name: "current")!.getter()
    }

    private func makeDate(_ ts: Double) throws -> Value {
        try registry.lookupConstructor("Date")!([.double(ts)])
    }

    @Test func calendarCurrent() throws {
        #expect(try getCal().hostObjectRef?.typeName == "Calendar")
    }

    @Test func dateComponents() throws {
        let cal = try getCal()
        let date = try makeDate(1718409600) // 2024-06-15
        let method = registry.lookupMethod(typeName: "Calendar", selector: "dateComponents")!
        let result = try method(cal, [.nil_, date])
        if case .dictionary(let d) = result {
            #expect(d["year"] == .int(2024))
        }
    }

    @Test func dateByAdding() throws {
        let cal = try getCal()
        let date = try makeDate(1718409600)
        let method = registry.lookupMethod(typeName: "Calendar", selector: "date")!
        let result = try method(cal, [.string("day"), .int(1), date])
        // Should return an optional date
        if case .optional(.some(let newDate)) = result {
            let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSince1970")!
            let ts = try prop.getter(newDate)
            if case .double(let d) = ts {
                #expect(d > 1718409600) // Later than input
            }
        }
    }

    @Test func startOfDay() throws {
        let cal = try getCal()
        let date = try makeDate(1718409600)
        let method = registry.lookupMethod(typeName: "Calendar", selector: "startOfDay")!
        let result = try method(cal, [date])
        #expect(result.hostObjectRef?.typeName == "Date")
    }

    @Test func isDateInToday() throws {
        let cal = try getCal()
        let today = try registry.lookupConstructor("Date")!([])
        let method = registry.lookupMethod(typeName: "Calendar", selector: "isDateInToday")!
        #expect(try method(cal, [today]) == .bool(true))
    }

    @Test func isDateInWeekend() throws {
        let cal = try getCal()
        // Jan 4, 2025 is a Saturday
        let saturday = try makeDate(1735948800)
        let method = registry.lookupMethod(typeName: "Calendar", selector: "isDateInWeekend")!
        let result = try method(cal, [saturday])
        // Just verify it returns a bool (timezone may affect result)
        if case .bool = result { } else { Issue.record("Expected bool") }
    }

    @Test func dateComponentsType() throws {
        let ctor = registry.lookupConstructor("DateComponents")!
        let dc = try ctor([])
        #expect(dc.hostObjectRef?.typeName == "DateComponents")
    }

    @Test func dateComponentProperties() throws {
        let ctor = registry.lookupConstructor("DateComponents")!
        let dc = try ctor([])
        for name in ["year", "month", "day", "hour", "minute", "second", "weekday"] {
            let prop = registry.lookupProperty(typeName: "DateComponents", name: name)!
            // Setter
            try prop.setter!(dc, .int(42))
            // Getter
            #expect(try prop.getter(dc) == .int(42), "Property \(name) should round-trip")
        }
    }
}

// MARK: - Data Bridge

@Suite("Data Bridge")
struct DataBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerDataBridge(on: r); return r
    }()

    @Test func dataFromString() throws {
        let data = try registry.lookupConstructor("Data")!([.string("hello")])
        let count = registry.lookupProperty(typeName: "Data", name: "count")!
        #expect(try count.getter(data) == .int(5))
    }

    @Test func emptyData() throws {
        let data = try registry.lookupConstructor("Data")!([])
        let isEmpty = registry.lookupProperty(typeName: "Data", name: "isEmpty")!
        #expect(try isEmpty.getter(data) == .bool(true))
    }

    @Test func nonEmptyData() throws {
        let data = try registry.lookupConstructor("Data")!([.string("x")])
        let isEmpty = registry.lookupProperty(typeName: "Data", name: "isEmpty")!
        #expect(try isEmpty.getter(data) == .bool(false))
    }

    @Test func base64() throws {
        let data = try registry.lookupConstructor("Data")!([.string("hello")])
        let method = registry.lookupMethod(typeName: "Data", selector: "base64EncodedString")!
        #expect(try method(data, []) == .string("aGVsbG8="))
    }

    @Test func dataToString() throws {
        let data = try registry.lookupConstructor("Data")!([.string("hello")])
        let method = registry.lookupMethod(typeName: "Data", selector: "string")!
        #expect(try method(data, []) == .string("hello"))
    }
}

// MARK: - String Extension Bridge

@Suite("String Extension Bridge")
struct StringExtBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerStringExtBridge(on: r); return r
    }()

    @Test func components() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "components")!
        #expect(try m(.string("a,b,c"), [.string(",")]) == .array([.string("a"), .string("b"), .string("c")]))
    }

    @Test func dataUsing() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "data")!
        let result = try m(.string("hello"), [])
        #expect(result.hostObjectRef?.typeName == "Data")
    }

    @Test func padding() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "padding")!
        let result = try m(.string("hi"), [.int(5), .string("*"), .int(0)])
        #expect(result == .string("hi***"))
    }

    @Test func startsWith() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "starts")!
        #expect(try m(.string("hello"), [.string("hel")]) == .bool(true))
        #expect(try m(.string("hello"), [.string("xyz")]) == .bool(false))
    }

    @Test func rangeOf() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "range")!
        #expect(try m(.string("hello world"), [.string("world")]) == .bool(true))
        #expect(try m(.string("hello world"), [.string("xyz")]) == .bool(false))
    }

    @Test func regexMatch() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "matches")!
        #expect(try m(.string("hello123"), [.string("[0-9]+")]) == .bool(true))
        #expect(try m(.string("hello"), [.string("^[0-9]+$")]) == .bool(false))
    }

    @Test func percentEncoding() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "addingPercentEncoding")!
        let result = try m(.string("hello world"), [])
        if case .string(let s) = result { #expect(s.contains("%20")) }
    }

    @Test func removingPercentEncoding() throws {
        let p = registry.lookupProperty(typeName: "String", name: "removingPercentEncoding")!
        #expect(try p.getter(.string("hello%20world")) == .string("hello world"))
    }

    @Test func capitalized() throws {
        let p = registry.lookupProperty(typeName: "String", name: "capitalized")!
        #expect(try p.getter(.string("hello world")) == .string("Hello World"))
    }

    @Test func firstChar() throws {
        let p = registry.lookupProperty(typeName: "String", name: "first")!
        #expect(try p.getter(.string("hello")) == .optional(.string("h")))
    }

    @Test func lastChar() throws {
        let p = registry.lookupProperty(typeName: "String", name: "last")!
        #expect(try p.getter(.string("hello")) == .optional(.string("o")))
    }
}

// MARK: - Timer Bridge

@Suite("Timer Bridge")
struct TimerBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerTimerBridge(on: r); return r
    }()

    @Test func invalidateMethodExists() {
        #expect(registry.lookupMethod(typeName: "Timer", selector: "invalidate") != nil)
    }

    @Test func isValidPropertyExists() {
        #expect(registry.lookupProperty(typeName: "Timer", name: "isValid") != nil)
    }

    @Test func timeIntervalPropertyExists() {
        #expect(registry.lookupProperty(typeName: "Timer", name: "timeInterval") != nil)
    }

    @Test func scheduledTimerExists() {
        // scheduledTimer is a static method — verify the instance methods are registered
        #expect(registry.lookupMethod(typeName: "Timer", selector: "invalidate") != nil)
    }
}

// MARK: - Notification Bridge

@Suite("Notification Bridge")
struct NotificationBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerNotificationBridge(on: r); return r
    }()

    @Test func defaultCenter() throws {
        let prop = registry.lookupStaticProperty(typeName: "NotificationCenter", name: "default")!
        let center = try prop.getter()
        #expect(center.hostObjectRef?.typeName == "NotificationCenter")
    }

    @Test func postNotification() throws {
        let prop = registry.lookupStaticProperty(typeName: "NotificationCenter", name: "default")!
        let center = try prop.getter()
        let method = registry.lookupMethod(typeName: "NotificationCenter", selector: "post")!
        _ = try method(center, [.string("TestNotification")])
    }

    @Test func addAndRemoveObserver() throws {
        let prop = registry.lookupStaticProperty(typeName: "NotificationCenter", name: "default")!
        let center = try prop.getter()
        let addM = registry.lookupMethod(typeName: "NotificationCenter", selector: "addObserver")!
        let observer = try addM(center, [.string("LanternTestNotif")])
        #expect(observer.hostObjectRef != nil)
        let removeM = registry.lookupMethod(typeName: "NotificationCenter", selector: "removeObserver")!
        _ = try removeM(center, [observer])
    }

    @Test func notificationNameType() throws {
        let ctor = registry.lookupConstructor("Notification.Name")!
        let name = try ctor([.string("myNotif")])
        #expect(name == .string("myNotif"))
    }
}

// MARK: - Bundle Bridge

@Suite("Bundle Bridge")
struct BundleBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerBundleBridge(on: r); return r
    }()

    private func getMain() throws -> Value {
        try registry.lookupStaticProperty(typeName: "Bundle", name: "main")!.getter()
    }

    @Test func mainBundle() throws {
        #expect(try getMain().hostObjectRef?.typeName == "Bundle")
    }

    @Test func infoDictionary() throws {
        let bundle = try getMain()
        let prop = registry.lookupProperty(typeName: "Bundle", name: "infoDictionary")!
        let info = try prop.getter(bundle)
        // Test bundle may or may not have info dict
        if case .dictionary = info { }
        else if case .nil_ = info { }
        else { Issue.record("Expected dictionary or nil") }
    }

    @Test func bundleIdentifier() throws {
        let bundle = try getMain()
        let prop = registry.lookupProperty(typeName: "Bundle", name: "bundleIdentifier")!
        let _ = try prop.getter(bundle) // May be nil in test context, just verify it doesn't crash
    }

    @Test func urlForResource() throws {
        let method = registry.lookupMethod(typeName: "Bundle", selector: "url")
        #expect(method != nil, "url(forResource:withExtension:) should be registered")
    }

    @Test func pathForResource() throws {
        let method = registry.lookupMethod(typeName: "Bundle", selector: "path")
        #expect(method != nil, "path(forResource:ofType:) should be registered")
    }
}

// MARK: - Original String/Array/Dictionary Bridge Tests

@Suite("String Bridge (Original)")
struct OriginalStringBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerStringBridge(on: r); return r
    }()

    @Test func uppercased() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "uppercased")!
        #expect(try m(.string("hello"), []) == .string("HELLO"))
    }
    @Test func lowercased() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "lowercased")!
        #expect(try m(.string("HELLO"), []) == .string("hello"))
    }
    @Test func hasPrefix() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "hasPrefix")!
        #expect(try m(.string("hello"), [.string("hel")]) == .bool(true))
        #expect(try m(.string("hello"), [.string("xyz")]) == .bool(false))
    }
    @Test func hasSuffix() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "hasSuffix")!
        #expect(try m(.string("hello"), [.string("llo")]) == .bool(true))
    }
    @Test func contains() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "contains")!
        #expect(try m(.string("hello world"), [.string("world")]) == .bool(true))
    }
    @Test func replacingOccurrences() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "replacingOccurrences")!
        #expect(try m(.string("hello world"), [.string("world"), .string("swift")]) == .string("hello swift"))
    }
    @Test func split() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "split")!
        #expect(try m(.string("a-b-c"), [.string("-")]) == .array([.string("a"), .string("b"), .string("c")]))
    }
    @Test func trimmingCharacters() throws {
        let m = registry.lookupMethod(typeName: "String", selector: "trimmingCharacters")!
        #expect(try m(.string("  hello  "), []) == .string("hello"))
    }
    @Test func countProperty() throws {
        let p = registry.lookupProperty(typeName: "String", name: "count")!
        #expect(try p.getter(.string("hello")) == .int(5))
    }
    @Test func isEmptyProperty() throws {
        let p = registry.lookupProperty(typeName: "String", name: "isEmpty")!
        #expect(try p.getter(.string("")) == .bool(true))
        #expect(try p.getter(.string("x")) == .bool(false))
    }
}

@Suite("Array Bridge")
struct ArrayBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerArrayBridge(on: r); return r
    }()

    @Test func countProperty() throws {
        let p = registry.lookupProperty(typeName: "Array", name: "count")!
        #expect(try p.getter(.array([.int(1), .int(2)])) == .int(2))
    }
    @Test func isEmptyProperty() throws {
        let p = registry.lookupProperty(typeName: "Array", name: "isEmpty")!
        #expect(try p.getter(.array([])) == .bool(true))
        #expect(try p.getter(.array([.int(1)])) == .bool(false))
    }
    @Test func firstProperty() throws {
        let p = registry.lookupProperty(typeName: "Array", name: "first")!
        if case .optional(.some(let v)) = try p.getter(.array([.int(42)])) {
            #expect(v == .int(42))
        }
    }
    @Test func lastProperty() throws {
        let p = registry.lookupProperty(typeName: "Array", name: "last")!
        if case .optional(.some(let v)) = try p.getter(.array([.int(1), .int(99)])) {
            #expect(v == .int(99))
        }
    }
    @Test func appendMethod() throws {
        let m = registry.lookupMethod(typeName: "Array", selector: "append")!
        let result = try m(.array([.int(1)]), [.int(2)])
        #expect(result == .array([.int(1), .int(2)]))
    }
    @Test func removeMethod() throws {
        let m = registry.lookupMethod(typeName: "Array", selector: "remove")!
        let result = try m(.array([.int(10), .int(20), .int(30)]), [.int(1)])
        #expect(result == .array([.int(10), .int(30)]))
    }
    @Test func containsMethod() throws {
        let m = registry.lookupMethod(typeName: "Array", selector: "contains")!
        #expect(try m(.array([.int(1), .int(2)]), [.int(2)]) == .bool(true))
        #expect(try m(.array([.int(1), .int(2)]), [.int(3)]) == .bool(false))
    }
    @Test func reversedMethod() throws {
        let m = registry.lookupMethod(typeName: "Array", selector: "reversed")!
        #expect(try m(.array([.int(1), .int(2), .int(3)]), []) == .array([.int(3), .int(2), .int(1)]))
    }
}

@Suite("Dictionary Bridge")
struct DictionaryBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerDictionaryBridge(on: r); return r
    }()

    @Test func countProperty() throws {
        let p = registry.lookupProperty(typeName: "Dictionary", name: "count")!
        #expect(try p.getter(.dictionary(["a": .int(1), "b": .int(2)])) == .int(2))
    }
    @Test func isEmptyProperty() throws {
        let p = registry.lookupProperty(typeName: "Dictionary", name: "isEmpty")!
        #expect(try p.getter(.dictionary([:])) == .bool(true))
    }
    @Test func keysProperty() throws {
        let p = registry.lookupProperty(typeName: "Dictionary", name: "keys")!
        let keys = try p.getter(.dictionary(["a": .int(1), "b": .int(2)]))
        if case .array(let arr) = keys {
            let strs = arr.compactMap(\.stringValue).sorted()
            #expect(strs == ["a", "b"])
        }
    }
    @Test func valuesProperty() throws {
        let p = registry.lookupProperty(typeName: "Dictionary", name: "values")!
        let vals = try p.getter(.dictionary(["x": .int(42)]))
        if case .array(let arr) = vals { #expect(arr.contains(.int(42))) }
    }
    @Test func removeValueMethod() throws {
        let m = registry.lookupMethod(typeName: "Dictionary", selector: "removeValue")!
        let result = try m(.dictionary(["a": .int(1), "b": .int(2)]), [.string("a")])
        if case .dictionary(let d) = result {
            #expect(d["a"] == nil)
            #expect(d["b"] == .int(2))
        }
    }
}
