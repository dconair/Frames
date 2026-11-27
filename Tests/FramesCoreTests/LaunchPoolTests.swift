import XCTest
@testable import FramesCore

final class LaunchPoolTests: XCTestCase {
    func testRotatingNeverRepeatsTheLastStyle() {
        for last in LaunchStyle.allCases {
            for _ in 0..<50 {
                XCTAssertNotEqual(LaunchPool.next(choice: .rotating, last: last), last)
            }
        }
    }

    func testRotatingReachesEveryStyle() {
        var seen = Set<LaunchStyle>()
        var last: LaunchStyle?
        for _ in 0..<500 {
            let style = LaunchPool.next(choice: .rotating, last: last)
            seen.insert(style)
            last = style
        }
        XCTAssertEqual(seen, Set(LaunchStyle.allCases))
    }

    func testFixedChoiceAlwaysWins() {
        XCTAssertEqual(LaunchPool.next(choice: .fixed(.blitz), last: .blitz), .blitz)
    }

    func testChoiceStorageRoundTrip() {
        for style in LaunchStyle.allCases {
            XCTAssertEqual(LaunchChoice(storage: LaunchChoice.fixed(style).storage), .fixed(style))
        }
        XCTAssertEqual(LaunchChoice(storage: LaunchChoice.rotating.storage), .rotating)
        XCTAssertEqual(LaunchChoice(storage: nil), .rotating)
        XCTAssertEqual(LaunchChoice(storage: "gibt-es-nicht"), .rotating)
    }

    func testAppIconNames() {
        XCTAssertNil(AppIconChoice.einzelbilder.alternateName)
        XCTAssertEqual(AppIconChoice.sucher.alternateName, "Icon-sucher")
        XCTAssertEqual(AppIconChoice(storage: "unbekannt"), .einzelbilder)
        XCTAssertEqual(Set(AppIconChoice.allCases.map(\.previewAsset)).count, AppIconChoice.allCases.count)
    }
}
