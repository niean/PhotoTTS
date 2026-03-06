import Foundation
import UIKit
import os.log
import Security

// MARK: - 设置管理器协议
/// 设置管理器代理协议，用于通知设置变更
protocol SettingsManagerDelegate: AnyObject {
    /// API密钥更新时的回调
    /// - Parameters:
    ///   - manager: 设置管理器实例
    ///   - key: 新的API密钥
    func settingsManager(_ manager: SettingsManager, didUpdateAPIKey key: String)
    
    /// 语音设置更新时的回调
    /// - Parameters:
    ///   - manager: 设置管理器实例
    ///   - settings: 新的语音设置
    func settingsManager(_ manager: SettingsManager, didUpdateVoiceSettings settings: VoiceSettings)
    
    /// 语言设置更新时的回调
    /// - Parameters:
    ///   - manager: 设置管理器实例
    ///   - languages: 新的支持语言列表
    func settingsManager(_ manager: SettingsManager, didUpdateLanguageSettings languages: [String])
    
    // 家长控制功能已移除
}

// MARK: - 设置管理器
/// 应用设置管理器，负责管理所有用户配置和设置
/// 包括API密钥、语音设置、语言设置、家长控制等
/// 使用UserDefaults存储普通设置，Keychain存储敏感信息
class SettingsManager {
    /// 共享实例，单例模式
    static let shared = SettingsManager()
    
    // MARK: - 属性
    /// 设置变更代理
    weak var delegate: SettingsManagerDelegate?
    
    // MARK: - 设置存储
    /// UserDefaults实例，用于存储普通设置
    private let userDefaults = UserDefaults.standard
    
    /// Keychain服务名称
    private let keychainService = "com.photoTTS.PhotoTTS"
    
    // MARK: - 初始化
    private init() {
        setupDefaultSettings()
    }
    
    // MARK: - Keychain 操作
    /// 从Keychain读取字符串
    private func keychainString(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    /// 向Keychain写入字符串
    private func keychainSet(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        // 先删除现有项
        SecItemDelete(query as CFDictionary)
        
        // 添加新项
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// 从Keychain删除项
    private func keychainRemove(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// 清空所有Keychain项
    private func keychainRemoveAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    // MARK: - API设置
    var apiKey: String? {
        get { 
            return keychainString(forKey: AppConstants.KeychainKeys.doubaoAPIKey) 
        }
        set { 
            if let newValue = newValue {
                _ = keychainSet(newValue, forKey: AppConstants.KeychainKeys.doubaoAPIKey)
                delegate?.settingsManager(self, didUpdateAPIKey: newValue)
            } else {
                _ = keychainRemove(forKey: AppConstants.KeychainKeys.doubaoAPIKey)
            }
        }
    }
    
    var isAPIKeyValid: Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }
    
    /// 获取豆包API密钥
    /// - Returns: API密钥字符串，如果不存在则返回nil
    func getDoubaoAPIKey() -> String? {
        return apiKey
    }
    
    // MARK: - TTS设置
    var accessKey: String? {
        get { 
            return keychainString(forKey: AppConstants.KeychainKeys.ttsAccessKey) 
        }
        set { 
            if let newValue = newValue {
                _ = keychainSet(newValue, forKey: AppConstants.KeychainKeys.ttsAccessKey)
            } else {
                _ = keychainRemove(forKey: AppConstants.KeychainKeys.ttsAccessKey)
            }
        }
    }
    
    var ttsAppId: String {
        get { 
            return userDefaults.string(forKey: AppConstants.UserDefaultsKeys.ttsAppId) ?? "4949282805"
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.ttsAppId)
        }
    }
    
    var ttsCluster: String {
        get { 
            return userDefaults.string(forKey: AppConstants.UserDefaultsKeys.ttsCluster) ?? "volcano_tts"
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.ttsCluster)
        }
    }
    
    var ttsUid: String {
        get { 
            return userDefaults.string(forKey: AppConstants.UserDefaultsKeys.ttsUid) ?? ""
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.ttsUid)
        }
    }
    
    var isTTSCredentialsValid: Bool {
        return accessKey != nil && !accessKey!.isEmpty
    }
    
    // MARK: - 语音设置
    var voiceSettings: VoiceSettings {
        get {
            let data = userDefaults.data(forKey: AppConstants.UserDefaultsKeys.voiceSettings) ?? Data()
            return (try? JSONDecoder().decode(VoiceSettings.self, from: data)) ?? VoiceSettings.default
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                userDefaults.set(data, forKey: AppConstants.UserDefaultsKeys.voiceSettings)
                delegate?.settingsManager(self, didUpdateVoiceSettings: newValue)
            }
        }
    }
    
    // MARK: - 语言设置
    var supportedLanguages: [String] {
        get { 
            return userDefaults.stringArray(forKey: AppConstants.UserDefaultsKeys.supportedLanguages) ?? AppConstants.Language.defaultLanguages
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.supportedLanguages)
            delegate?.settingsManager(self, didUpdateLanguageSettings: newValue)
        }
    }
    
    var currentLanguage: String {
        get { 
            return userDefaults.string(forKey: AppConstants.UserDefaultsKeys.currentLanguage) ?? AppConstants.Language.defaultCurrent
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.currentLanguage)
        }
    }
    
    // 家长控制功能已移除
    
    // MARK: - 身份名称
    /// 用户身份名称，默认取设备名称
    var identityName: String {
        get {
            let stored = userDefaults.string(forKey: AppConstants.UserDefaultsKeys.identityName)
            if let stored = stored, !stored.isEmpty {
                return stored
            }
            return UIDevice.current.name
        }
        set {
            let trimmed = String(newValue.prefix(AppConstants.Identity.nameMaxLength))
            if trimmed.isEmpty {
                userDefaults.removeObject(forKey: AppConstants.UserDefaultsKeys.identityName)
            } else {
                userDefaults.set(trimmed, forKey: AppConstants.UserDefaultsKeys.identityName)
            }
        }
    }

    // MARK: - 应用设置
    var isFirstLaunch: Bool {
        get { 
            return userDefaults.bool(forKey: AppConstants.UserDefaultsKeys.isFirstLaunch) 
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.isFirstLaunch)
        }
    }
    
    var appLaunchCount: Int {
        get { 
            return userDefaults.integer(forKey: AppConstants.UserDefaultsKeys.appLaunchCount) 
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.appLaunchCount)
        }
    }
    
    var lastLaunchDate: Date? {
        get { 
            return userDefaults.object(forKey: AppConstants.UserDefaultsKeys.lastLaunchDate) as? Date 
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.lastLaunchDate)
        }
    }
    
    // MARK: - 存储设置
    var maxCacheSize: Int64 {
        get { 
            return userDefaults.object(forKey: AppConstants.UserDefaultsKeys.maxCacheSize) as? Int64 ?? AppConstants.Cache.maxCacheSize
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.maxCacheSize)
        }
    }
    
    var autoCleanupEnabled: Bool {
        get { 
            return userDefaults.bool(forKey: AppConstants.UserDefaultsKeys.autoCleanupEnabled) 
        }
        set { 
            userDefaults.set(newValue, forKey: AppConstants.UserDefaultsKeys.autoCleanupEnabled)
        }
    }
    
    // MARK: - 配置读取方法
    
    /// 读取配置文件的完整内容
    /// - Returns: 配置字典，如果读取失败返回nil
    func loadConfig() -> [String: Any]? {
        // 优先从Documents目录读取用户自定义配置
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let userConfigURL = documentsPath.appendingPathComponent("config_local.json")
        
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            do {
                let configData = try Data(contentsOf: userConfigURL)
                let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
                return config
            } catch {
                os.Logger.settingsManager.error("读取用户配置文件失败: \(error.localizedDescription)")
            }
        }
        
        // 回退到Bundle中的默认配置
        guard let bundleConfigPath = Bundle.main.path(forResource: "config_local", ofType: "json") else {
            os.Logger.settingsManager.error("找不到默认配置文件")
            return nil
        }
        
        do {
            let configData = try Data(contentsOf: URL(fileURLWithPath: bundleConfigPath))
            let config = try JSONSerialization.jsonObject(with: configData) as? [String: Any]
            os.Logger.settingsManager.info("成功读取默认配置文件: \(bundleConfigPath)")
            return config
        } catch {
            os.Logger.settingsManager.error("读取默认配置文件失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 读取配置文件的原始JSON字符串
    /// - Returns: JSON字符串，如果读取失败返回nil
    func loadConfigAsString() -> String? {
        // 优先从Documents目录读取用户自定义配置
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let userConfigURL = documentsPath.appendingPathComponent("config_local.json")
        
        if FileManager.default.fileExists(atPath: userConfigURL.path) {
            do {
                let configData = try Data(contentsOf: userConfigURL)
                let configString = String(data: configData, encoding: .utf8)
                return configString
            } catch {
                os.Logger.settingsManager.error("读取用户配置文件字符串失败: \(error.localizedDescription)")
            }
        }
        
        // 回退到Bundle中的默认配置
        guard let bundleConfigPath = Bundle.main.path(forResource: "config_local", ofType: "json") else {
            os.Logger.settingsManager.error("找不到默认配置文件")
            return nil
        }
        
        do {
            let configData = try Data(contentsOf: URL(fileURLWithPath: bundleConfigPath))
            let configString = String(data: configData, encoding: .utf8)
            os.Logger.settingsManager.info("成功读取默认配置文件字符串: \(bundleConfigPath)")
            return configString
        } catch {
            os.Logger.settingsManager.error("读取默认配置文件字符串失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 加载默认配置（从Bundle中的配置文件）
    /// - Returns: 默认配置的JSON字符串，如果读取失败返回"{}"
    func loadDefaultConfig() -> String {
        guard let configPath = Bundle.main.path(forResource: "config_local", ofType: "json") else {
            os.Logger.settingsManager.error("找不到Bundle中的config_local.json配置文件")
            return "{}"
        }
        
        do {
            let configData = try Data(contentsOf: URL(fileURLWithPath: configPath))
            let configString = String(data: configData, encoding: .utf8) ?? "{}"
            os.Logger.settingsManager.info("成功加载Bundle中的默认配置")
            return configString
        } catch {
            os.Logger.settingsManager.error("读取Bundle配置文件失败: \(error.localizedDescription)")
            return "{}"
        }
    }
    
    /// 读取系统配置部分
    /// - Returns: 系统配置字典，如果读取失败返回空字典
    func loadSystemConfig() -> [String: Any] {
        guard let config = loadConfig(),
              let sysConfig = config["sys"] as? [String: Any] else {
            os.Logger.settingsManager.error("读取系统配置失败，使用空配置")
            return [:]
        }
        return sysConfig
    }
    
    /// 读取OCR配置部分（完整ocr节点）
    /// - Returns: OCR配置字典，如果读取失败返回空字典
    func loadOCRConfig() -> [String: Any] {
        guard let config = loadConfig(),
              let ocrConfig = config["ocr"] as? [String: Any] else {
            os.Logger.settingsManager.error("读取OCR配置失败，使用空配置")
            return [:]
        }
        return ocrConfig
    }
    
    /// 读取当前活跃的OCR模型名称
    /// - Returns: 模型名称（"doubao"或"openai"），默认"doubao"
    func getActiveOCRModel() -> String {
        let ocrConfig = loadOCRConfig()
        let model = ocrConfig["model"] as? String ?? "doubao"
        let supported = ["doubao", "openai"]
        if supported.contains(model) {
            return model
        }
        os.Logger.settingsManager.warning("不支持的OCR模型: \(model)，回退到doubao")
        return "doubao"
    }
    
    /// 读取活跃OCR模型的子配置
    /// - Returns: 活跃模型的配置字典（base_url/model_name/api_key等），如果读取失败返回空字典
    func loadActiveOCRModelConfig() -> [String: Any] {
        let ocrConfig = loadOCRConfig()
        let activeModel = getActiveOCRModel()
        guard let modelConfig = ocrConfig[activeModel] as? [String: Any] else {
            os.Logger.settingsManager.error("读取OCR模型[\(activeModel)]子配置失败，使用空配置")
            return [:]
        }
        return modelConfig
    }
    
    /// 获取指定OCR模型的Keychain key
    /// - Parameter model: 模型名称
    /// - Returns: 对应的Keychain key
    private func keychainKeyForOCRModel(_ model: String) -> String {
        switch model {
        case "openai":
            return AppConstants.KeychainKeys.openaiOCRAPIKey
        default:
            return AppConstants.KeychainKeys.doubaoAPIKey
        }
    }
    
    /// 读取指定OCR模型的API密钥（优先Keychain，回退config，首次回退写入Keychain）
    /// - Parameter model: 模型名称
    /// - Returns: API密钥，如果读取失败返回空字符串
    func getOCRAPIKeyForModel(_ model: String) -> String {
        let keychainKey = keychainKeyForOCRModel(model)
        // 优先从 Keychain 读取
        if let stored = keychainString(forKey: keychainKey), !stored.isEmpty {
            return stored
        }
        // 回退到 config 文件中对应模型的子配置
        let ocrConfig = loadOCRConfig()
        guard let modelConfig = ocrConfig[model] as? [String: Any] else {
            return ""
        }
        let configKey = modelConfig["api_key"] as? String ?? ""
        // 首次从 config 读取后写入 Keychain
        if !configKey.isEmpty {
            _ = keychainSet(configKey, forKey: keychainKey)
            os.Logger.settingsManager.info("OCR[\(model)] API密钥已从配置文件迁移到Keychain")
        }
        return configKey
    }
    
    /// 读取TTS配置部分
    /// - Returns: TTS配置字典，如果读取失败返回空字典
    func loadTTSConfig() -> [String: Any] {
        guard let config = loadConfig(),
              let ttsConfig = config["tts"] as? [String: Any] else {
            os.Logger.settingsManager.error("读取TTS配置失败，使用空配置")
            return [:]
        }
        return ttsConfig
    }
    
    // MARK: - 具体配置项读取方法
    
    /// 读取OCR并发数配置
    /// - Returns: OCR并发数，默认为1
    func getOCRConcurrentCount() -> Int {
        let sysConfig = loadSystemConfig()
        let concurrentCount = sysConfig["ocr_concurrent_count"] as? Int ?? AppConstants.defaultOCRConcurrentCount
        os.Logger.settingsManager.info("读取OCR并发数配置: \(concurrentCount)")
        return max(1, concurrentCount) // 确保至少为1
    }
    
    /// 读取TTS最大字符限制配置
    /// - Returns: TTS最大字符数，默认为10240
    func getTTSMaxLength() -> Int {
        let sysConfig = loadSystemConfig()
        let maxLength = sysConfig["tts_text_max_length"] as? Int ?? AppConstants.defaultTTSMaxLength
        os.Logger.settingsManager.info("读取TTS字符限制配置: \(maxLength)")
        return max(1, maxLength)
    }
    
    /// 读取OCR基础URL
    /// - Returns: OCR基础URL，如果读取失败返回空字符串
    func getOCRBaseURL() -> String {
        let ocrConfig = loadOCRConfig()
        return ocrConfig["base_url"] as? String ?? ""
    }
    
    /// 读取OCR模型名称
    /// - Returns: OCR模型名称，如果读取失败返回空字符串
    func getOCRModelName() -> String {
        let ocrConfig = loadOCRConfig()
        return ocrConfig["model_name"] as? String ?? ""
    }
    
    /// 读取OCR API密钥（优先从Keychain获取，回退到config文件，首次回退时写入Keychain）
    /// - Returns: OCR API密钥，如果读取失败返回空字符串
    func getOCRAPIKey() -> String {
        // 优先从 Keychain 读取
        if let keychainKey = apiKey, !keychainKey.isEmpty {
            return keychainKey
        }
        // 回退到 config 文件
        let ocrConfig = loadOCRConfig()
        let configKey = ocrConfig["api_key"] as? String ?? ""
        // 首次从 config 读取后写入 Keychain
        if !configKey.isEmpty {
            apiKey = configKey
            os.Logger.settingsManager.info("OCR API密钥已从配置文件迁移到Keychain")
        }
        return configKey
    }
    
    /// 读取OCR用户提示词
    /// - Returns: OCR用户提示词，如果读取失败返回空字符串
    func getOCRUserPrompt() -> String {
        let ocrConfig = loadOCRConfig()
        return ocrConfig["prompt_user"] as? String ?? ""
    }
    
    /// 读取TTS基础URL
    /// - Returns: TTS基础URL，如果读取失败返回空字符串
    func getTTSBaseURL() -> String {
        let ttsConfig = loadTTSConfig()
        return ttsConfig["base_url"] as? String ?? ""
    }
    
    /// 读取TTS应用ID
    /// - Returns: TTS应用ID，如果读取失败返回空字符串
    func getTTSAppID() -> String {
        let ttsConfig = loadTTSConfig()
        return ttsConfig["appid"] as? String ?? ""
    }
    
    /// 读取TTS访问密钥（优先从Keychain获取，回退到config文件，首次回退时写入Keychain）
    /// - Returns: TTS访问密钥，如果读取失败返回空字符串
    func getTTSAccessKey() -> String {
        // 优先从 Keychain 读取
        if let keychainKey = accessKey, !keychainKey.isEmpty {
            return keychainKey
        }
        // 回退到 config 文件
        let ttsConfig = loadTTSConfig()
        let configKey = ttsConfig["access_key"] as? String ?? ""
        // 首次从 config 读取后写入 Keychain
        if !configKey.isEmpty {
            accessKey = configKey
            os.Logger.settingsManager.info("TTS访问密钥已从配置文件迁移到Keychain")
        }
        return configKey
    }
    
    /// 读取TTS集群
    /// - Returns: TTS集群，如果读取失败返回空字符串
    func getTTSCluster() -> String {
        let ttsConfig = loadTTSConfig()
        return ttsConfig["cluster"] as? String ?? ""
    }
    
    /// 读取TTS用户ID
    /// - Returns: TTS用户ID，如果读取失败返回空字符串
    func getTTSUID() -> String {
        let ttsConfig = loadTTSConfig()
        return ttsConfig["uid"] as? String ?? ""
    }
    
    /// 读取TTS语音类型
    /// - Returns: TTS语音类型，如果读取失败返回空字符串
    func getTTSVoiceType() -> String {
        let ttsConfig = loadTTSConfig()
        return ttsConfig["voice_type"] as? String ?? ""
    }
    
    /// 读取TTS编码格式
    /// - Returns: TTS编码格式，如果读取失败返回空字符串
    func getTTSEncoding() -> String {
        let ttsConfig = loadTTSConfig()
        return ttsConfig["encoding"] as? String ?? ""
    }
    
    /// 读取TTS语速比例
    /// - Returns: TTS语速比例，默认为1.0
    func getTTSSpeedRatio() -> Double {
        let ttsConfig = loadTTSConfig()
        return ttsConfig["speed_ratio"] as? Double ?? 1.0
    }
    
    // MARK: - 配置更新方法
    
    /// 更新用户配置文件
    /// - Parameter configContent: 新的配置内容（JSON字符串）
    /// - Returns: 更新是否成功
    func updateUserConfig(_ configContent: String) -> Bool {
        do {
            let configData = configContent.data(using: .utf8)!
            let configURL = getConfigFileURL()
            try configData.write(to: configURL)
            
            // 通知应用重新加载配置
            NotificationCenter.default.post(name: Constants.NotificationNames.configUpdated, object: nil)
            
            os.Logger.settingsManager.info("用户配置文件更新成功: \(configURL.path)")
            return true
        } catch {
            os.Logger.settingsManager.error("更新用户配置文件失败: \(error.localizedDescription)")
            return false
        }
    }
    
    /// 还原用户配置为默认配置
    /// - Returns: 还原是否成功
    func resetUserConfigToDefault() -> Bool {
        let defaultConfigContent = loadDefaultConfig()
        return updateUserConfig(defaultConfigContent)
    }
    
    // MARK: - 私有方法
    
    /// 获取用户配置文件URL（Documents目录）
    /// - Returns: 用户配置文件URL
    private func getConfigFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let userConfigURL = documentsPath.appendingPathComponent("config_local.json")
        os.Logger.settingsManager.debug("用户配置文件路径: \(userConfigURL.path)")
        return userConfigURL
    }
    
    func setupDefaultSettings() {
        if isFirstLaunch {
            // 设置默认值
            voiceSettings = VoiceSettings.default
            // 家长控制功能已移除
            supportedLanguages = AppConstants.Language.defaultLanguages
            currentLanguage = AppConstants.Language.defaultCurrent
            maxCacheSize = AppConstants.Cache.maxCacheSize
            autoCleanupEnabled = AppConstants.Cache.defaultAutoCleanupEnabled
            
            isFirstLaunch = false
        }
        
        // 更新启动计数
        appLaunchCount += 1
        lastLaunchDate = Date()
    }
    
    func validateAPIKey(_ key: String, completion: @escaping (Bool) -> Void) {
        os.Logger.settingsManager.info("开始验证API密钥, 密钥长度: \(key.count)")
        
        // 这里应该调用API验证密钥
        // 暂时简单验证格式
        let isValid = key.count >= AppConstants.API.minKeyLength && key.contains(AppConstants.API.keyPrefix)
        
        if isValid {
            os.Logger.settingsManager.info("API密钥验证通过")
        } else {
            os.Logger.settingsManager.warning("API密钥验证失败: 格式不正确")
        }
        
        completion(isValid)
    }
    
    func resetToDefaults() {
        // 重置所有设置到默认值
        voiceSettings = VoiceSettings.default
        // 家长控制功能已移除
        supportedLanguages = AppConstants.Language.defaultLanguages
        currentLanguage = AppConstants.Language.defaultCurrent
        maxCacheSize = AppConstants.Cache.maxCacheSize
        autoCleanupEnabled = AppConstants.Cache.defaultAutoCleanupEnabled
        
        // 清除API密钥
        apiKey = nil
        
        // 清除其他设置
        userDefaults.removeObject(forKey: AppConstants.UserDefaultsKeys.appLaunchCount)
        userDefaults.removeObject(forKey: AppConstants.UserDefaultsKeys.lastLaunchDate)
        
        // 重新设置默认值
        setupDefaultSettings()
    }
    
    func exportSettings() -> Data? {
        let settingsData = SettingsExportData(
            voiceSettings: voiceSettings,
            supportedLanguages: supportedLanguages,
            currentLanguage: currentLanguage,
            maxCacheSize: maxCacheSize,
            autoCleanupEnabled: autoCleanupEnabled
        )
        
        return try? JSONEncoder().encode(settingsData)
    }
    
    func importSettings(_ data: Data) -> Bool {
        guard let settingsData = try? JSONDecoder().decode(SettingsExportData.self, from: data) else {
            return false
        }
        
        // 应用导入的设置
        voiceSettings = settingsData.voiceSettings
        // 家长控制功能已移除
        supportedLanguages = settingsData.supportedLanguages
        currentLanguage = settingsData.currentLanguage
        maxCacheSize = settingsData.maxCacheSize
        autoCleanupEnabled = settingsData.autoCleanupEnabled
        
        return true
    }
    
    func clearAllData() {
        // 清除所有用户数据
        userDefaults.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        keychainRemoveAll()
        
        // 重新设置默认值
        setupDefaultSettings()
    }
    
    func getStorageInfo() -> StorageInfo {
        // 这里应该计算实际的存储使用情况
        // 暂时返回模拟数据
        return StorageInfo(
            totalSize: maxCacheSize,
            usedSize: 0,
            availableSize: maxCacheSize,
            imageCount: 0,
            audioCount: 0
        )
    }
}

// MARK: - 设置导出数据模型
struct SettingsExportData: Codable {
    let voiceSettings: VoiceSettings
    let supportedLanguages: [String]
    let currentLanguage: String
    let maxCacheSize: Int64
    let autoCleanupEnabled: Bool
    let exportDate: Date
    let appVersion: String
    
    init(voiceSettings: VoiceSettings, supportedLanguages: [String], currentLanguage: String, maxCacheSize: Int64, autoCleanupEnabled: Bool) {
        self.voiceSettings = voiceSettings
        self.supportedLanguages = supportedLanguages
        self.currentLanguage = currentLanguage
        self.maxCacheSize = maxCacheSize
        self.autoCleanupEnabled = autoCleanupEnabled
        self.exportDate = Date()
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

// MARK: - 存储信息模型
struct StorageInfo {
    let totalSize: Int64
    let usedSize: Int64
    let availableSize: Int64
    let imageCount: Int
    let audioCount: Int
    
    var usedPercentage: Double {
        guard totalSize > 0 else { return 0.0 }
        return Double(usedSize) / Double(totalSize)
    }
    
    var formattedTotalSize: String {
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
    
    var formattedUsedSize: String {
        return ByteCountFormatter.string(fromByteCount: usedSize, countStyle: .file)
    }
    
    var formattedAvailableSize: String {
        return ByteCountFormatter.string(fromByteCount: availableSize, countStyle: .file)
    }
}
