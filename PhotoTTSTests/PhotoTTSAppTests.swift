import XCTest
import SwiftUI
import AVFoundation
@testable import PhotoTTS

/// 数据模型与基础组件测试
final class PhotoTTSAppTests: XCTestCase {
    private var createdSessionIDs: [String] = []

    override func tearDown() {
        for sessionID in createdSessionIDs {
            _ = SessionRecordManager.shared.deleteSession(id: sessionID)
        }
        createdSessionIDs.removeAll()
        super.tearDown()
    }
    
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
        let audioSegment = TTSAudioSegment(
            text: "hello",
            format: "mp3",
            duration: 1.5,
            imageStartIndex: 0,
            imageEndIndex: 0,
            textStartOffset: 0,
            textEndOffset: 4,
            audioData: audioData
        )
        let response = AudioResponse(
            audioData: audioData,
            format: "mp3",
            duration: 3.0,
            validImageCount: 2,
            recognizedTexts: ["hello", "world"],
            audioSegments: [audioSegment]
        )
        
        XCTAssertFalse(response.id.isEmpty)
        XCTAssertEqual(response.audioData, audioData)
        XCTAssertEqual(response.format, "mp3")
        XCTAssertEqual(response.duration, 3.0)
        XCTAssertEqual(response.validImageCount, 2)
        XCTAssertEqual(response.recognizedTexts, ["hello", "world"])
        XCTAssertEqual(response.audioSegments?.count, 1)
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
            audioSegments: [],
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
            audioSegments: [],
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
            audioSegments: [],
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

    func testTTSAudioSegmentCodableDropsInlineAudioData() throws {
        let segment = TTSAudioSegment(
            text: "hello",
            format: "mp3",
            duration: 1.0,
            imageStartIndex: 0,
            imageEndIndex: 0,
            textStartOffset: 0,
            textEndOffset: 4,
            audioData: Data([0x01, 0x02])
        )

        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(TTSAudioSegment.self, from: data)

        XCTAssertEqual(decoded.text, "hello")
        XCTAssertNil(decoded.audioData)
    }

    func testSessionRecordGetAudioSegmentsFallsBackToLegacySingleAudio() {
        let audioData = Data([0x01, 0x02, 0x03])
        let record = SessionRecord(
            id: UUID().uuidString,
            name: "legacy-record",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "hello world",
            ocrTextSegments: ["hello", "world"],
            audioDataBase64: audioData.base64EncodedString(),
            audioFormat: "mp3",
            audioSegments: [],
            audioDuration: 5.0,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 2,
            totalImageCount: 2,
            textLength: 11,
            audioSize: audioData.count,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0
        )

        let segments = record.getAudioSegments()
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].imageStartIndex, 0)
        XCTAssertEqual(segments[0].imageEndIndex, 1)
        XCTAssertEqual(segments[0].audioData, audioData)
    }

    func testSaveAndLoadSegmentedAudioPreservesSequenceNumbers() {
        let segmentOneData = Data([0x01, 0x02, 0x03])
        let segmentTwoData = Data([0x04, 0x05, 0x06])
        let firstSegment = TTSAudioSegment(
            sequenceNumber: 1,
            text: "第一页",
            format: "mp3",
            duration: 1.2,
            imageStartIndex: 0,
            imageEndIndex: 0,
            textStartOffset: 0,
            textEndOffset: 2,
            audioData: segmentOneData
        )
        let secondSegment = TTSAudioSegment(
            sequenceNumber: 2,
            text: "第二页",
            format: "mp3",
            duration: 1.5,
            imageStartIndex: 1,
            imageEndIndex: 1,
            textStartOffset: 3,
            textEndOffset: 5,
            audioData: segmentTwoData
        )

        let sessionID = "segmented-save-load-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)
        let record = SessionRecord(
            id: sessionID,
            name: "segmented-save-load",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "第一页\n第二页",
            ocrTextSegments: ["第一页", "第二页"],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioSegments: [firstSegment, secondSegment],
            audioDuration: 2.7,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 2,
            totalImageCount: 2,
            textLength: 6,
            audioSize: segmentOneData.count + segmentTwoData.count,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0
        )

        let saveResult = SessionRecordManager.shared.saveSession(record)
        XCTAssertTrue(saveResult.success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.appendingPathComponent("audio_1.mp3").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionDir.appendingPathComponent("audio_2.mp3").path))

        let loadedRecord = SessionRecordManager.shared.loadSession(id: sessionID)
        XCTAssertEqual(loadedRecord?.audioSegments.map(\.sequenceNumber), [1, 2])
        XCTAssertEqual(loadedRecord?.audioSegments.compactMap(\.audioData), [segmentOneData, segmentTwoData])
    }

    func testImportOneSessionPreservesSegmentedAudioSequenceNumbers() throws {
        let segmentOneData = Data([0x0A, 0x0B])
        let segmentTwoData = Data([0x0C, 0x0D, 0x0E])
        let sessionID = "segmented-import-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "segmented-import",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "甲乙",
            ocrTextSegments: ["甲", "乙"],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioSegments: [
                TTSAudioSegment(
                    sequenceNumber: 1,
                    text: "甲",
                    format: "mp3",
                    duration: 0.8,
                    imageStartIndex: 0,
                    imageEndIndex: 0,
                    textStartOffset: 0,
                    textEndOffset: 0,
                    audioData: segmentOneData
                ),
                TTSAudioSegment(
                    sequenceNumber: 2,
                    text: "乙",
                    format: "mp3",
                    duration: 1.0,
                    imageStartIndex: 1,
                    imageEndIndex: 1,
                    textStartOffset: 1,
                    textEndOffset: 1,
                    audioData: segmentTwoData
                )
            ],
            audioDuration: 1.8,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 2,
            totalImageCount: 2,
            textLength: 2,
            audioSize: segmentOneData.count + segmentTwoData.count,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0
        )

        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory.appendingPathComponent("segmented_export_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        _ = SessionRecordManager.shared.deleteSession(id: sessionID)
        createdSessionIDs.removeAll(where: { $0 == sessionID })

        let exportedDirs = try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
        let exportedSessionDir = try XCTUnwrap(exportedDirs.first(where: {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }))

        let importResult = SessionRecordManager.shared.importOneSession(from: exportedSessionDir)
        XCTAssertTrue(importResult.success)
        XCTAssertEqual(importResult.importedCount, 1)

        createdSessionIDs.append(sessionID)
        let importedRecord = try XCTUnwrap(SessionRecordManager.shared.loadSession(id: sessionID))
        XCTAssertEqual(importedRecord.audioSegments.map(\.sequenceNumber), [1, 2])
        XCTAssertEqual(importedRecord.audioSegments.compactMap(\.audioData), [segmentOneData, segmentTwoData])
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
    
    // MARK: - SessionRecordMetadata seriesName 测试

    private func makeMetadata(name: String, createdAt: Date = Date()) -> SessionRecordMetadata {
        SessionRecordMetadata(id: UUID().uuidString, name: name, createdAt: createdAt, updatedAt: createdAt, totalImageCount: 1, validImageCount: 1, textLength: 100, audioDuration: 60, avatarImageIndex: 0, storageSize: 1024)
    }

    func testSeriesName_normalFormat() {
        let m = makeMetadata(name: "26.03.16 小红帽-第一章")
        XCTAssertEqual(m.seriesName, "小红帽")
    }

    func testSeriesName_noHyphen() {
        let m = makeMetadata(name: "26.03.16 随手拍")
        XCTAssertEqual(m.seriesName, "未分类")
    }

    func testSeriesName_shortName() {
        let m = makeMetadata(name: "短")
        XCTAssertEqual(m.seriesName, "未分类")
    }

    func testSeriesName_multipleHyphens() {
        let m = makeMetadata(name: "26.03.16 小红帽-第一章-上")
        XCTAssertEqual(m.seriesName, "小红帽")
    }

    func testSeriesName_emptyAfterPrefix() {
        let m = makeMetadata(name: "26.03.16 -故事")
        XCTAssertEqual(m.seriesName, "未分类")
    }

    // MARK: - SessionRecordMetadata monthKey 测试

    func testMonthKey_normalFormat() {
        let m = makeMetadata(name: "26.03.16 小红帽-第一章")
        XCTAssertEqual(m.monthKey, "2026年3月")
    }

    func testMonthKey_fallbackToCreatedAt() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let jan2026 = formatter.date(from: "2026-01-15")!
        let m = makeMetadata(name: "短", createdAt: jan2026)
        XCTAssertEqual(m.monthKey, "2026年1月")
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
