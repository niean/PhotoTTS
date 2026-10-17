import XCTest
@testable import PhotoTTS

/// LLMService 绘本名称过滤测试
final class LLMServiceTests: XCTestCase {

    private func filter(_ text: String) -> String {
        text.components(separatedBy: LLMConstants.storyNameInvalidCharacters).joined()
    }

    /// 中英文与数字应保留
    func testStoryNameFilterKeepsLettersAndDigits() {
        XCTAssertEqual(filter("三只小猪"), "三只小猪")
        XCTAssertEqual(filter("The3Bears"), "The3Bears")
    }

    /// 中英文标点符号应剔除
    func testStoryNameFilterRemovesPunctuation() {
        XCTAssertEqual(filter("《三只小猪》"), "三只小猪")
        XCTAssertEqual(filter("小熊，你好！"), "小熊你好")
        XCTAssertEqual(filter("小红帽:大灰狼?"), "小红帽大灰狼")
        XCTAssertEqual(filter("「好饿的毛毛虫」…"), "好饿的毛毛虫")
        XCTAssertEqual(filter("A.B,C;D"), "ABCD")
    }

    /// 引号、括号、emoji 等特殊字符应剔除
    func testStoryNameFilterRemovesSymbolsAndEmoji() {
        XCTAssertEqual(filter("“月亮”晚安(睡前故事)"), "月亮晚安睡前故事")
        XCTAssertEqual(filter("`小熊'\"的[家]"), "小熊的家")
        XCTAssertEqual(filter("小兔子🐰和胡萝卜🥕"), "小兔子和胡萝卜")
        XCTAssertEqual(filter("#1@故事*时间&"), "1故事时间")
    }

    /// 减号是标准分隔符，应保留
    func testStoryNameFilterKeepsHyphen() {
        XCTAssertEqual(filter("小熊-睡前故事"), "小熊-睡前故事")
        XCTAssertEqual(filter("three-pigs-2"), "three-pigs-2")
    }

    /// 空格与换行应剔除
    func testStoryNameFilterRemovesWhitespace() {
        XCTAssertEqual(filter("小熊 的 一天"), "小熊的一天")
        XCTAssertEqual(filter("小猪\n佩奇"), "小猪佩奇")
    }
}
