import XCTest
import Foundation
@testable import PhotoTTS

// MARK: - 集成测试（需要真实 API 配置，默认跳过）
/// 此测试调用真实 OCR/TTS API，需要 config_local.json 中配置有效密钥。
/// 每次运行会消耗 API 配额，不适合自动化 CI，仅用于手动验证。
/// 如需运行，注释掉 XCTSkip 行即可。
final class PhotoTTSIntegrationTests: XCTestCase {
    
    // MARK: - 测试配置
    
    private struct TestConfig {
        static let testImage1 = "real_test_image_1.jpg"
        static let testImage2 = "real_test_image_2.jpg"
        static let outputVoice = "real_test_voice_combined"
        static let configPath = "config_local.json"
    }
    
    private var config: [String: Any]?
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        config = loadConfiguration()
    }
    
    // MARK: - OCR + TTS 端到端测试
    
    func testOCRAndTTSPipeline() async throws {
        throw XCTSkip("集成测试需要真实 API 配置，默认跳过。如需运行请注释此行。")
        
        guard let config = config else {
            XCTFail("配置文件加载失败")
            return
        }
        
        // OCR: 识别测试图片
        var allTexts: [String] = []
        
        if let text1 = await performOCR(imageName: TestConfig.testImage1, config: config) {
            XCTAssertFalse(text1.isEmpty, "图片1 OCR 结果不应为空")
            allTexts.append(text1)
        }
        
        if let text2 = await performOCR(imageName: TestConfig.testImage2, config: config) {
            XCTAssertFalse(text2.isEmpty, "图片2 OCR 结果不应为空")
            allTexts.append(text2)
        }
        
        XCTAssertFalse(allTexts.isEmpty, "至少应有一张图片识别成功")
        
        // TTS: 合并文字后合成语音
        let combinedText = allTexts.joined(separator: "\n\n")
        let audioData = await performTTS(text: combinedText, config: config)
        
        XCTAssertNotNil(audioData, "TTS 合成应返回音频数据")
        if let data = audioData {
            XCTAssertGreaterThan(data.count, 0, "音频数据不应为空")
        }
    }
    
    // MARK: - 配置加载测试
    
    func testConfigurationLoading() throws {
        throw XCTSkip("集成测试需要真实 API 配置，默认跳过。如需运行请注释此行。")
        
        let config = loadConfiguration()
        XCTAssertNotNil(config, "应能加载配置文件")
        
        if let config = config {
            let ocr = config["ocr"] as? [String: Any]
            XCTAssertNotNil(ocr, "配置中应包含 OCR 配置")
            XCTAssertNotNil(ocr?["base_url"], "OCR 配置应包含 base_url")
            XCTAssertNotNil(ocr?["model_name"], "OCR 配置应包含 model_name")
            
            let tts = config["tts"] as? [String: Any]
            XCTAssertNotNil(tts, "配置中应包含 TTS 配置")
            XCTAssertNotNil(tts?["base_url"], "TTS 配置应包含 base_url")
            XCTAssertNotNil(tts?["appid"], "TTS 配置应包含 appid")
        }
    }
    
    // MARK: - 私有方法
    
    private func loadConfiguration() -> [String: Any]? {
        let possiblePaths = [
            "PhotoTTS/Resources/\(TestConfig.configPath)",
            "../PhotoTTS/Resources/\(TestConfig.configPath)",
            "../../PhotoTTS/Resources/\(TestConfig.configPath)",
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path),
               let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return dict
            }
        }
        return nil
    }
    
    private func performOCR(imageName: String, config: [String: Any]) async -> String? {
        let possiblePaths = [
            "PhotoTTSTests/FunctionalTests/\(imageName)",
            "../PhotoTTSTests/FunctionalTests/\(imageName)",
            "../../PhotoTTSTests/FunctionalTests/\(imageName)",
        ]
        
        var imageData: Data?
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                imageData = try? Data(contentsOf: URL(fileURLWithPath: path))
                break
            }
        }
        
        guard let data = imageData else { return nil }
        
        guard let ocr = config["ocr"] as? [String: Any],
              let baseURL = ocr["base_url"] as? String,
              let modelName = ocr["model_name"] as? String,
              let apiKey = ocr["api_key"] as? String else {
            return nil
        }
        
        let base64Image = data.base64EncodedString()
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "text", "text": "你是一个专业的OCR识别助手。请识别图片中的汉字；如果图片中有多页文字，请按照从左到右、自上而下的顺序合并在一起。要求：1.忽略拼音 2.请不要添加任何内容"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                ]
            ]],
            "max_tokens": 1000,
            "temperature": 0.1
        ]
        
        guard let url = URL(string: baseURL) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (responseData, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            
            guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                return nil
            }
            return content
        } catch {
            return nil
        }
    }
    
    private func performTTS(text: String, config: [String: Any]) async -> Data? {
        guard let tts = config["tts"] as? [String: Any],
              let baseURL = tts["base_url"] as? String,
              let appId = tts["appid"] as? String,
              let accessKey = tts["access_key"] as? String,
              let cluster = tts["cluster"] as? String,
              let voiceType = tts["voice_type"] as? String,
              let encoding = tts["encoding"] as? String,
              let speedRatio = tts["speed_ratio"] as? Double else {
            return nil
        }
        
        let requestBody: [String: Any] = [
            "app": ["appid": appId, "cluster": cluster, "token": "tts_token_\(Int(Date().timeIntervalSince1970))"],
            "user": ["uid": "test_\(Int(Date().timeIntervalSince1970))"],
            "request": ["reqid": UUID().uuidString, "operation": "query", "text": text],
            "audio": ["encoding": encoding, "voice_type": voiceType, "speed_ratio": speedRatio]
        ]
        
        guard let url = URL(string: baseURL) else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer; \(accessKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            
            // 直接音频响应
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
               contentType.contains("audio/") {
                return data
            }
            
            // JSON 响应中的 base64 音频
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let audioBase64 = json["audio"] as? String, let audioData = Data(base64Encoded: audioBase64) {
                    return audioData
                }
                if let audioBase64 = json["data"] as? String, let audioData = Data(base64Encoded: audioBase64) {
                    return audioData
                }
            }
            
            return data.isEmpty ? nil : data
        } catch {
            return nil
        }
    }
}
