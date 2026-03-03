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
}

// MARK: - Mock Network Service

final class MockNetworkService: NetworkServiceProtocol {
    
    var ttsResult: Result<AudioResponse, Error>?
    var batchTTSResult: Result<[AudioResponse], Error>?
    var connectionResult: Result<Bool, Error>?
    
    func convertTextToSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
        if let result = ttsResult {
            completion(result)
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
