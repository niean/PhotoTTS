import XCTest
@testable import PhotoTTS

final class ImageToSpeechCoordinatorTests: XCTestCase {
    
    // MARK: - 属性
    var coordinator: ImageToSpeechCoordinator!
    var mockNetworkService: MockNetworkService!
    var mockSettingsManager: MockSettingsManager!
    
    // MARK: - 设置和清理
    override func setUp() {
        super.setUp()
        mockNetworkService = MockNetworkService()
        mockSettingsManager = MockSettingsManager()
        coordinator = ImageToSpeechCoordinator(
            networkService: mockNetworkService,
            settingsManager: mockSettingsManager
        )
    }
    
    override func tearDown() {
        coordinator = nil
        mockNetworkService = nil
        mockSettingsManager = nil
        super.tearDown()
    }
    
    // MARK: - 核心功能测试
    
    func testConvertTextToSpeechSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "文字转语音成功")
        let mockText = "测试文字内容"
        let mockAudioResponse = createMockAudioResponse()
        
        mockNetworkService.convertTextToSpeechResult = .success(mockAudioResponse)
        
        var finalResult: Result<AudioResponse, ImageToSpeechProcessingError>?
        
        // When
        coordinator.convertTextToSpeech(mockText) { result in
            finalResult = result
            expectation.fulfill()
        }
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        
        switch finalResult {
        case .success(let response):
            XCTAssertEqual(response.audioURL, mockAudioResponse.audioURL)
        case .failure, .none:
            XCTFail("应该成功")
        }
    }
    
    func testConvertTextToSpeechFailure() {
        // Given
        let expectation = XCTestExpectation(description: "文字转语音失败")
        let mockText = "测试文字内容"
        let mockError = NetworkError.serverError
        
        mockNetworkService.convertTextToSpeechResult = .failure(mockError)
        
        var finalResult: Result<AudioResponse, ImageToSpeechProcessingError>?
        
        // When
        coordinator.convertTextToSpeech(mockText) { result in
            finalResult = result
            expectation.fulfill()
        }
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        
        switch finalResult {
        case .failure(let error):
            if case .ttsFailed(let underlyingError) = error {
                XCTAssertEqual(underlyingError as? NetworkError, mockError)
            } else {
                XCTFail("应该是TTS失败错误")
            }
        case .success, .none:
            XCTFail("应该失败")
        }
    }
    
    func testBatchTextToSpeechSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "批量文字转语音成功")
        let mockTexts = ["第一段文字", "第二段文字"]
        let mockAudioResponses = [
            createMockAudioResponse(audioURL: "audio1.mp3"),
            createMockAudioResponse(audioURL: "audio2.mp3")
        ]
        
        mockNetworkService.convertTextToSpeechBatchResult = .success(mockAudioResponses)
        
        var finalResult: Result<[AudioResponse], ImageToSpeechProcessingError>?
        
        // When
        coordinator.convertBatchTextsToSpeech(mockTexts) { result in
            finalResult = result
            expectation.fulfill()
        }
        
        // Then
        wait(for: [expectation], timeout: 1.0)
        
        switch finalResult {
        case .success(let responses):
            XCTAssertEqual(responses.count, 2)
            XCTAssertEqual(responses[0].audioURL, "audio1.mp3")
            XCTAssertEqual(responses[1].audioURL, "audio2.mp3")
        case .failure, .none:
            XCTFail("应该成功")
        }
    }
    
    // MARK: - 辅助方法
    private func createMockAudioResponse(audioURL: String = "test.mp3") -> AudioResponse {
        return AudioResponse(
            id: UUID().uuidString,
            audioURL: audioURL,
            text: "测试文字",
            language: "zh",
            duration: 120.0,
            format: "mp3",
            quality: "high",
            timestamp: Date()
        )
    }
    
    // MARK: - Mock Services
    class MockNetworkService: NetworkServiceProtocol {
        var convertTextToSpeechResult: Result<AudioResponse, Error>?
        var convertTextToSpeechBatchResult: Result<[AudioResponse], Error>?
        
        func convertTextToSpeech(_ text: String, voiceSettings: VoiceSettings, completion: @escaping (Result<AudioResponse, Error>) -> Void) {
            if let result = convertTextToSpeechResult {
                completion(result)
            }
        }
        
        func convertTextToSpeechBatch(_ texts: [String], voiceSettings: VoiceSettings, completion: @escaping (Result<[AudioResponse], Error>) -> Void) {
            if let result = convertTextToSpeechBatchResult {
                completion(result)
            }
        }
    }
    
    class MockSettingsManager: SettingsManagerProtocol {
        var voiceSettings: VoiceSettings = VoiceSettings.default
        var accessKey: String? = "test_key"
        var ttsAppId: String = "test_app_id"
        var ttsCluster: String = "test_cluster"
        var ttsAccessKey: String = "test_access_key"
        var ttsUid: String = "test_uid"
    }
}
