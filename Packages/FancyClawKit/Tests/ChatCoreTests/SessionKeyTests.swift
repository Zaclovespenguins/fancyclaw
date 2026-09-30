import Foundation
import Testing
@testable import ChatCore

struct SessionKeyTests {
    @Test func mainSessionKey() {
        #expect(SessionKey.main.rawValue == "agent:main:main")
    }

    @Test func encodesAsBareString() throws {
        let data = try JSONEncoder().encode(SessionKey.main)
        #expect(String(decoding: data, as: UTF8.self) == #""agent:main:main""#)
    }
}
