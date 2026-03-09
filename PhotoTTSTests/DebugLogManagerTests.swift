import XCTest
@testable import PhotoTTS

final class DebugLogManagerTests: XCTestCase {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        // 清空日志，确保测试环境干净
        DebugLogManager.shared.clearLogs()
        // 等待清空操作完成（clearLogs 是异步的）
        let clearExpectation = expectation(description: "clearLogs")
        DebugLogManager.shared.flushAndGetLatestLogs(lineCount: 1) { _, _ in
            clearExpectation.fulfill()
        }
        wait(for: [clearExpectation], timeout: 5.0)
    }
    
    // MARK: - flushAndGetLatestLogs 测试
    
    /// 验证 flushAndGetLatestLogs 能读到在调用前通过 log() 写入的所有日志
    func testFlushAndGetLatestLogsReadsRecentLogs() {
        let uniqueMarker = "TEST_MARKER_\(UUID().uuidString)"
        
        // 通过 log() 写入带唯一标识的日志
        DebugLogManager.shared.log(uniqueMarker)
        
        // 使用 flushAndGetLatestLogs 读取，验证能读到刚写入的日志
        let readExpectation = expectation(description: "flushAndGetLatestLogs")
        var resultLogs = ""
        var resultSize: Int64 = 0
        
        DebugLogManager.shared.flushAndGetLatestLogs(lineCount: 50) { logs, size in
            resultLogs = logs
            resultSize = size
            readExpectation.fulfill()
        }
        
        wait(for: [readExpectation], timeout: 5.0)
        
        XCTAssertTrue(resultLogs.contains(uniqueMarker), "flushAndGetLatestLogs 应能读到刚通过 log() 写入的日志")
        XCTAssertGreaterThan(resultSize, 0, "日志文件大小应大于 0")
    }
    
    /// 验证连续多次 log() 后 flushAndGetLatestLogs 能读到所有日志
    func testFlushAndGetLatestLogsReadsMultipleLogs() {
        let markers = (0..<5).map { "MULTI_\($0)_\(UUID().uuidString)" }
        
        for marker in markers {
            DebugLogManager.shared.log(marker)
        }
        
        let readExpectation = expectation(description: "flushAndGetLatestLogs")
        var resultLogs = ""
        
        DebugLogManager.shared.flushAndGetLatestLogs(lineCount: 50) { logs, _ in
            resultLogs = logs
            readExpectation.fulfill()
        }
        
        wait(for: [readExpectation], timeout: 5.0)
        
        for marker in markers {
            XCTAssertTrue(resultLogs.contains(marker), "应能读到日志: \(marker)")
        }
    }
    
    /// 验证 getLatestLogs（同步版本）基本功能
    func testGetLatestLogsBasicFunction() {
        let uniqueMarker = "SYNC_TEST_\(UUID().uuidString)"
        
        // 写入日志
        DebugLogManager.shared.log(uniqueMarker)
        
        // 先用 flush 确保写入完成
        let flushExpectation = expectation(description: "flush")
        DebugLogManager.shared.flushAndGetLatestLogs(lineCount: 1) { _, _ in
            flushExpectation.fulfill()
        }
        wait(for: [flushExpectation], timeout: 5.0)
        
        // 同步读取应该也能读到
        let logs = DebugLogManager.shared.getLatestLogs(lineCount: 50)
        XCTAssertTrue(logs.contains(uniqueMarker), "getLatestLogs 在 flush 后应能读到日志")
    }
    
    /// 验证日志倒序：最新日志在最前面
    func testLogsAreInReverseChronologicalOrder() {
        let firstMarker = "FIRST_\(UUID().uuidString)"
        let secondMarker = "SECOND_\(UUID().uuidString)"
        
        DebugLogManager.shared.log(firstMarker)
        // 短暂延迟确保时间戳不同
        Thread.sleep(forTimeInterval: 0.01)
        DebugLogManager.shared.log(secondMarker)
        
        let readExpectation = expectation(description: "flushAndGetLatestLogs")
        var resultLogs = ""
        
        DebugLogManager.shared.flushAndGetLatestLogs(lineCount: 50) { logs, _ in
            resultLogs = logs
            readExpectation.fulfill()
        }
        
        wait(for: [readExpectation], timeout: 5.0)
        
        let firstRange = resultLogs.range(of: firstMarker)
        let secondRange = resultLogs.range(of: secondMarker)
        
        XCTAssertNotNil(firstRange, "应包含第一条日志")
        XCTAssertNotNil(secondRange, "应包含第二条日志")
        
        if let first = firstRange, let second = secondRange {
            // 倒序：第二条（更新）应在第一条（更旧）之前
            XCTAssertTrue(second.lowerBound < first.lowerBound, "最新日志应排在最前面（时间倒序）")
        }
    }
}
