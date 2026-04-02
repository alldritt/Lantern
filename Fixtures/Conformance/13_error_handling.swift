// Lantern Conformance Test Fixtures — Error Handling
// Each test is run through both Lantern and the Swift compiler.
// Output must match exactly.

// TEST: throw_and_catch
// EXPECT: caught: too small
enum ValidationError: Error {
case tooSmall
case tooLarge
}
func validate(_ n: Int) throws -> Int {
if n < 0 { throw ValidationError.tooSmall }
if n > 100 { throw ValidationError.tooLarge }
return n
}
do {
let _ = try validate(-5)
} catch ValidationError.tooSmall {
print("caught: too small")
} catch ValidationError.tooLarge {
print("caught: too large")
} catch {
print("caught: unknown")
}
// END

// TEST: throw_and_catch_success
// EXPECT: 42
do {
let result = try validate2(42)
print(result)
} catch {
print("error")
}

enum V2Error: Error { case bad }
func validate2(_ n: Int) throws -> Int {
if n < 0 { throw V2Error.bad }
return n
}
// END

// TEST: try_optional_success
// EXPECT: Optional(42)
enum OptErr: Error { case fail }
func mayFail(_ succeed: Bool) throws -> Int {
if !succeed { throw OptErr.fail }
return 42
}
let result = try? mayFail(true)
print(result as Any)
// END

// TEST: try_optional_failure
// EXPECT: nil
enum OptErr2: Error { case fail }
func mayFail2(_ succeed: Bool) throws -> Int {
if !succeed { throw OptErr2.fail }
return 42
}
let result2 = try? mayFail2(false)
print(result2 as Any)
// END

// TEST: catch_all
// EXPECT: got error
enum SomeError: Error { case oops }
func alwaysFails() throws {
throw SomeError.oops
}
do {
try alwaysFails()
} catch {
print("got error")
}
// END

// TEST: error_propagation
// EXPECT: caught at top
enum PropError: Error { case deep }
func level3() throws {
throw PropError.deep
}
func level2() throws {
try level3()
}
func level1() throws {
try level2()
}
do {
try level1()
} catch {
print("caught at top")
}
// END

// TEST: defer_normal_exit
// EXPECT: start
// end
// deferred
func withDefer() {
defer { print("deferred") }
print("start")
print("end")
}
withDefer()
// END

// TEST: defer_on_throw
// EXPECT: start
// deferred
// caught
enum DeferErr: Error { case boom }
func deferAndThrow() throws {
defer { print("deferred") }
print("start")
throw DeferErr.boom
}
do {
try deferAndThrow()
} catch {
print("caught")
}
// END

// TEST: multiple_defers_reverse_order
// EXPECT: first
// third
// second
func multiDefer() {
defer { print("second") }
defer { print("third") }
print("first")
}
multiDefer()
// END

// TEST: defer_on_early_return
// EXPECT: cleanup
func earlyReturn(_ flag: Bool) -> String {
defer { print("cleanup") }
if flag {
return "early"
}
return "normal"
}
let _ = earlyReturn(true)
// END

// TEST: nested_do_catch
// EXPECT: inner caught
// outer continues
enum NestErr: Error { case inner, outer }
do {
do {
throw NestErr.inner
} catch NestErr.inner {
print("inner caught")
}
print("outer continues")
} catch {
print("outer caught")
}
// END

// TEST: rethrow_pattern
// EXPECT: caught: rethrown
enum ReErr: Error { case original }
func riskyOperation() throws -> Int {
throw ReErr.original
}
func wrapper() throws -> Int {
return try riskyOperation()
}
do {
let _ = try wrapper()
} catch {
print("caught: rethrown")
}
// END

// TEST: error_with_associated_value
// EXPECT: not found: key123
enum LookupError: Error {
case notFound(key: String)
case accessDenied
}
func lookup(_ key: String) throws -> String {
throw LookupError.notFound(key: key)
}
do {
let _ = try lookup("key123")
} catch LookupError.notFound(let key) {
print("not found: \(key)")
} catch {
print("other error")
}
// END

// TEST: throwing_closure
// EXPECT: caught in closure
enum ClosureErr: Error { case fail }
let throwingClosure: () throws -> Void = {
throw ClosureErr.fail
}
do {
try throwingClosure()
} catch {
print("caught in closure")
}
// END

// TEST: defer_with_variable_access
// EXPECT: final value: 42
func deferAccess() {
var x = 0
defer { print("final value: \(x)") }
x = 42
}
deferAccess()
// END

// TEST: try_in_loop
// EXPECT: 0 ok
// 1 ok
// 2 failed
enum LoopErr: Error { case threshold }
func checkValue(_ n: Int) throws -> String {
if n >= 2 { throw LoopErr.threshold }
return "ok"
}
for i in 0..<3 {
do {
let result = try checkValue(i)
print("\(i) \(result)")
} catch {
print("\(i) failed")
}
}
// END