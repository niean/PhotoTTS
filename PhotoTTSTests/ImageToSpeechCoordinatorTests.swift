import XCTest
@testable import PhotoTTS

final class ImageToSpeechCoordinatorTests: XCTestCase {
    
    // MARK: - 属性
    
    var coordinator: ImageToSpeechCoordinator!
    var mockNetworkService: MockNetworkService!
    
    // MARK: - 设置和清理
    
    override func setUp() {
        super.setUp()
        mockNetworkService = MockNetworkService()
        coordinator = ImageToSpeechCoordinator(
            networkService: mockNetworkService
        )
    }
    
    override func tearDown() {
        coordinator = nil
        mockNetworkService = nil
        super.tearDown()
    }
    
    // MARK: - convertTextToSpeech 测试
    
    func testConvertTextToSpeechSuccess() {
        let expectation = XCTestExpectation(description: "TTS success")
        let mockAudio = Data(repeating: 0xAA, count: 256)
        let mockResponse = AudioResponse(
            audioData: mockAudio,
            format: "mp3",
            duration: 5.0
        )
        
        mockNetworkService.ttsResult = .success(mockResponse)
        
        coordinator.convertTextToSpeech("hello") { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.format, "mp3")
                XCTAssertEqual(response.duration, 5.0)
            case .failure(let error):
                XCTFail("should succeed, got: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testConvertTextToSpeechFailure() {
        let expectation = XCTestExpectation(description: "TTS failure")
        
        mockNetworkService.ttsResult = .failure(NetworkError.serverError)
        
        coordinator.convertTextToSpeech("hello") { result in
            switch result {
            case .success:
                XCTFail("should fail")
            case .failure(let error):
                if case .ttsFailed = error {
                    // OK
                } else {
                    XCTFail("should be ttsFailed, got: \(error)")
                }
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - testNetworkConnection 测试
    
    func testNetworkConnectionSuccess() {
        let expectation = XCTestExpectation(description: "connection success")
        
        mockNetworkService.connectionResult = .success(true)
        
        coordinator.testNetworkConnection { result in
            switch result {
            case .success(let connected):
                XCTAssertTrue(connected)
            case .failure(let error):
                XCTFail("should succeed, got: \(error)")
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testNetworkConnectionFailure() {
        let expectation = XCTestExpectation(description: "connection failure")
        
        mockNetworkService.connectionResult = .failure(NetworkError.invalidURL)
        
        coordinator.testNetworkConnection { result in
            switch result {
            case .success:
                XCTFail("should fail")
            case .failure:
                break // OK
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - cancelProcessing 测试
    
    func testCancelProcessing() {
        // cancelProcessing 应能正常调用而不崩溃
        coordinator.cancelProcessing()
    }
    
    // MARK: - ImageToSpeechProcessingError 测试
    
    func testProcessingErrorOCRFailed() {
        let underlying = NSError(domain: "ocr", code: 1)
        let error = ImageToSpeechProcessingError.ocrFailed(underlying)
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testProcessingErrorTTSFailed() {
        let underlying = NSError(domain: "tts", code: 2)
        let error = ImageToSpeechProcessingError.ttsFailed(underlying)
        XCTAssertNotNil(error.errorDescription)
    }
    
    func testProcessingErrorCancelled() {
        let error = ImageToSpeechProcessingError.cancelled
        XCTAssertNotNil(error.errorDescription)
    }

    func testBuildTTSSegmentsKeepsImageTextAtomic() {
        let longText = String(repeating: "A", count: Constants.TTS.segmentCharacterLimit + 100)
        let segments = coordinator.buildTTSSegments(from: ["第一页", longText, "第三页"])

        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.map(\.sequenceNumber), [1, 2, 3])
        XCTAssertEqual(segments[1].imageStartIndex, 1)
        XCTAssertEqual(segments[1].imageEndIndex, 1)
    }

    func testBuildTTSSegmentsAggregatesAdjacentShortTexts() {
        let segments = coordinator.buildTTSSegments(from: ["一", "二", "三"])

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "一\n\n二\n\n三")
        XCTAssertEqual(segments[0].imageStartIndex, 0)
        XCTAssertEqual(segments[0].imageEndIndex, 2)
    }

    func testSegmentedTTSHonorsConcurrentLimitAndPreservesSequence() {
        let expectation = XCTestExpectation(description: "segmented tts")
        mockNetworkService.segmentDelay = 0.05
        mockNetworkService.ttsHandler = { text in
            let size = max(1, text.count)
            return .success(AudioResponse(audioData: Data(repeating: 0xAB, count: size), format: "mp3", duration: 1.0))
        }

        let texts = (0..<12).map { "第\($0 + 1)页" + String(repeating: "A", count: 900) }
        let combinedText = texts.joined(separator: Constants.ocrTextSeparator)

        coordinator.convertBatchImagesToSpeech(
            [],
            startingFrom: .tts,
            ocrTexts: texts,
            ocrCombinedText: combinedText,
            llmStoryName: nil,
            llmHighlights: nil
        ) { _ in } completion: { result in
            switch result {
            case .success(let response):
                let numbers = response.audioSegments?.map(\.sequenceNumber) ?? []
                XCTAssertEqual(numbers, Array(1...numbers.count))
                XCTAssertLessThanOrEqual(self.mockNetworkService.maxConcurrentSeen, Constants.TTS.segmentConcurrentLimit)
            case .failure(let error):
                XCTFail("should succeed, got: \(error)")
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - Mock Network Service

final class MockNetworkService: NetworkServiceProtocol {
    
    var ttsResult: Result<AudioResponse, Error>?
    var batchTTSResult: Result<[AudioResponse], Error>?
    var connectionResult: Result<Bool, Error>?
    var ttsHandler: ((String) -> Result<AudioResponse, Error>)?
    var segmentDelay: TimeInterval = 0
    private let lock = NSLock()
    private var concurrentCount = 0
    private(set) var maxConcurrentSeen = 0
    
    func convertTextToSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        lock.lock()
        concurrentCount += 1
        maxConcurrentSeen = max(maxConcurrentSeen, concurrentCount)
        lock.unlock()

        let result = ttsHandler?(text) ?? ttsResult
        let finish = {
            if let result {
                completion(result)
            }
            self.lock.lock()
            self.concurrentCount -= 1
            self.lock.unlock()
        }

        if segmentDelay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + segmentDelay) {
                finish()
            }
        } else {
            finish()
        }
    }
    
    func convertTextsToSpeech(_ texts: [String], voiceSettings: VoiceSettings, completion: @escaping (Result<[AudioResponse], Error>) -> Void) {
        if let result = batchTTSResult {
            completion(result)
        }
    }
    
    func convertTextToSpeechBatch(_ texts: [String], voiceSettings: VoiceSettings, completion: @escaping (Result<[AudioResponse], Error>) -> Void) {
        if let result = batchTTSResult {
            completion(result)
        }
    }
    
    func testConnection(completion: @escaping (Result<Bool, Error>) -> Void) {
        if let result = connectionResult {
            completion(result)
        }
    }
    
    func cancelAllRequests() {
        // no-op
    }
}
