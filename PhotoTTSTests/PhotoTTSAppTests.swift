import XCTest
import SwiftUI
import AVFoundation
@testable import PhotoTTS

/// 数据模型与基础组件测试
final class PhotoTTSAppTests: XCTestCase {
    
    // MARK: - VoiceSettings 测试
    
    func testVoiceSettingsCreation() {
        let settings = VoiceSettings(
            speed: 1.5,
            pitch: 0.8,
            volume: 0.9,
            voiceType: "child",
            encoding: "wav"
        )
        
        XCTAssertEqual(settings.speed, 1.5)
        XCTAssertEqual(settings.pitch, 0.8)
        XCTAssertEqual(settings.volume, 0.9)
        XCTAssertEqual(settings.voiceType, "child")
        XCTAssertEqual(settings.encoding, "wav")
    }
    
    func testVoiceSettingsDefault() {
        let defaultSettings = VoiceSettings.default
        
        XCTAssertEqual(defaultSettings.speed, 1.0)
        XCTAssertEqual(defaultSettings.pitch, 1.0)
        XCTAssertEqual(defaultSettings.volume, 1.0)
        XCTAssertEqual(defaultSettings.voiceType, "default")
        XCTAssertEqual(defaultSettings.encoding, "mp3")
    }
    
    func testVoiceSettingsEquatable() {
        let a = VoiceSettings(speed: 1.0, pitch: 1.0, volume: 1.0, voiceType: "default", encoding: "mp3")
        let b = VoiceSettings(speed: 1.0, pitch: 1.0, volume: 1.0, voiceType: "default", encoding: "mp3")
        let c = VoiceSettings(speed: 1.5, pitch: 1.0, volume: 1.0, voiceType: "default", encoding: "mp3")
        
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
    
    func testVoiceSettingsCodable() throws {
        let original = VoiceSettings(speed: 1.2, pitch: 0.9, volume: 0.8, voiceType: "child", encoding: "wav")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(VoiceSettings.self, from: data)
        
        XCTAssertEqual(original, decoded)
    }
    
    // MARK: - AudioResponse 测试
    
    func testAudioResponseCreation() {
        let response = AudioResponse(
            id: "test-id",
            audioURL: "test.mp3",
            text: "hello",
            language: "zh",
            duration: 5.0,
            format: "mp3",
            quality: "high",
            timestamp: Date()
        )
        
        XCTAssertEqual(response.id, "test-id")
        XCTAssertEqual(response.audioURL, "test.mp3")
        XCTAssertEqual(response.text, "hello")
        XCTAssertEqual(response.language, "zh")
        XCTAssertEqual(response.duration, 5.0)
        XCTAssertEqual(response.format, "mp3")
        XCTAssertEqual(response.quality, "high")
        XCTAssertNil(response.audioData)
        XCTAssertNil(response.voiceSettings)
        XCTAssertNil(response.validImageCount)
        XCTAssertNil(response.recognizedTexts)
    }
    
    func testAudioResponseTTSInit() {
        let audioData = Data(repeating: 0xFF, count: 100)
        let response = AudioResponse(
            audioData: audioData,
            format: "mp3",
            duration: 3.0,
            validImageCount: 2,
            recognizedTexts: ["hello", "world"]
        )
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertEqual(response.audioData, audioData)
        XCTAssertEqual(response.format, "mp3")
        XCTAssertEqual(response.duration, 3.0)
        XCTAssertEqual(response.validImageCount, 2)
        XCTAssertEqual(response.recognizedTexts, ["hello", "world"])
        XCTAssertEqual(response.language, "zh")
    }
    
    // MARK: - SessionRecord 测试
    
    func testSessionRecordCreation() {
        let record = SessionRecord(
            id: UUID().uuidString,
            name: "test-record",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: ["img1", "img2"],
            ocrText: "hello world",
            ocrTextSegments: ["hello", "world"],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioDuration: 10.0,
            ocrDuration: 1.0,
            ttsDuration: 2.0,
            validImageCount: 2,
            totalImageCount: 2,
            textLength: 11,
            audioSize: 0,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0
        )
        
        XCTAssertFalse(record.id.isEmpty)
        XCTAssertEqual(record.name, "test-record")
        XCTAssertEqual(record.imageDataList.count, 2)
        XCTAssertEqual(record.ocrText, "hello world")
        XCTAssertEqual(record.ocrTextSegments, ["hello", "world"])
        XCTAssertEqual(record.audioFormat, "mp3")
        XCTAssertEqual(record.audioDuration, 10.0)
        XCTAssertEqual(record.validImageCount, 2)
        XCTAssertEqual(record.totalImageCount, 2)
        XCTAssertEqual(record.avatarImageIndex, 0)
        XCTAssertEqual(record.storageSize, 0)
    }
    
    func testSessionRecordIdentifiable() {
        let record1 = SessionRecord(
            id: "id-1",
            name: "record1",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "",
            ocrTextSegments: [],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioDuration: 0,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 0,
            totalImageCount: 0,
            textLength: 0,
            audioSize: 0,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0
        )
        
        let record2 = SessionRecord(
            id: "id-2",
            name: "record2",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "",
            ocrTextSegments: [],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioDuration: 0,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 0,
            totalImageCount: 0,
            textLength: 0,
            audioSize: 0,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0
        )
        
        XCTAssertEqual(record1.id, "id-1")
        XCTAssertEqual(record2.id, "id-2")
        XCTAssertNotEqual(record1.id, record2.id)
    }
    
    // MARK: - Constants 测试
    
    func testConstantsValues() {
        XCTAssertGreaterThan(Constants.Network.requestTimeout, 0)
        XCTAssertGreaterThan(Constants.Network.maxRetryCount, 0)
    }
    
    func testOCRConstants() {
        XCTAssertEqual(Constants.ocrEmptyResultIndicator, "空字符串")
        XCTAssertEqual(Constants.ocrTextSeparator, "\n\n")
        XCTAssertGreaterThan(Constants.defaultOCRConcurrentCount, 0)
    }
    
    // MARK: - ImageToSpeechProcessingError 测试
    
    func testProcessingErrorDescriptions() {
        let ocrError = ImageToSpeechProcessingError.ocrFailed(NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "OCR timeout"]))
        XCTAssertNotNil(ocrError.errorDescription)
        XCTAssertTrue(ocrError.errorDescription?.contains("文字识别失败") ?? false)
        
        let ttsError = ImageToSpeechProcessingError.ttsFailed(NSError(domain: "test", code: 2, userInfo: [NSLocalizedDescriptionKey: "TTS timeout"]))
        XCTAssertNotNil(ttsError.errorDescription)
        XCTAssertTrue(ttsError.errorDescription?.contains("文字转语音失败") ?? false)
        
        let cancelledError = ImageToSpeechProcessingError.cancelled
        XCTAssertNotNil(cancelledError.errorDescription)
    }
    
    // MARK: - NetworkError 测试
    
    func testNetworkErrorCases() {
        let errors: [NetworkError] = [
            .invalidInput("empty"),
            .missingAPIKey,
            .invalidURL,
            .invalidResponse,
            .httpError(404),
            .noData,
            .serverError,
            .noTexts,
            .tooManyTexts,
            .textTooLong,
        ]
        
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "NetworkError.\(error) should have a description")
        }
    }
    
    // MARK: - 相机组件测试
    
    func testCustomCameraViewControllerCreation() {
        let cameraVC = CustomCameraViewController()
        XCTAssertNotNil(cameraVC, "CustomCameraViewController should be created successfully")
    }
    
    // MARK: - 性能测试
    
    func testVoiceSettingsEncodingPerformance() {
        let settings = VoiceSettings.default
        let encoder = JSONEncoder()
        
        measure {
            for _ in 0..<1000 {
                _ = try? encoder.encode(settings)
            }
        }
    }
}
