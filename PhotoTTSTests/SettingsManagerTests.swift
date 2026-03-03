import XCTest
@testable import PhotoTTS

final class SettingsManagerTests: XCTestCase {
    
    var settingsManager: SettingsManager!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        settingsManager = SettingsManager.shared
    }
    
    override func tearDownWithError() throws {
        // 注意：clearAllData 会清除真实的 Keychain 和 UserDefaults 数据
        // 仅在模拟器环境中运行此测试
        settingsManager.clearAllData()
        try super.tearDownWithError()
    }
    
    // MARK: - API 密钥测试
    
    func testAPIKeyStorage() {
        let testKey = "sk-test1234567890abcdef"
        settingsManager.apiKey = testKey
        
        XCTAssertEqual(settingsManager.apiKey, testKey)
        XCTAssertTrue(settingsManager.isAPIKeyValid)
    }
    
    func testAPIKeyValidation() {
        // isAPIKeyValid 检查 apiKey 是否非空
        settingsManager.apiKey = nil
        XCTAssertFalse(settingsManager.isAPIKeyValid)
        
        settingsManager.apiKey = ""
        XCTAssertFalse(settingsManager.isAPIKeyValid)
        
        settingsManager.apiKey = "any-non-empty-key"
        XCTAssertTrue(settingsManager.isAPIKeyValid)
    }
    
    func testAPIKeyRemoval() {
        let testKey = "sk-test1234567890abcdef"
        settingsManager.apiKey = testKey
        XCTAssertEqual(settingsManager.apiKey, testKey)
        
        settingsManager.apiKey = nil
        XCTAssertNil(settingsManager.apiKey)
        XCTAssertFalse(settingsManager.isAPIKeyValid)
    }
    
    // MARK: - TTS 配置测试
    
    func testTTSConfiguration() {
        let testAppId = "test_app_id"
        let testCluster = "test_cluster"
        let testAccessKey = "test_access_key"
        let testUid = "test_uid"
        
        settingsManager.ttsAppId = testAppId
        settingsManager.ttsCluster = testCluster
        settingsManager.accessKey = testAccessKey
        settingsManager.ttsUid = testUid
        
        XCTAssertEqual(settingsManager.ttsAppId, testAppId)
        XCTAssertEqual(settingsManager.ttsCluster, testCluster)
        XCTAssertEqual(settingsManager.accessKey, testAccessKey)
        XCTAssertEqual(settingsManager.ttsUid, testUid)
    }
    
    func testTTSCredentialsValidation() {
        settingsManager.accessKey = nil
        XCTAssertFalse(settingsManager.isTTSCredentialsValid)
        
        settingsManager.accessKey = ""
        XCTAssertFalse(settingsManager.isTTSCredentialsValid)
        
        settingsManager.accessKey = "valid_key"
        XCTAssertTrue(settingsManager.isTTSCredentialsValid)
    }
    
    // MARK: - 语音设置测试
    
    func testVoiceSettingsStorage() {
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
        let defaultSettings = VoiceSettings.default
        
        XCTAssertEqual(defaultSettings.speed, 1.0)
        XCTAssertEqual(defaultSettings.pitch, 1.0)
        XCTAssertEqual(defaultSettings.volume, 1.0)
        XCTAssertEqual(defaultSettings.voiceType, "default")
        XCTAssertEqual(defaultSettings.encoding, "mp3")
    }
    
    // MARK: - 语言设置测试
    
    func testLanguageSettings() {
        let testLanguage = "en"
        settingsManager.currentLanguage = testLanguage
        
        XCTAssertEqual(settingsManager.currentLanguage, testLanguage)
    }
    
    // MARK: - 数据清理测试
    
    func testDataClearing() {
        let testKey = "sk-test1234567890abcdef"
        settingsManager.apiKey = testKey
        XCTAssertEqual(settingsManager.apiKey, testKey)
        
        settingsManager.clearAllData()
        
        XCTAssertNil(settingsManager.apiKey)
        XCTAssertFalse(settingsManager.isAPIKeyValid)
    }
}
