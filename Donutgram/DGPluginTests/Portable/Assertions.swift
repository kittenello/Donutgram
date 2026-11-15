import Foundation
class XCTestExpectation {
    let semaphore = DispatchSemaphore(value: 0)
    let label: String
    init(_ label: String) { self.label = label }
    func fulfill() { semaphore.signal() }
}
class XCTestCase {
    func setUpWithError() throws {}
    func tearDownWithError() throws {}
    func expectation(description: String) -> XCTestExpectation { return XCTestExpectation(description) }
    func wait(for expectations: [XCTestExpectation], timeout: TimeInterval) {
        let deadline = DispatchTime.now() + timeout
        for expectation in expectations { if expectation.semaphore.wait(timeout: deadline) != .success { fatalError("timed out: " + expectation.label) } }
    }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { do { if try !value() { fatalError(message(), file: file, line: line) } } catch { fatalError(String(describing:error), file:file,line:line) } }
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { do { if try value() { fatalError(message(), file:file,line:line) } } catch { fatalError(String(describing:error),file:file,line:line) } }
func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { do { if try left() != right() { fatalError(message(),file:file,line:line) } } catch { fatalError(String(describing:error),file:file,line:line) } }
func XCTAssertNil<T>(_ value: @autoclosure () throws -> T?, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { do { if try value() != nil { fatalError(message(),file:file,line:line) } } catch { fatalError(String(describing:error),file:file,line:line) } }
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) { do { _ = try value() } catch { return }; fatalError("expected error: " + message(),file:file,line:line) }
func XCTUnwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T { guard let value else { fatalError("unexpected nil",file:file,line:line) }; return value }

func XCTFail(_ message: String, file: StaticString = #file, line: UInt = #line) { fatalError(message,file:file,line:line) }
func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { _ = try value() } catch { fatalError(String(describing: error),file:file,line:line) } }
func XCTAssertNotEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) { do { if try left() == right() { fatalError("values unexpectedly equal",file:file,line:line) } } catch { fatalError(String(describing:error),file:file,line:line) } }
func XCTSkipIf(_ condition: Bool, _ reason: String) throws { if condition { throw DGPortableSkip(reason: reason) } }
struct DGPortableSkip: Error { let reason: String }
