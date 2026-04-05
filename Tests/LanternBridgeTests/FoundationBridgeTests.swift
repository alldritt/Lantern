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
        let result = try ctor([.double(0)]) // Unix epoch
        let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSince1970")!
        let ts = try prop.getter(result)
        #expect(ts == .double(0))
    }

    @Test func timeIntervalSince1970() throws {
        let ctor = registry.lookupConstructor("Date")!
        let date = try ctor([.double(1000000)])
        let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSince1970")!
        #expect(try prop.getter(date) == .double(1000000))
    }

    @Test func addingTimeInterval() throws {
        let ctor = registry.lookupConstructor("Date")!
        let date = try ctor([.double(0)])
        let method = registry.lookupMethod(typeName: "Date", selector: "addingTimeInterval")!
        let result = try method(date, [.double(3600)])
        let prop = registry.lookupProperty(typeName: "Date", name: "timeIntervalSince1970")!
        #expect(try prop.getter(result) == .double(3600))
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

    @Test func scheme() throws {
        let ctor = registry.lookupConstructor("URL")!
        let url = try ctor([.string("https://example.com")])
        let prop = registry.lookupProperty(typeName: "URL", name: "scheme")!
        #expect(try prop.getter(url) == .string("https"))
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
            #expect(s.count == 36) // UUID format: 8-4-4-4-12
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

    @Test func encodeSimpleValue() throws {
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

    @Test func decodeSimpleValue() throws {
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

    @Test func setAndGetString() throws {
        let defaults = registry.lookupStaticProperty(typeName: "UserDefaults", name: "standard")!
        let ud = try defaults.getter() // static property, receiver unused
        let setMethod = registry.lookupMethod(typeName: "UserDefaults", selector: "set")!
        let getMethod = registry.lookupMethod(typeName: "UserDefaults", selector: "string")!

        let key = "lantern_test_\(UUID().uuidString)"
        _ = try setMethod(ud, [.string("hello"), .string(key)])
        let result = try getMethod(ud, [.string(key)])
        #expect(result == .string("hello"))

        // Cleanup
        let removeMethod = registry.lookupMethod(typeName: "UserDefaults", selector: "removeObject")!
        _ = try removeMethod(ud, [.string(key)])
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

    @Test func formatDate() throws {
        let fmtCtor = registry.lookupConstructor("DateFormatter")!
        let fmt = try fmtCtor([])
        // Set format
        let fmtProp = registry.lookupProperty(typeName: "DateFormatter", name: "dateFormat")!
        try fmtProp.setter!(fmt, .string("yyyy"))
        // Create a date well into 2024
        let dateCtor = registry.lookupConstructor("Date")!
        let date = try dateCtor([.double(1718409600)]) // 2024-06-15
        // Format it
        let strMethod = registry.lookupMethod(typeName: "DateFormatter", selector: "string")!
        let result = try strMethod(fmt, [date])
        #expect(result == .string("2024"))
    }
}

// MARK: - NumberFormatter Bridge

@Suite("NumberFormatter Bridge")
struct NumberFormatterBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerNumberFormatterBridge(on: r); return r
    }()

    @Test func formatNumber() throws {
        let ctor = registry.lookupConstructor("NumberFormatter")!
        let fmt = try ctor([])
        let method = registry.lookupMethod(typeName: "NumberFormatter", selector: "string")!
        let result = try method(fmt, [.int(42)])
        if case .string(let s) = result {
            #expect(s.contains("42"))
        } else {
            Issue.record("Expected string")
        }
    }

    @Test func parseNumber() throws {
        let ctor = registry.lookupConstructor("NumberFormatter")!
        let fmt = try ctor([])
        let method = registry.lookupMethod(typeName: "NumberFormatter", selector: "number")!
        let result = try method(fmt, [.string("3.14")])
        if case .double(let d) = result {
            #expect(abs(d - 3.14) < 0.01)
        } else {
            Issue.record("Expected double, got \(result)")
        }
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

    @Test func calendarCurrent() throws {
        let prop = registry.lookupStaticProperty(typeName: "Calendar", name: "current")!
        let cal = try prop.getter()
        #expect(cal.hostObjectRef?.typeName == "Calendar")
    }

    @Test func dateComponents() throws {
        let calProp = registry.lookupStaticProperty(typeName: "Calendar", name: "current")!
        let cal = try calProp.getter()
        // Create a known date: 2024-06-15
        let dateCtor = registry.lookupConstructor("Date")!
        let date = try dateCtor([.double(1718409600)]) // approx 2024-06-15
        let method = registry.lookupMethod(typeName: "Calendar", selector: "dateComponents")!
        let result = try method(cal, [.nil_, date])
        if case .dictionary(let d) = result {
            #expect(d["year"] == .int(2024))
        } else {
            Issue.record("Expected dictionary, got \(result)")
        }
    }

    @Test func isDateInToday() throws {
        let calProp = registry.lookupStaticProperty(typeName: "Calendar", name: "current")!
        let cal = try calProp.getter()
        let dateCtor = registry.lookupConstructor("Date")!
        let today = try dateCtor([])
        let method = registry.lookupMethod(typeName: "Calendar", selector: "isDateInToday")!
        #expect(try method(cal, [today]) == .bool(true))
    }
}

// MARK: - Data Bridge

@Suite("Data Bridge")
struct DataBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerDataBridge(on: r); return r
    }()

    @Test func dataFromString() throws {
        let ctor = registry.lookupConstructor("Data")!
        let data = try ctor([.string("hello")])
        let countProp = registry.lookupProperty(typeName: "Data", name: "count")!
        #expect(try countProp.getter(data) == .int(5))
    }

    @Test func base64() throws {
        let ctor = registry.lookupConstructor("Data")!
        let data = try ctor([.string("hello")])
        let method = registry.lookupMethod(typeName: "Data", selector: "base64EncodedString")!
        let result = try method(data, [])
        #expect(result == .string("aGVsbG8="))
    }

    @Test func dataToString() throws {
        let ctor = registry.lookupConstructor("Data")!
        let data = try ctor([.string("hello")])
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
        let method = registry.lookupMethod(typeName: "String", selector: "components")!
        let result = try method(.string("a,b,c"), [.string(",")])
        #expect(result == .array([.string("a"), .string("b"), .string("c")]))
    }

    @Test func startsWith() throws {
        let method = registry.lookupMethod(typeName: "String", selector: "starts")!
        #expect(try method(.string("hello"), [.string("hel")]) == .bool(true))
        #expect(try method(.string("hello"), [.string("world")]) == .bool(false))
    }

    @Test func regexMatch() throws {
        let method = registry.lookupMethod(typeName: "String", selector: "matches")!
        #expect(try method(.string("hello123"), [.string("[0-9]+")]) == .bool(true))
        #expect(try method(.string("hello"), [.string("^[0-9]+$")]) == .bool(false))
    }

    @Test func capitalized() throws {
        let prop = registry.lookupProperty(typeName: "String", name: "capitalized")!
        #expect(try prop.getter(.string("hello world")) == .string("Hello World"))
    }

    @Test func percentEncoding() throws {
        let method = registry.lookupMethod(typeName: "String", selector: "addingPercentEncoding")!
        let result = try method(.string("hello world"), [])
        if case .string(let s) = result {
            #expect(s.contains("%20") || s.contains("+"))
        }
    }
}

// MARK: - Timer Bridge

@Suite("Timer Bridge")
struct TimerBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerTimerBridge(on: r); return r
    }()

    @Test func timerProperties() throws {
        let method = registry.lookupMethod(typeName: "Timer", selector: "invalidate")!
        // Just verify the method exists
        #expect(method != nil)
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
        // Should not throw
        _ = try method(center, [.string("TestNotification")])
    }
}

// MARK: - Bundle Bridge

@Suite("Bundle Bridge")
struct BundleBridgeTests {
    let registry: BridgeRegistry = {
        let r = BridgeRegistry(); registerBundleBridge(on: r); return r
    }()

    @Test func mainBundle() throws {
        let prop = registry.lookupStaticProperty(typeName: "Bundle", name: "main")!
        let bundle = try prop.getter()
        #expect(bundle.hostObjectRef?.typeName == "Bundle")
    }

    @Test func infoDictionary() throws {
        let prop = registry.lookupStaticProperty(typeName: "Bundle", name: "main")!
        let bundle = try prop.getter()
        let infoProp = registry.lookupProperty(typeName: "Bundle", name: "infoDictionary")!
        let info = try infoProp.getter(bundle)
        // Should be a dictionary (even if empty in test context)
        if case .dictionary = info {
            // OK
        } else if case .nil_ = info {
            // Also OK — test bundle may not have info dict
        } else {
            Issue.record("Expected dictionary or nil")
        }
    }
}
