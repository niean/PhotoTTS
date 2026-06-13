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

    func testSessionRecordSourceOCRTextExcludesVirtualHighlightsPage() {
        let record = SessionRecord(
            id: UUID().uuidString,
            name: "26.05.01 贝贝熊-刷牙",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "第一页\(Constants.ocrTextSeparator)第二页\(Constants.ocrTextSeparator)要点总结",
            ocrTextSegments: ["第一页", "第二页", "要点总结"],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioSegments: [],
            audioDuration: 1.0,
            ocrDuration: 0.1,
            llmDuration: 0.2,
            ttsDuration: 0.3,
            validImageCount: 2,
            totalImageCount: 2,
            textLength: 0,
            audioSize: 0,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0,
            makeStatus: .completed,
            storyHighlights: "要点总结",
            hasVirtualPage: true
        )

        XCTAssertEqual(record.sourceOCRTextSegments, ["第一页", "第二页"])
        XCTAssertEqual(record.sourceOCRText, "第一页\(Constants.ocrTextSeparator)第二页")
        XCTAssertEqual(record.nameWithoutDatePrefix, "贝贝熊-刷牙")
    }

    func testHomeMetadataQueryExcludesUnnamedSessionsOnlyWhenRequested() {
        let unnamedId = UUID().uuidString
        let namedId = UUID().uuidString
        createdSessionIDs += [unnamedId, namedId]

        let unnamedRecord = SessionRecord(
            id: unnamedId,
            name: "26.05.10 未命名-101010",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "draft",
            ocrTextSegments: ["draft"],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioSegments: [],
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1,
            totalImageCount: 1,
            textLength: 5,
            audioSize: 0,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0,
            makeStatus: .completed
        )
        let namedRecord = SessionRecord(
            id: namedId,
            name: "26.05.10 贝贝熊-刷牙",
            createdAt: Date(),
            updatedAt: Date(),
            imageDataList: [],
            ocrText: "named",
            ocrTextSegments: ["named"],
            audioDataBase64: "",
            audioFormat: "mp3",
            audioSegments: [],
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1,
            totalImageCount: 1,
            textLength: 5,
            audioSize: 0,
            voiceSettings: nil,
            avatarImageIndex: 0,
            storageSize: 0,
            makeStatus: .completed
        )

        XCTAssertTrue(SessionRecordManager.shared.saveSession(unnamedRecord).success)
        XCTAssertTrue(SessionRecordManager.shared.saveSession(namedRecord).success)

        let allMetadata = SessionRecordManager.shared.getAllSessionMetadata(
            caller: "test.allMetadata",
            forceRefresh: true
        )
        XCTAssertTrue(allMetadata.contains(where: { $0.id == unnamedId }))
        XCTAssertTrue(allMetadata.contains(where: { $0.id == namedId }))

        let homeMetadata = SessionRecordManager.shared.getFilteredSessionMetadata(
            completedOnly: true,
            excludeUnnamed: true,
            caller: "test.homeMetadata"
        )
        XCTAssertFalse(homeMetadata.contains(where: { $0.id == unnamedId }))
        XCTAssertTrue(homeMetadata.contains(where: { $0.id == namedId }))
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
            images: [
                makeImage(color: .red, size: CGSize(width: 120, height: 120)),
                makeImage(color: .blue, size: CGSize(width: 120, height: 120))
            ],
            ocrText: "甲乙",
            ocrTextSegments: ["甲", "乙"],
            audioData: Data(),
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
            validImageCount: 2
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

    func testImportTransferredSessionsRecoveringPartialsImportsOnlyCompleteSessions() throws {
        let sourceSessionID = "partial-transfer-source-\(UUID().uuidString)"
        createdSessionIDs.append(sourceSessionID)

        let sourceRecord = SessionRecord(
            id: sourceSessionID,
            name: "partial-transfer-source",
            images: [makeImage(color: .blue)],
            ocrText: "完整记录",
            ocrTextSegments: ["完整记录"],
            audioData: Data([0x01, 0x02, 0x03]),
            audioFormat: "mp3",
            audioDuration: 1.2,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(sourceRecord).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("partial_transfer_export_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSelectedSessions([sourceSessionID], to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportPackageDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )
        let sessionsDir = exportPackageDir.appendingPathComponent("Sessions", isDirectory: true)

        let importedSessionID = "partial-transfer-import-\(UUID().uuidString)"
        let importedDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: importedDir.path))

        let importedRecordURL = importedDir.appendingPathComponent("record.json")
        let importedMetadataURL = importedDir.appendingPathComponent("metadata.json")
        let importedIntegrityURL = importedDir.appendingPathComponent("integrity.json")

        var recoveredRecord = try JSONDecoder().decode(SessionRecord.self, from: Data(contentsOf: importedRecordURL))
        recoveredRecord = SessionRecord(
            id: importedSessionID,
            name: recoveredRecord.name,
            createdAt: recoveredRecord.createdAt,
            updatedAt: recoveredRecord.updatedAt,
            imageDataList: recoveredRecord.imageDataList,
            ocrText: recoveredRecord.ocrText,
            ocrTextSegments: recoveredRecord.ocrTextSegments,
            audioDataBase64: recoveredRecord.audioDataBase64,
            audioFormat: recoveredRecord.audioFormat,
            audioSegments: recoveredRecord.audioSegments,
            audioDuration: recoveredRecord.audioDuration,
            ocrDuration: recoveredRecord.ocrDuration,
            llmDuration: recoveredRecord.llmDuration,
            ttsDuration: recoveredRecord.ttsDuration,
            validImageCount: recoveredRecord.validImageCount,
            totalImageCount: recoveredRecord.totalImageCount,
            textLength: recoveredRecord.textLength,
            audioSize: recoveredRecord.audioSize,
            voiceSettings: recoveredRecord.voiceSettings,
            avatarImageIndex: recoveredRecord.avatarImageIndex,
            storageSize: recoveredRecord.storageSize,
            makeStatus: recoveredRecord.makeStatus,
            storyHighlights: recoveredRecord.storyHighlights,
            hasVirtualPage: recoveredRecord.hasVirtualPage,
            animationStyle: recoveredRecord.animationStyle,
            coverImagePath: recoveredRecord.coverImagePath
        )
        try JSONEncoder().encode(recoveredRecord).write(to: importedRecordURL)

        var recoveredMetadata = try JSONDecoder().decode(SessionRecordMetadata.self, from: Data(contentsOf: importedMetadataURL))
        recoveredMetadata = SessionRecordMetadata(
            id: importedSessionID,
            name: recoveredMetadata.name,
            createdAt: recoveredMetadata.createdAt,
            updatedAt: recoveredMetadata.updatedAt,
            totalImageCount: recoveredMetadata.totalImageCount,
            validImageCount: recoveredMetadata.validImageCount,
            textLength: recoveredMetadata.textLength,
            audioDuration: recoveredMetadata.audioDuration,
            avatarImageIndex: recoveredMetadata.avatarImageIndex,
            storageSize: recoveredMetadata.storageSize,
            makeStatus: recoveredMetadata.makeStatus,
            animationStyle: recoveredMetadata.animationStyle
        )
        try JSONEncoder().encode(recoveredMetadata).write(to: importedMetadataURL)
        try? FileManager.default.removeItem(at: importedIntegrityURL)

        let incompleteSessionDir = sessionsDir.appendingPathComponent("broken-session", isDirectory: true)
        try FileManager.default.createDirectory(at: incompleteSessionDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: importedRecordURL, to: incompleteSessionDir.appendingPathComponent("record.json"))
        try FileManager.default.copyItem(at: importedMetadataURL, to: incompleteSessionDir.appendingPathComponent("metadata.json"))
        try FileManager.default.createDirectory(at: incompleteSessionDir.appendingPathComponent("images", isDirectory: true), withIntermediateDirectories: true)

        let deleteOriginalResult = SessionRecordManager.shared.deleteSession(id: sourceSessionID)
        XCTAssertTrue(deleteOriginalResult)
        createdSessionIDs.removeAll(where: { $0 == sourceSessionID })

        let importResult = SessionRecordManager.shared.importTransferredSessionsRecoveringPartials(from: sessionsDir.deletingLastPathComponent())
        XCTAssertTrue(importResult.success)
        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertEqual(importResult.skippedCount, 1)
        XCTAssertEqual(importResult.duplicateCount, 0)
        XCTAssertEqual(importResult.skipReasonCounts[.sessionDirectoryInvalid], 1)

        createdSessionIDs.append(importedSessionID)
        XCTAssertNotNil(SessionRecordManager.shared.loadSession(id: importedSessionID))
        XCTAssertNil(SessionRecordManager.shared.loadSession(id: "broken-session"))
    }

    func testSaveSessionDoesNotWriteIntegrityManifestOnDisk() throws {
        let sessionID = "integrity-save-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-save",
            images: [makeImage(color: .systemPink)],
            ocrText: "完整性测试",
            ocrTextSegments: ["完整性测试"],
            audioData: Data([0x01, 0x02, 0x03]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )

        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let integrityURL = sessionDir.appendingPathComponent("integrity.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: integrityURL.path))
    }

    func testPurgeLocalSessionIntegrityRemovesLegacyManifest() throws {
        let sessionID = "integrity-purge-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-purge",
            images: [makeImage(color: .systemTeal)],
            ocrText: "清理测试",
            ocrTextSegments: ["清理测试"],
            audioData: Data([0x0A, 0x0B]),
            audioFormat: "mp3",
            audioDuration: 0.8,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )

        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let integrityURL = sessionDir.appendingPathComponent("integrity.json")
        try Data("{\"version\":1}".utf8).write(to: integrityURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: integrityURL.path))

        let result = SessionRecordManager.shared.purgeLocalSessionIntegrityForAllSessions()
        XCTAssertGreaterThanOrEqual(result.updated, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: integrityURL.path))
    }

    func testExportSessionWritesIntegrityManifestForSnapshotOnly() throws {
        let sessionID = "integrity-export-snapshot-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-export-snapshot",
            images: [makeImage(color: .purple)],
            ocrText: "导出快照",
            ocrTextSegments: ["导出快照"],
            audioData: Data([0x21, 0x22]),
            audioFormat: "mp3",
            audioDuration: 0.5,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )

        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)
        let localSessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localSessionDir.appendingPathComponent("integrity.json").path))

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity_snapshot_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedSessionDir.appendingPathComponent("integrity.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: localSessionDir.appendingPathComponent("integrity.json").path))
    }

    func testExportedSnapshotImportsAfterLocalFilesChange() throws {
        let sessionID = "integrity-export-preflight-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-export-preflight",
            images: [makeImage(color: .brown)],
            ocrText: "导出前校验",
            ocrTextSegments: ["导出前校验"],
            audioData: Data([0x31, 0x32, 0x33]),
            audioFormat: "mp3",
            audioDuration: 0.9,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )

        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)
        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDir.appendingPathComponent("integrity.json").path))

        let history = SessionHistory(makeEvents: [SessionHistoryEvent(timestamp: Date(), identity: "iPhone")])
        SessionRecordManager.shared.saveSessionHistory(sessionId: sessionID, history: history)

        let historyURL = sessionDir.appendingPathComponent("history.json")
        let tamperedHistory = try XCTUnwrap("""
        {
          "makeEvents" : [],
          "playEvents" : []
        }
        """.data(using: .utf8))
        try tamperedHistory.write(to: historyURL)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity_export_preflight_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)
        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: exportedSessionDir.appendingPathComponent("integrity.json").path))

        _ = SessionRecordManager.shared.deleteSession(id: sessionID)
        createdSessionIDs.removeAll(where: { $0 == sessionID })

        let importResult = SessionRecordManager.shared.importOneSession(from: exportedSessionDir)
        XCTAssertTrue(importResult.success)
        XCTAssertEqual(importResult.importedCount, 1)

        createdSessionIDs.append(sessionID)
        XCTAssertNotNil(SessionRecordManager.shared.loadSession(id: sessionID))
        let importedSessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: importedSessionDir.appendingPathComponent("integrity.json").path))
    }

    func testExportSessionClearsPlayEventsButKeepsMakeEvents() throws {
        let sessionID = "export-history-trim-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "export-history-trim",
            images: [makeImage(color: .systemPink)],
            ocrText: "导出时裁剪历史",
            ocrTextSegments: ["导出时裁剪历史"],
            audioData: Data([0x41, 0x42, 0x43]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let makeEvent = SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_001_000), identity: "maker")
        let playEvent = SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_001_600), identity: "player")
        let originalHistory = SessionHistory(makeEvents: [makeEvent], playEvents: [playEvent])
        SessionRecordManager.shared.saveSessionHistory(sessionId: sessionID, history: originalHistory)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_history_trim_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let exportedHistory = try loadHistory(from: exportedSessionDir.appendingPathComponent("history.json"))
        XCTAssertEqual(exportedHistory.makeEvents.map(\.identity), ["maker"])
        XCTAssertEqual(exportedHistory.playEvents.count, 0)

        let localHistory = SessionRecordManager.shared.loadSessionHistory(sessionId: sessionID)
        XCTAssertEqual(localHistory.makeEvents.map(\.identity), ["maker"])
        XCTAssertEqual(localHistory.playEvents.map(\.identity), ["player"])
    }

    func testExportSelectedSessionsClearsPlayEventsButKeepsMakeEvents() throws {
        let sessionID = "batch-export-history-trim-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "batch-export-history-trim",
            images: [makeImage(color: .systemTeal)],
            ocrText: "批量导出裁剪历史",
            ocrTextSegments: ["批量导出裁剪历史"],
            audioData: Data([0x44, 0x45, 0x46]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        SessionRecordManager.shared.saveSessionHistory(
            sessionId: sessionID,
            history: SessionHistory(
                makeEvents: [SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_002_000), identity: "maker-batch")],
                playEvents: [SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_002_600), identity: "player-batch")]
            )
        )

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch_export_history_trim_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSelectedSessions([sessionID], to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportPackageDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )
        let sessionsDir = exportPackageDir.appendingPathComponent("Sessions", isDirectory: true)
        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let exportedHistory = try loadHistory(from: exportedSessionDir.appendingPathComponent("history.json"))
        XCTAssertEqual(exportedHistory.makeEvents.map(\.identity), ["maker-batch"])
        XCTAssertEqual(exportedHistory.playEvents.count, 0)
    }

    func testExportSessionWithStatsKeepsPlayEvents() throws {
        let sessionID = "export-history-keep-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "export-history-keep",
            images: [makeImage(color: .systemIndigo)],
            ocrText: "带统计导出",
            ocrTextSegments: ["带统计导出"],
            audioData: Data([0x47, 0x48, 0x49]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let makeEvent = SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_003_000), identity: "maker-keep")
        let playEvent = SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_003_600), identity: "player-keep")
        SessionRecordManager.shared.saveSessionHistory(
            sessionId: sessionID,
            history: SessionHistory(makeEvents: [makeEvent], playEvents: [playEvent])
        )

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("export_history_keep_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(
            id: sessionID,
            to: exportRoot,
            historyMode: .keepAllEvents
        )
        XCTAssertTrue(exportResult.success)

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let exportedHistory = try loadHistory(from: exportedSessionDir.appendingPathComponent("history.json"))
        XCTAssertEqual(exportedHistory.makeEvents.map(\.identity), ["maker-keep"])
        XCTAssertEqual(exportedHistory.playEvents.map(\.identity), ["player-keep"])
    }

    func testExportSelectedSessionsWithStatsKeepsPlayEvents() throws {
        let sessionID = "batch-export-history-keep-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "batch-export-history-keep",
            images: [makeImage(color: .systemMint)],
            ocrText: "批量带统计导出",
            ocrTextSegments: ["批量带统计导出"],
            audioData: Data([0x4A, 0x4B, 0x4C]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        SessionRecordManager.shared.saveSessionHistory(
            sessionId: sessionID,
            history: SessionHistory(
                makeEvents: [SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_004_000), identity: "maker-batch-keep")],
                playEvents: [SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_004_600), identity: "player-batch-keep")]
            )
        )

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("batch_export_history_keep_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSelectedSessions(
            [sessionID],
            to: exportRoot,
            historyMode: .keepAllEvents
        )
        XCTAssertTrue(exportResult.success)

        let exportPackageDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )
        let sessionsDir = exportPackageDir.appendingPathComponent("Sessions", isDirectory: true)
        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let exportedHistory = try loadHistory(from: exportedSessionDir.appendingPathComponent("history.json"))
        XCTAssertEqual(exportedHistory.makeEvents.map(\.identity), ["maker-batch-keep"])
        XCTAssertEqual(exportedHistory.playEvents.map(\.identity), ["player-batch-keep"])
    }

    func testApplyHistoryPackageFromUnpackedDirectoryDoesNotCreateReceiverIntegrityManifest() throws {
        let sessionID = "play-history-integrity-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "play-history-integrity",
            images: [makeImage(color: .magenta)],
            ocrText: "播放记录接收后更新校验",
            ocrTextSegments: ["播放记录接收后更新校验"],
            audioData: Data([0x51, 0x52, 0x53]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let integrityURL = sessionDir.appendingPathComponent("integrity.json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: integrityURL.path))

        let incomingHistory = SessionHistory(
            makeEvents: [SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_000), identity: "sender-iPhone")],
            playEvents: [SessionHistoryEvent(timestamp: Date(timeIntervalSince1970: 1_700_000_600), identity: "sender-iPad")]
        )

        let unpackDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("play_history_unpack_\(UUID().uuidString)", isDirectory: true)
        let incomingSessionDir = unpackDir.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: incomingSessionDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unpackDir) }

        let incomingHistoryURL = incomingSessionDir.appendingPathComponent("history.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let historyData = try encoder.encode(incomingHistory)
        try historyData.write(to: incomingHistoryURL)

        let result = SessionRecordManager.shared.applyHistoryPackageFromUnpackedDirectory(
            unpackDir,
            existingSessionIDs: [sessionID]
        )

        XCTAssertEqual(result.received, 1)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: integrityURL.path))

        let persistedHistory = SessionRecordManager.shared.loadSessionHistory(sessionId: sessionID)
        XCTAssertEqual(persistedHistory.makeEvents.map(\.identity), incomingHistory.makeEvents.map(\.identity))
        XCTAssertEqual(persistedHistory.makeEvents.map(\.timestamp), incomingHistory.makeEvents.map(\.timestamp))
        XCTAssertEqual(persistedHistory.playEvents.map(\.identity), incomingHistory.playEvents.map(\.identity))
        XCTAssertEqual(persistedHistory.playEvents.map(\.timestamp), incomingHistory.playEvents.map(\.timestamp))
    }

    func testApplyHistoryPackageFromUnpackedDirectorySkipsMissingSessionAndInvalidHistory() throws {
        let existingSessionID = "play-history-existing-\(UUID().uuidString)"
        createdSessionIDs.append(existingSessionID)

        let record = SessionRecord(
            id: existingSessionID,
            name: "play-history-existing",
            images: [makeImage(color: .cyan)],
            ocrText: "历史记录跳过原因",
            ocrTextSegments: ["历史记录跳过原因"],
            audioData: Data([0x61, 0x62]),
            audioFormat: "mp3",
            audioDuration: 0.7,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let unpackDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("play_history_skip_unpack_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: unpackDir) }

        let missingSessionDir = unpackDir.appendingPathComponent("missing-session", isDirectory: true)
        try FileManager.default.createDirectory(at: missingSessionDir, withIntermediateDirectories: true)

        let invalidHistoryDir = unpackDir.appendingPathComponent(existingSessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: invalidHistoryDir, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: invalidHistoryDir.appendingPathComponent("history.json"))

        let result = SessionRecordManager.shared.applyHistoryPackageFromUnpackedDirectory(
            unpackDir,
            existingSessionIDs: [existingSessionID]
        )

        XCTAssertEqual(result.received, 0)
        XCTAssertEqual(result.skipped, 2)
    }

    func testImportOneSessionRejectsTamperedIntegrityManifest() throws {
        let sessionID = "integrity-import-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-import",
            images: [makeImage(color: .orange)],
            ocrText: "导入校验",
            ocrTextSegments: ["导入校验"],
            audioData: Data([0x11, 0x12, 0x13]),
            audioFormat: "mp3",
            audioDuration: 1.3,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory.appendingPathComponent("integrity_export_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        _ = SessionRecordManager.shared.deleteSession(id: sessionID)
        createdSessionIDs.removeAll(where: { $0 == sessionID })

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let exportedRecordURL = exportedSessionDir.appendingPathComponent("record.json")
        var exportedRecordData = try Data(contentsOf: exportedRecordURL)
        exportedRecordData.append(0x20)
        try exportedRecordData.write(to: exportedRecordURL)

        let importResult = SessionRecordManager.shared.importOneSession(from: exportedSessionDir)
        XCTAssertFalse(importResult.success)
        XCTAssertEqual(importResult.importedCount, 0)
        XCTAssertEqual(importResult.skippedCount, 1)
        XCTAssertEqual(importResult.errorMessage, "该记录目录不完整或已损坏")
        XCTAssertEqual(importResult.skipReasonCounts[.integrityValidationFailed], 1)
    }

    func testImportOneSessionIgnoresStaleMetadataCacheAfterLocalDeletion() throws {
        let sessionID = "stale-cache-import-one-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "stale-cache-import-one",
            images: [makeImage(color: .cyan)],
            ocrText: "重新传输",
            ocrTextSegments: ["重新传输"],
            audioData: Data([0x31, 0x32, 0x33]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale_cache_import_one_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        _ = SessionRecordManager.shared.getAllSessionMetadata(caller: "test.staleCacheImportOne.warmup")
        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.removeItem(at: sessionDir)
        createdSessionIDs.removeAll(where: { $0 == sessionID })

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let importResult = SessionRecordManager.shared.importOneSession(from: exportedSessionDir)
        XCTAssertTrue(importResult.success)
        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertEqual(importResult.duplicateCount, 0)
        XCTAssertTrue(importResult.skipReasonCounts.isEmpty)

        createdSessionIDs.append(sessionID)
        XCTAssertNotNil(SessionRecordManager.shared.loadSession(id: sessionID))
    }

    func testImportOneSessionReportsDuplicateSkipReason() throws {
        let sessionID = "duplicate-import-one-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "duplicate-import-one",
            images: [makeImage(color: .orange)],
            ocrText: "重复导入",
            ocrTextSegments: ["重复导入"],
            audioData: Data([0x61, 0x62, 0x63]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("duplicate_import_one_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let importResult = SessionRecordManager.shared.importOneSession(from: exportedSessionDir)
        XCTAssertTrue(importResult.success)
        XCTAssertEqual(importResult.importedCount, 0)
        XCTAssertEqual(importResult.duplicateCount, 1)
        XCTAssertEqual(importResult.skipReasonCounts[.duplicateID], 1)
    }

    func testImportAllSessionsIgnoresStaleMetadataCacheAfterLocalDeletion() throws {
        let sessionID = "stale-cache-import-all-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "stale-cache-import-all",
            images: [makeImage(color: .magenta)],
            ocrText: "再次制作后重传",
            ocrTextSegments: ["再次制作后重传"],
            audioData: Data([0x41, 0x42, 0x43]),
            audioFormat: "mp3",
            audioDuration: 1.1,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale_cache_import_all_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSelectedSessions([sessionID], to: exportRoot)
        XCTAssertTrue(exportResult.success)

        _ = SessionRecordManager.shared.getAllSessionMetadata(caller: "test.staleCacheImportAll.warmup")
        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.removeItem(at: sessionDir)
        createdSessionIDs.removeAll(where: { $0 == sessionID })

        let exportPackageDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let importResult = SessionRecordManager.shared.importAllSessions(from: exportPackageDir)
        XCTAssertTrue(importResult.success)
        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertEqual(importResult.duplicateCount, 0)
        XCTAssertTrue(importResult.skipReasonCounts.isEmpty)

        createdSessionIDs.append(sessionID)
        XCTAssertNotNil(SessionRecordManager.shared.loadSession(id: sessionID))
    }

    func testUpdateSessionWithResultsReplacesLegacyDatePrefixInStoryName() throws {
        let sessionID = "update-session-results-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let draftRecord = SessionRecord(
            id: sessionID,
            name: "26.04.29 贝贝熊-旧名字",
            images: [makeImage(color: .orange)],
            ocrText: "旧文本",
            ocrTextSegments: ["旧文本"],
            audioData: Data(),
            audioFormat: "mp3",
            audioDuration: 0.8,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1,
            makeStatus: .making
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(draftRecord).success)

        let response = AudioResponse(
            id: sessionID,
            audioURL: "",
            text: "新文本",
            language: "zh",
            duration: 1.2,
            format: "mp3",
            quality: "high",
            timestamp: Date(),
            voiceSettings: nil,
            audioData: Data([0x01, 0x02, 0x03]),
            validImageCount: 1,
            recognizedTexts: ["新文本"],
            audioSegments: [],
            storyName: "26.04.29 贝贝熊-新名字",
            storyHighlights: "新的要点",
            hasVirtualPage: true
        )

        XCTAssertTrue(
            SessionRecordManager.shared.updateSessionWithResults(
                id: sessionID,
                audioResponse: response,
                ocrDuration: 0.3,
                llmDuration: 0.4,
                ttsDuration: 0.5
            )
        )

        let updatedRecord = try XCTUnwrap(SessionRecordManager.shared.loadSession(id: sessionID))
        let formatter = DateFormatter()
        formatter.dateFormat = Constants.sessionNameDatePrefixFormat
        let expectedPrefix = formatter.string(from: Date())

        XCTAssertEqual(updatedRecord.name, expectedPrefix + "贝贝熊-新名字")
        XCTAssertFalse(updatedRecord.name.contains("26.04.29 贝贝熊-新名字"))
    }

    func testExportedSnapshotFromRemadeSessionPassesIntegrityValidation() throws {
        let sessionID = "remade-export-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let initialRecord = SessionRecord(
            id: sessionID,
            name: "remade-export-initial",
            images: [
                makeImage(color: .red, size: CGSize(width: 120, height: 120)),
                makeImage(color: .blue, size: CGSize(width: 120, height: 120))
            ],
            ocrText: "旧文本",
            ocrTextSegments: ["旧", "文本"],
            audioData: Data([0x01, 0x02, 0x03, 0x04]),
            audioFormat: "mp3",
            audioDuration: 1.5,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 2
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord).success)

        let coverData = try XCTUnwrap(makeImage(color: .green, size: CGSize(width: 160, height: 90)).jpegData(compressionQuality: 1.0))
        let coverPath = try SessionRecordManager.shared.saveCoverImage(data: coverData, sessionId: sessionID)
        let initialWithCover = initialRecord.withCoverImagePath(coverPath)
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialWithCover).success)

        let remadeRecord = SessionRecord(
            id: sessionID,
            name: "remade-export-final",
            createdAt: initialWithCover.createdAt,
            updatedAt: Date(),
            images: [makeImage(color: .purple, size: CGSize(width: 140, height: 140))],
            ocrText: "再次制作后的文本",
            ocrTextSegments: ["再次制作后的文本"],
            audioData: Data([0x11, 0x12, 0x13]),
            audioFormat: "mp3",
            audioDuration: 2.0,
            ocrDuration: 0.3,
            ttsDuration: 0.4,
            validImageCount: 1,
            avatarImageIndex: 0,
            storyHighlights: "要点",
            hasVirtualPage: true
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(remadeRecord).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("remade_export_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSelectedSessions([sessionID], to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportPackageDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )
        let sessionsDir = exportPackageDir.appendingPathComponent("Sessions", isDirectory: true)
        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: sessionsDir, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        XCTAssertEqual(
            SessionRecordManager.shared.validateTransferredSessionDirectory(exportedSessionDir),
            .valid(id: sessionID, name: "remade-export-final")
        )
    }

    func testSaveDraftSessionReplacingExistingContentResetsAvatarAndCoverWhenFirstImageChanges() throws {
        let sessionID = "replace-draft-reset-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let initialRecord = SessionRecord(
            id: sessionID,
            name: "replace-draft-reset",
            images: [
                makeImage(color: .red, size: CGSize(width: 120, height: 120)),
                makeImage(color: .blue, size: CGSize(width: 120, height: 120))
            ],
            ocrText: "旧文本",
            ocrTextSegments: ["旧", "文本"],
            audioData: Data([0x01, 0x02]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 2,
            avatarImageIndex: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent("avatar.jpg")
        let coverURL = sessionDir.appendingPathComponent("cover.jpg")

        let customAvatarData = try XCTUnwrap(
            makeImage(color: .purple, size: CGSize(width: 96, height: 96)).jpegData(compressionQuality: 1.0)
        )
        try customAvatarData.write(to: avatarURL)

        let coverData = try XCTUnwrap(
            makeImage(color: .green, size: CGSize(width: 160, height: 90)).jpegData(compressionQuality: 1.0)
        )
        let coverPath = try SessionRecordManager.shared.saveCoverImage(data: coverData, sessionId: sessionID)
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord.withCoverImagePath(coverPath)).success)

        XCTAssertTrue(
            SessionRecordManager.shared.saveDraftSession(
                id: sessionID,
                name: "ignored",
                images: [
                    makeImage(color: .yellow, size: CGSize(width: 120, height: 120)),
                    makeImage(color: .blue, size: CGSize(width: 120, height: 120))
                ],
                replaceExistingContent: true
            )
        )

        let updatedRecord = try XCTUnwrap(SessionRecordManager.shared.loadSession(id: sessionID))
        XCTAssertEqual(updatedRecord.name, initialRecord.name)
        XCTAssertEqual(updatedRecord.totalImageCount, 2)
        XCTAssertEqual(updatedRecord.avatarImageIndex, 0)
        XCTAssertEqual(updatedRecord.makeStatus, .making)
        XCTAssertNil(updatedRecord.coverImagePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: avatarURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: coverURL.path))
    }

    func testSaveDraftSessionReplacingExistingContentPreservesArtworkWhenFirstImageUnchanged() throws {
        let sessionID = "replace-draft-keep-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let initialRecord = SessionRecord(
            id: sessionID,
            name: "replace-draft-keep",
            images: [
                makeImage(color: .red, size: CGSize(width: 120, height: 120)),
                makeImage(color: .blue, size: CGSize(width: 120, height: 120))
            ],
            ocrText: "旧文本",
            ocrTextSegments: ["旧", "文本"],
            audioData: Data([0x01, 0x02]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 2,
            avatarImageIndex: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent("avatar.jpg")
        let coverURL = sessionDir.appendingPathComponent("cover.jpg")

        let customAvatarData = try XCTUnwrap(
            makeImage(color: .purple, size: CGSize(width: 96, height: 96)).jpegData(compressionQuality: 1.0)
        )
        try customAvatarData.write(to: avatarURL)

        let coverData = try XCTUnwrap(
            makeImage(color: .green, size: CGSize(width: 160, height: 90)).jpegData(compressionQuality: 1.0)
        )
        let coverPath = try SessionRecordManager.shared.saveCoverImage(data: coverData, sessionId: sessionID)
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord.withCoverImagePath(coverPath)).success)

        let unchangedFirstImage = try XCTUnwrap(
            SessionRecordManager.shared.loadImage(sessionId: sessionID, index: 0, maxDimension: 400)
        )

        XCTAssertTrue(
            SessionRecordManager.shared.saveDraftSession(
                id: sessionID,
                name: "ignored",
                images: [
                    unchangedFirstImage,
                    makeImage(color: .yellow, size: CGSize(width: 120, height: 120))
                ],
                replaceExistingContent: true
            )
        )

        let updatedRecord = try XCTUnwrap(SessionRecordManager.shared.loadSession(id: sessionID))
        XCTAssertEqual(updatedRecord.avatarImageIndex, 1)
        XCTAssertEqual(updatedRecord.coverImagePath, coverPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: avatarURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: coverURL.path))
    }

    func testReplaceSessionImageResetsAvatarAndCoverWhenReplacingFirstImage() throws {
        let sessionID = "replace-session-image-reset-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let initialRecord = SessionRecord(
            id: sessionID,
            name: "replace-session-image-reset",
            images: [
                makeImage(color: .red, size: CGSize(width: 120, height: 120)),
                makeImage(color: .blue, size: CGSize(width: 120, height: 120))
            ],
            ocrText: "旧文本",
            ocrTextSegments: ["旧", "文本"],
            audioData: Data([0x01, 0x02, 0x03]),
            audioFormat: "mp3",
            audioDuration: 1.2,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 2,
            avatarImageIndex: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent("avatar.jpg")
        let coverURL = sessionDir.appendingPathComponent("cover.jpg")

        let customAvatarData = try XCTUnwrap(
            makeImage(color: .purple, size: CGSize(width: 96, height: 96)).jpegData(compressionQuality: 1.0)
        )
        try customAvatarData.write(to: avatarURL)

        let coverData = try XCTUnwrap(
            makeImage(color: .green, size: CGSize(width: 160, height: 90)).jpegData(compressionQuality: 1.0)
        )
        let coverPath = try SessionRecordManager.shared.saveCoverImage(data: coverData, sessionId: sessionID)
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord.withCoverImagePath(coverPath)).success)

        XCTAssertTrue(
            SessionRecordManager.shared.replaceSessionImage(
                sessionId: sessionID,
                index: 0,
                image: makeImage(color: .yellow, size: CGSize(width: 150, height: 150))
            )
        )

        let updatedRecord = try XCTUnwrap(SessionRecordManager.shared.loadSession(id: sessionID))
        XCTAssertEqual(updatedRecord.avatarImageIndex, 0)
        XCTAssertNil(updatedRecord.coverImagePath)
        XCTAssertEqual(updatedRecord.ocrText, initialRecord.ocrText)
        XCTAssertEqual(updatedRecord.ocrTextSegments, initialRecord.ocrTextSegments)
        XCTAssertEqual(updatedRecord.audioDuration, initialRecord.audioDuration)
        XCTAssertFalse(FileManager.default.fileExists(atPath: coverURL.path))
    }

    func testReplaceSessionImagePreservesAvatarAndCoverWhenReplacingNonFirstImage() throws {
        let sessionID = "replace-session-image-keep-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let initialRecord = SessionRecord(
            id: sessionID,
            name: "replace-session-image-keep",
            images: [
                makeImage(color: .red, size: CGSize(width: 120, height: 120)),
                makeImage(color: .blue, size: CGSize(width: 120, height: 120))
            ],
            ocrText: "旧文本",
            ocrTextSegments: ["旧", "文本"],
            audioData: Data([0x01, 0x02, 0x03]),
            audioFormat: "mp3",
            audioDuration: 1.2,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 2,
            avatarImageIndex: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent("avatar.jpg")
        let coverURL = sessionDir.appendingPathComponent("cover.jpg")

        let customAvatarData = try XCTUnwrap(
            makeImage(color: .purple, size: CGSize(width: 96, height: 96)).jpegData(compressionQuality: 1.0)
        )
        try customAvatarData.write(to: avatarURL)

        let coverData = try XCTUnwrap(
            makeImage(color: .green, size: CGSize(width: 160, height: 90)).jpegData(compressionQuality: 1.0)
        )
        let coverPath = try SessionRecordManager.shared.saveCoverImage(data: coverData, sessionId: sessionID)
        XCTAssertTrue(SessionRecordManager.shared.saveSession(initialRecord.withCoverImagePath(coverPath)).success)

        XCTAssertTrue(
            SessionRecordManager.shared.replaceSessionImage(
                sessionId: sessionID,
                index: 1,
                image: makeImage(color: .yellow, size: CGSize(width: 150, height: 150))
            )
        )

        let updatedRecord = try XCTUnwrap(SessionRecordManager.shared.loadSession(id: sessionID))
        XCTAssertEqual(updatedRecord.avatarImageIndex, 1)
        XCTAssertEqual(updatedRecord.coverImagePath, coverPath)
        XCTAssertEqual(updatedRecord.ocrText, initialRecord.ocrText)
        XCTAssertEqual(updatedRecord.ocrTextSegments, initialRecord.ocrTextSegments)
        XCTAssertEqual(updatedRecord.audioDuration, initialRecord.audioDuration)
        XCTAssertTrue(FileManager.default.fileExists(atPath: avatarURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: coverURL.path))
    }

    func testValidateTransferredSessionDirectoryReportsMissingImageReason() throws {
        let sessionID = "integrity-validate-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-validate",
            images: [makeImage(color: .orange)],
            ocrText: "校验缺图",
            ocrTextSegments: ["校验缺图"],
            audioData: Data([0x71, 0x72, 0x73]),
            audioFormat: "mp3",
            audioDuration: 1.1,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity_validate_export_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        try FileManager.default.removeItem(at: exportedSessionDir.appendingPathComponent("integrity.json"))
        let imageURL = exportedSessionDir.appendingPathComponent("images/image_0.jpg")
        try FileManager.default.removeItem(at: imageURL)

        let result = SessionRecordManager.shared.validateTransferredSessionDirectory(exportedSessionDir)
        XCTAssertEqual(result, .invalid(reason: "缺少图片文件 image_0.jpg"))
    }

    func testValidateTransferredSessionDirectoryReportsIntegrityFailureFileDetail() throws {
        let sessionID = "integrity-detail-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-detail",
            images: [makeImage(color: .cyan)],
            ocrText: "校验明细",
            ocrTextSegments: ["校验明细"],
            audioData: Data([0x61, 0x62, 0x63, 0x64]),
            audioFormat: "mp3",
            audioDuration: 1.2,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity_detail_export_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let imageURL = exportedSessionDir.appendingPathComponent("images/image_0.jpg")
        try Data([0x00, 0x01, 0x02]).write(to: imageURL, options: .atomic)

        let result = SessionRecordManager.shared.validateTransferredSessionDirectory(exportedSessionDir)
        guard case .invalid(let reason) = result else {
            return XCTFail("Expected integrity validation to fail")
        }
        XCTAssertTrue(reason.contains("完整性校验失败:"))
        XCTAssertTrue(reason.contains("images/image_0.jpg"))
        XCTAssertTrue(reason.contains("文件大小不匹配") || reason.contains("文件 MD5 不匹配"))
    }

    func testValidateTransferredSessionDirectoryAcceptsLegacyImagePathInIntegrityManifest() throws {
        let sessionID = "integrity-legacy-image-path-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "integrity-legacy-image-path",
            images: [makeImage(color: .brown)],
            ocrText: "兼容旧图片路径",
            ocrTextSegments: ["兼容旧图片路径"],
            audioData: Data([0x21, 0x22, 0x23]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0.1,
            ttsDuration: 0.2,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let exportRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity_legacy_image_path_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: exportRoot) }

        let exportResult = SessionRecordManager.shared.exportSession(id: sessionID, to: exportRoot)
        XCTAssertTrue(exportResult.success)

        let exportedSessionDir = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: exportRoot, includingPropertiesForKeys: [.isDirectoryKey])
                .first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true })
        )

        let integrityURL = exportedSessionDir.appendingPathComponent("integrity.json")
        let integrityData = try Data(contentsOf: integrityURL)
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: integrityData) as? [String: Any])
        let files = try XCTUnwrap(jsonObject["files"] as? [[String: Any]])
        let mutatedFiles = files.map { file -> [String: Any] in
            guard let path = file["path"] as? String, path == "images/image_0.jpg" else {
                return file
            }
            var mutated = file
            mutated["path"] = "image_0.jpg"
            return mutated
        }

        var mutatedObject = jsonObject
        mutatedObject["files"] = mutatedFiles
        let mutatedData = try JSONSerialization.data(withJSONObject: mutatedObject, options: [.prettyPrinted, .sortedKeys])
        try mutatedData.write(to: integrityURL, options: .atomic)

        XCTAssertEqual(
            SessionRecordManager.shared.validateTransferredSessionDirectory(exportedSessionDir),
            .valid(id: sessionID, name: "integrity-legacy-image-path")
        )
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
    
    // MARK: - 传输大小估算测试

    func testTransferEstimatedSizeForFullRecordUsesSessionDirectorySize() throws {
        let sessionID = "transfer-size-full-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "transfer-size-full",
            images: [makeImage(color: .red)],
            ocrText: "测试",
            ocrTextSegments: ["测试"],
            audioData: Data([0x01, 0x02, 0x03]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)

        let sessionDir = SessionRecordManager.shared.sessionsDirectory.appendingPathComponent(sessionID, isDirectory: true)
        let expectedSize = directorySize(sessionDir)

        XCTAssertEqual(
            SessionRecordManager.shared.transferEstimatedSize(sessionIDs: [sessionID], mode: .full),
            expectedSize
        )
        XCTAssertEqual(
            SessionRecordManager.shared.transferEstimatedSize(sessionIDs: [sessionID], mode: .fullWithStats),
            expectedSize
        )
    }

    func testTransferEstimatedSizeForPlayOnlyUsesHistoryFilesOnly() throws {
        let sessionID = "transfer-size-play-\(UUID().uuidString)"
        let missingHistoryID = "transfer-size-missing-\(UUID().uuidString)"
        createdSessionIDs += [sessionID, missingHistoryID]

        let record = SessionRecord(
            id: sessionID,
            name: "transfer-size-play",
            images: [makeImage(color: .blue)],
            ocrText: "测试",
            ocrTextSegments: ["测试"],
            audioData: Data([0x01, 0x02, 0x03, 0x04]),
            audioFormat: "mp3",
            audioDuration: 1.0,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 1
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)
        SessionRecordManager.shared.saveSessionHistory(
            sessionId: sessionID,
            history: SessionHistory(makeEvents: [], playEvents: [SessionHistoryEvent(timestamp: Date(), identity: "iPhone")])
        )

        let missingRecord = SessionRecord(
            id: missingHistoryID,
            name: "transfer-size-missing",
            images: [],
            ocrText: "测试",
            ocrTextSegments: ["测试"],
            audioData: Data(),
            audioFormat: "mp3",
            audioDuration: 0,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 0
        )
        XCTAssertTrue(SessionRecordManager.shared.saveSession(missingRecord).success)
        let missingHistoryURL = SessionRecordManager.shared.sessionsDirectory
            .appendingPathComponent(missingHistoryID, isDirectory: true)
            .appendingPathComponent("history.json")
        try? FileManager.default.removeItem(at: missingHistoryURL)

        let historyURL = SessionRecordManager.shared.sessionsDirectory
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("history.json")
        let expectedSize = Int64(try historyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)

        XCTAssertEqual(
            SessionRecordManager.shared.transferEstimatedSize(sessionIDs: [sessionID, missingHistoryID], mode: .playOnly),
            expectedSize
        )
    }

    // MARK: - 相机组件测试

    func testCustomCameraViewControllerCreation() {
        let cameraVC = CustomCameraViewController()
        XCTAssertNotNil(cameraVC, "CustomCameraViewController should be created successfully")
    }

    // MARK: - 首页启动预热测试

    func testPreloadHomeCardCoverCachesFallbackImage() {
        let sessionID = "home-card-cover-\(UUID().uuidString)"
        createdSessionIDs.append(sessionID)

        let record = SessionRecord(
            id: sessionID,
            name: "26.04.20 启动预热测试",
            images: [makeImage(color: .red)],
            ocrText: "测试",
            ocrTextSegments: ["测试"],
            audioData: Data(),
            audioFormat: "mp3",
            audioDuration: 0,
            ocrDuration: 0,
            ttsDuration: 0,
            validImageCount: 1
        )

        XCTAssertTrue(SessionRecordManager.shared.saveSession(record).success)
        XCTAssertNil(SessionRecordManager.shared.loadHomeCardCoverIfCached(sessionId: sessionID))

        let preloadFinished = expectation(description: "home-card-cover-preloaded")
        SessionRecordManager.shared.preloadHomeCardCover(
            sessionId: sessionID,
            avatarImageIndex: 0,
            totalImageCount: 1
        )

        DispatchQueue.global().async {
            for _ in 0..<20 {
                if SessionRecordManager.shared.loadHomeCardCoverIfCached(sessionId: sessionID) != nil {
                    preloadFinished.fulfill()
                    return
                }
                usleep(50_000)
            }
        }

        wait(for: [preloadFinished], timeout: 2.0)
        XCTAssertNotNil(SessionRecordManager.shared.loadHomeCardCoverIfCached(sessionId: sessionID))
    }
    
    // MARK: - SessionRecordMetadata seriesName 测试

    private func makeMetadata(id: String = UUID().uuidString, name: String, createdAt: Date = Date()) -> SessionRecordMetadata {
        SessionRecordMetadata(id: id, name: name, createdAt: createdAt, updatedAt: createdAt, totalImageCount: 1, validImageCount: 1, textLength: 100, audioDuration: 60, avatarImageIndex: 0, storageSize: 1024)
    }

    private func makeImage(color: UIColor, size: CGSize = CGSize(width: 40, height: 40)) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
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

    // MARK: - 首页排序测试

    func testHomeListSort_ordersByDateThenSeriesThenName() {
        let items = [
            makeMetadata(name: "26.03.17 小熊-B"),
            makeMetadata(name: "26.03.18 小熊-B"),
            makeMetadata(name: "26.03.18 白雪-A"),
            makeMetadata(name: "26.03.18 小熊-A")
        ]

        let sortedNames = SessionRecordManager.sortSessionMetadata(items, by: .list).map(\.name)

        XCTAssertEqual(sortedNames, [
            "26.03.18 白雪-A",
            "26.03.18 小熊-A",
            "26.03.18 小熊-B",
            "26.03.17 小熊-B"
        ])
    }

    func testHomeSeriesSort_ordersBySeriesThenDateThenName() {
        let items = [
            makeMetadata(name: "26.03.17 小熊-B"),
            makeMetadata(name: "26.03.18 小熊-B"),
            makeMetadata(name: "26.03.18 白雪-A"),
            makeMetadata(name: "26.03.18 小熊-A")
        ]

        let sortedNames = SessionRecordManager.sortSessionMetadata(items, by: .series).map(\.name)

        XCTAssertEqual(sortedNames, [
            "26.03.18 白雪-A",
            "26.03.18 小熊-A",
            "26.03.18 小熊-B",
            "26.03.17 小熊-B"
        ])
    }

    func testHomeSeriesSort_placesUncategorizedLast() {
        let items = [
            makeMetadata(name: "26.03.18 小熊-第一章"),
            makeMetadata(name: "26.03.18 没有系列名"),
            makeMetadata(name: "26.03.18 白雪-第一章")
        ]

        let sortedNames = SessionRecordManager.sortSessionMetadata(items, by: .series).map(\.name)

        XCTAssertEqual(sortedNames, [
            "26.03.18 白雪-第一章",
            "26.03.18 小熊-第一章",
            "26.03.18 没有系列名"
        ])
    }

    func testHomePlayPlanSort_listModePromotesEarliestTodoDate() {
        let items = [
            makeMetadata(id: "b", name: "26.03.18 小熊-A"),
            makeMetadata(id: "a", name: "26.03.17 白雪-A"),
            makeMetadata(id: "c", name: "26.03.18 白雪-B")
        ]

        let (sortedItems, todoIds) = HomePagePlayPlanHelper.applySort(
            to: items,
            statsMap: [:],
            sortMode: .list,
            playPlanEnabled: true,
            isTodayProcessed: false,
            now: makeDate("2026-03-20")
        )

        XCTAssertEqual(sortedItems.map(\.id), ["a"])
        XCTAssertEqual(todoIds, Set(["a"]))
    }

    func testHomePlayPlanSort_seriesModeHidesItemsAfterPlanDate() {
        let items = [
            makeMetadata(id: "b", name: "26.03.18 小熊-A"),
            makeMetadata(id: "a", name: "26.03.17 白雪-A"),
            makeMetadata(id: "c", name: "26.03.18 白雪-B")
        ]

        let (sortedItems, todoIds) = HomePagePlayPlanHelper.applySort(
            to: items,
            statsMap: [:],
            sortMode: .series,
            playPlanEnabled: true,
            isTodayProcessed: false,
            now: makeDate("2026-03-20")
        )

        XCTAssertEqual(sortedItems.map(\.id), ["a"])
        XCTAssertEqual(todoIds, Set(["a"]))
    }

    func testHomePlayPlanSort_todayProcessedHidesItemsAfterProcessedPlanDate() {
        let items = [
            makeMetadata(id: "future", name: "26.03.19 小熊-A"),
            makeMetadata(id: "plan", name: "26.03.18 白雪-A"),
            makeMetadata(id: "past", name: "26.03.17 小兔-A")
        ]

        let (sortedItems, todoIds) = HomePagePlayPlanHelper.applySort(
            to: items,
            statsMap: [:],
            sortMode: .list,
            playPlanEnabled: true,
            isTodayProcessed: true,
            todayProcessedTodoDate: makeDate("2026-03-18"),
            now: makeDate("2026-03-20")
        )

        XCTAssertEqual(sortedItems.map(\.id), ["plan", "past"])
        XCTAssertTrue(todoIds.isEmpty)
    }

    func testHomePlayPlanQueue_onlyListModeUsesPlanQueue() {
        XCTAssertTrue(HomePagePlayPlanHelper.shouldUsePlanQueue(sortMode: .list, playPlanEnabled: true, isTodoRecord: true))
        XCTAssertFalse(HomePagePlayPlanHelper.shouldUsePlanQueue(sortMode: .series, playPlanEnabled: true, isTodoRecord: true))
        XCTAssertFalse(HomePagePlayPlanHelper.shouldUsePlanQueue(sortMode: .list, playPlanEnabled: true, isTodoRecord: false))
    }

    func testHomeVisiblePlayStatsDetectsNewPlayEvent() {
        let visibleItems = [
            makeMetadata(id: "played", name: "26.03.18 小熊-A"),
            makeMetadata(id: "unplayed", name: "26.03.18 小熊-B")
        ]
        let latestStats = [
            "played": PlayStatInfo(lastPlayedAt: makeDate("2026-03-20"), playCount: 1)
        ]

        XCTAssertTrue(HomePagePlayPlanHelper.hasVisiblePlayStatsChange(
            visibleItems: visibleItems,
            currentStatsMap: [:],
            latestStatsMap: latestStats
        ))
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

    private func makeDate(_ value: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.date(from: value)!
    }

    private func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        return enumerator.reduce(Int64(0)) { total, item in
            guard let fileURL = item as? URL,
                  let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
                return total
            }
            return total + Int64(fileSize)
        }
    }

    private func loadHistory(from url: URL) throws -> SessionHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SessionHistory.self, from: Data(contentsOf: url))
    }
}
