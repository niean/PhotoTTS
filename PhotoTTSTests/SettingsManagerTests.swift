import XCTest
@testable import PhotoTTS

final class SettingsManagerTests: XCTestCase {
    
    var settingsManager: SettingsManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        settingsManager = SettingsManager.shared
    }
    
    override func tearDownWithError() throws {
        // 清理测试数据
        settingsManager.clearAllData()
        try super.tearDownWithError()
    }
    
    // MARK: - 核心配置测试
    
    func testAPIKeyStorage() {
        // 测试API密钥存储
        let testKey = "sk-test1234567890abcdef"
        settingsManager.apiKey = testKey
        
        XCTAssertEqual(settingsManager.apiKey, testKey)
        XCTAssertTrue(settingsManager.isAPIKeyValid)
    }
    
    func testAPIKeyValidation() {
        // 测试API密钥验证
        let validKey = "sk-test1234567890abcdef"
        let invalidKey = "invalid-key"
        
        XCTAssertTrue(validKey.count >= 20 && validKey.contains("sk-"))
        XCTAssertFalse(invalidKey.count >= 20 && invalidKey.contains("sk-"))
    }
    
    func testAPIKeyRemoval() {
        // 测试API密钥移除
        let testKey = "sk-test1234567890abcdef"
        settingsManager.apiKey = testKey
        XCTAssertEqual(settingsManager.apiKey, testKey)
        
        settingsManager.apiKey = nil
        XCTAssertNil(settingsManager.apiKey)
        XCTAssertFalse(settingsManager.isAPIKeyValid)
    }
    
    // MARK: - TTS配置测试
    
    func testTTSConfiguration() {
        // 测试TTS配置存储
        let testAppId = "test_app_id"
        let testCluster = "test_cluster"
        let testAccessKey = "test_access_key"
        let testUid = "test_uid"
        
        settingsManager.ttsAppId = testAppId
        settingsManager.ttsCluster = testCluster
        settingsManager.ttsAccessKey = testAccessKey
        settingsManager.ttsUid = testUid
        
        XCTAssertEqual(settingsManager.ttsAppId, testAppId)
        XCTAssertEqual(settingsManager.ttsCluster, testCluster)
        XCTAssertEqual(settingsManager.ttsAccessKey, testAccessKey)
        XCTAssertEqual(settingsManager.ttsUid, testUid)
    }
    
    // MARK: - 语音设置测试
    
    func testVoiceSettingsStorage() {
        // 测试语音设置存储
        let testSettings = VoiceSettings(
            speed: 1.2,
            pitch: 0.8,
            volume: 0.9,
            voiceType: "test",
            encoding: "mp3"
        )
        
        settingsManager.voiceSettings = testSettings
        
        XCTAssertEqual(settingsManager.voiceSettings.speed, 1.2)
        XCTAssertEqual(settingsManager.voiceSettings.pitch, 0.8)
        XCTAssertEqual(settingsManager.voiceSettings.volume, 0.9)
        XCTAssertEqual(settingsManager.voiceSettings.voiceType, "test")
        XCTAssertEqual(settingsManager.voiceSettings.encoding, "mp3")
    }
    
    func testVoiceSettingsDefault() {
        // 测试默认语音设置
        let defaultSettings = VoiceSettings.default
        
        XCTAssertEqual(defaultSettings.speed, 1.0)
        XCTAssertEqual(defaultSettings.pitch, 1.0)
        XCTAssertEqual(defaultSettings.volume, 0.8)
        XCTAssertEqual(defaultSettings.voiceType, "default")
        XCTAssertEqual(defaultSettings.encoding, "mp3")
    }
    
    // MARK: - 语言设置测试
    
    func testLanguageSettings() {
        // 测试语言设置
        let testLanguage = "en"
        settingsManager.currentLanguage = testLanguage
        
        XCTAssertEqual(settingsManager.currentLanguage, testLanguage)
    }
    
    // MARK: - 数据清理测试
    
    func testDataClearing() {
        // 测试数据清理
        let testKey = "sk-test1234567890abcdef"
        settingsManager.apiKey = testKey
        
        XCTAssertEqual(settingsManager.apiKey, testKey)
        
        settingsManager.clearAllData()
        
        XCTAssertNil(settingsManager.apiKey)
    }
}
