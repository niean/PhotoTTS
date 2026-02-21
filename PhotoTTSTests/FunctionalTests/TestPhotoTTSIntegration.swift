#!/usr/bin/env swift

import Foundation
import CommonCrypto

// MARK: - 测试配置
struct TestConfig {
    static let testImage1 = "real_test_image_1.jpg"
    static let testImage2 = "real_test_image_2.jpg"
    static let outputVoice = "real_test_voice_combined"
    static let configPath = "PhotoTTS/Resources/config_dev.json"
}

// MARK: - 主测试类
class PhotoTTSTest {
    private var config: [String: Any]?
    
    init() {
        loadConfiguration()
    }
    
    // MARK: - 配置加载（使用正式代码的配置文件）
    private func loadConfiguration() {
        print("🔧 加载配置文件...")
        
        // 尝试多个可能的配置文件路径
        let possiblePaths = [
            TestConfig.configPath,
            "../\(TestConfig.configPath)",
            "../../\(TestConfig.configPath)",
            "../../../\(TestConfig.configPath)",
            "PhotoTTS/Resources/config_dev.json",
            "../PhotoTTS/Resources/config_dev.json",
            "../../PhotoTTS/Resources/config_dev.json"
        ]
        
        var configData: Data?
        var usedPath: String?
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                do {
                    configData = try Data(contentsOf: URL(fileURLWithPath: path))
                    usedPath = path
                    print("✅ 找到配置文件: \(path)")
                    break
                } catch {
                    print("⚠️ 读取配置文件失败: \(path) - \(error.localizedDescription)")
                }
            }
        }
        
        guard let data = configData else {
            print("❌ 找不到配置文件，尝试的路径:")
            for path in possiblePaths {
                print("   - \(path)")
            }
            return
        }
        
        do {
            let configDict = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            
            guard let config = configDict else {
                print("❌ 配置文件格式错误")
                return
            }
            
            self.config = config
            print("✅ 配置文件加载成功: \(usedPath ?? "未知路径")")
            
            // 打印配置信息
            if let ocr = config["ocr"] as? [String: Any] {
                print("📋 OCR配置:")
                print("   - Base URL: \(ocr["base_url"] as? String ?? "未设置")")
                print("   - Model: \(ocr["model_name"] as? String ?? "未设置")")
                print("   - API Key: \(ocr["api_key"] as? String ?? "未设置")")
            }
            
            if let tts = config["tts"] as? [String: Any] {
                print("📋 TTS配置:")
                print("   - Base URL: \(tts["base_url"] as? String ?? "未设置")")
                print("   - App ID: \(tts["appid"] as? String ?? "未设置")")
                print("   - Access Key: \(tts["access_key"] as? String ?? "未设置")")
                print("   - Secret Key: \(tts["secret_key"] as? String ?? "未设置")")
                print("   - Cluster: \(tts["cluster"] as? String ?? "未设置")")
                print("   - UID: \(tts["uid"] as? String ?? "未设置")")
                print("   - Voice Type: \(tts["voice_type"] as? String ?? "未设置")")
                print("   - Encoding: \(tts["encoding"] as? String ?? "未设置")")
            }
            
        } catch {
            print("❌ 配置文件解析失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 主测试流程
    func runIntegrationTest() async {
        print("\n🚀 开始Photo TTS集成测试...")
        print("📱 使用正式代码配置和逻辑进行测试")
        
        guard let config = config else {
            print("❌ 配置未加载，无法继续测试")
            return
        }
        
        // 第一步：处理所有图片的OCR
        print("\n📸 第一步：OCR文字识别")
        var allRecognizedTexts: [String] = []
        
        // 处理第一张图片
        print("\n   🔍 识别图片1: \(TestConfig.testImage1)")
        if let text1 = await performOCR(imageName: TestConfig.testImage1, config: config) {
            print("   ✅ 图片1识别成功")
            print("   📝 识别文字: \(text1)")
            allRecognizedTexts.append(text1)
        } else {
            print("   ❌ 图片1识别失败")
        }
        
        // 处理第二张图片
        print("\n   🔍 识别图片2: \(TestConfig.testImage2)")
        if let text2 = await performOCR(imageName: TestConfig.testImage2, config: config) {
            print("   ✅ 图片2识别成功")
            print("   📝 识别文字: \(text2)")
            allRecognizedTexts.append(text2)
        } else {
            print("   ❌ 图片2识别失败")
        }
        
        // 第二步：合并所有文字，做一次TTS
        if !allRecognizedTexts.isEmpty {
            print("\n🔊 第二步：TTS语音合成")
            let combinedText = allRecognizedTexts.joined(separator: "\n\n---\n\n")
            print("   📝 合并后的文字:")
            print("   \(combinedText)")
            
            if let audioData = await performTTS(text: combinedText, config: config) {
                print("   ✅ TTS合成成功")
                print("   📊 音频大小: \(audioData.count) 字节")
                
                // 保存音频文件
                if saveAudioFile(audioData: audioData, fileName: TestConfig.outputVoice, format: "mp3") {
                    print("   💾 音频文件保存成功")
                } else {
                    print("   ❌ 音频文件保存失败")
                }
            } else {
                print("   ❌ TTS合成失败")
            }
        } else {
            print("\n❌ 没有成功识别的文字，跳过TTS测试")
        }
        
        print("\n🎉 Photo TTS集成测试完成！")
    }
    
    // MARK: - OCR文字识别（使用正式代码的配置和逻辑）
    private func performOCR(imageName: String, config: [String: Any]) async -> String? {
        // 尝试多个可能的图片路径
        let possibleImagePaths = [
            imageName,
            "./\(imageName)",
            "../\(imageName)",
            "../../\(imageName)",
            "Tests/FunctionalTests/\(imageName)",
            "../Tests/FunctionalTests/\(imageName)",
            "../../Tests/FunctionalTests/\(imageName)"
        ]
        
        var imagePath: String?
        for path in possibleImagePaths {
            if FileManager.default.fileExists(atPath: path) {
                imagePath = path
                break
            }
        }
        
        guard let validImagePath = imagePath else {
            print("   ❌ 图片文件不存在，尝试的路径:")
            for path in possibleImagePaths {
                print("      - \(path)")
            }
            return nil
        }
        
        print("   📸 找到图片文件: \(validImagePath)")
        
        // 读取图片文件
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: validImagePath)) else {
            print("   ❌ 图片文件读取失败")
            return nil
        }
        
        print("   📸 图片大小: \(imageData.count) 字节")
        
        // 使用正式代码的OCR配置
        guard let ocr = config["ocr"] as? [String: Any],
              let ocrBaseURL = ocr["base_url"] as? String,
              let ocrModelName = ocr["model_name"] as? String,
              let ocrAPIKey = ocr["api_key"] as? String else {
            print("   ❌ OCR配置缺失")
            return nil
        }
        
        // 构建OCR请求（使用正式代码的格式）
        let base64Image = imageData.base64EncodedString()
        let ocrRequest = [
            "model": ocrModelName,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": "你是一个专业的OCR识别助手。请识别图片中的汉字；如果图片中有多页文字，请按照从左到右、自上而下的顺序合并在一起。要求：1.忽略拼音 2.请不要添加任何内容"
                        ],
                        [
                            "type": "image_url",
                            "image_url": [
                                "url": "data:image/jpeg;base64,\(base64Image)"
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 1000,
            "temperature": 0.1
        ] as [String: Any]
        
        // 发送OCR请求
        guard let url = URL(string: ocrBaseURL) else {
            print("   ❌ OCR URL无效")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(ocrAPIKey)", forHTTPHeaderField: "Authorization")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: ocrRequest)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("   📡 OCR响应状态: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode == 200 {
                    // 解析豆包OCR API的实际响应格式
                    guard let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = jsonData["choices"] as? [[String: Any]],
                          let firstChoice = choices.first,
                          let message = firstChoice["message"] as? [String: Any],
                          let content = message["content"] as? String else {
                        print("   ❌ OCR响应数据格式错误")
                        return nil
                    }
                    return content
                } else {
                    print("   ❌ OCR HTTP错误: \(httpResponse.statusCode)")
                    if let errorText = String(data: data, encoding: .utf8) {
                        print("   📝 错误详情: \(errorText)")
                    }
                }
            }
        } catch {
            print("   ❌ OCR请求失败: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - TTS语音合成（使用正式代码的配置和逻辑）
    private func performTTS(text: String, config: [String: Any]) async -> Data? {
        print("   🎵 开始TTS转换...")
        
        // 使用正式代码的TTS配置
        guard let tts = config["tts"] as? [String: Any],
              let ttsBaseURL = tts["base_url"] as? String,
              let ttsAppId = tts["appid"] as? String,
              let ttsAccessKey = tts["access_key"] as? String,
              let ttsSecretKey = tts["secret_key"] as? String,
              let ttsCluster = tts["cluster"] as? String,
              let ttsUid = tts["uid"] as? String,
              let ttsVoiceType = tts["voice_type"] as? String,
              let ttsEncoding = tts["encoding"] as? String,
              let ttsSpeedRatio = tts["speed_ratio"] as? Double else {
            print("   ❌ TTS配置缺失")
            return nil
        }
        
        // 准备豆包TTS请求（使用正式代码的格式）
        let doubaoParams: [String: Any] = [
            "app": [
                "appid": ttsAppId,
                "cluster": ttsCluster,
                "token": "tts_token_\(Int(Date().timeIntervalSince1970))"
            ],
            "user": [
                "uid": "user_\(Int(Date().timeIntervalSince1970))"
            ],
            "request": [
                "reqid": UUID().uuidString,
                "operation": "query",
                "text": text
            ],
            "audio": [
                "encoding": ttsEncoding,
                "voice_type": ttsVoiceType,
                "speed_ratio": ttsSpeedRatio
            ]
        ]
        
        // 发送TTS请求
        guard let url = URL(string: ttsBaseURL) else {
            print("   ❌ TTS URL无效")
            return nil
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // 添加Authorization头（Bearer Token认证）
        let bearerToken = "Bearer; \(ttsAccessKey)"
        request.setValue(bearerToken, forHTTPHeaderField: "Authorization")
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: doubaoParams)
            request.httpBody = jsonData
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("   ❌ 无效的HTTP响应")
                return nil
            }
            
            print("   📡 TTS响应状态: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "未知错误"
                print("   ❌ TTS HTTP错误: \(httpResponse.statusCode)")
                print("   📝 错误详情: \(errorMessage)")
                return nil
            }
            
            // 检查响应内容类型
            if let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
                print("   📥 收到TTS响应，Content-Type: \(contentType)")
                
                if contentType.contains("audio/") {
                    // 直接返回音频数据
                    print("   ✅ 收到音频数据，大小: \(data.count) 字节")
                    return data
                }
            }
            
            // 尝试解析JSON响应
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("   📥 收到豆包TTS API响应:")
                
                // 检查是否有音频数据（Base64编码）
                if let audioBase64 = json["audio"] as? String,
                   let audioData = Data(base64Encoded: audioBase64) {
                    print("   ✅ 成功解析Base64音频数据，大小: \(audioData.count) 字节")
                    return audioData
                }
                
                // 检查是否有data字段包含音频
                if let audioBase64 = json["data"] as? String,
                   let audioData = Data(base64Encoded: audioBase64) {
                    print("   ✅ 成功解析data字段中的音频数据，大小: \(audioData.count) 字节")
                    return audioData
                }
                
                // 检查是否有result字段
                if let result = json["result"] as? [String: Any],
                   let audioBase64 = result["audio"] as? String,
                   let audioData = Data(base64Encoded: audioBase64) {
                    print("   ✅ 成功解析result中的音频数据，大小: \(audioData.count) 字节")
                    return audioData
                }
                
                print("   ❌ 未找到音频数据字段")
                return nil
            } else {
                // 如果不是JSON，检查是否是直接的音频数据
                if data.count > 0 {
                    print("   ✅ 收到二进制数据，可能是音频文件，大小: \(data.count) 字节")
                    return data
                }
                
                print("   ❌ 响应数据为空或无法解析")
                return nil
            }
            
        } catch {
            print("   ❌ TTS请求失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - 保存音频文件
    private func saveAudioFile(audioData: Data, fileName: String, format: String) -> Bool {
        // 尝试多个可能的保存路径
        let possiblePaths = [
            "\(fileName).\(format)",  // 当前目录
            "./\(fileName).\(format)",  // 当前目录（明确）
            "../\(fileName).\(format)",  // 上级目录
            "../../\(fileName).\(format)",  // 上两级目录
            "PhotoTTSTests/FunctionalTests/\(fileName).\(format)",  // 相对路径
            "../PhotoTTSTests/FunctionalTests/\(fileName).\(format)",  // 相对路径
            "../../PhotoTTSTests/FunctionalTests/\(fileName).\(format)"  // 相对路径
        ]
        
        var savedPath: String?
        
        for path in possiblePaths {
            do {
                try audioData.write(to: URL(fileURLWithPath: path))
                savedPath = path
                print("   💾 音频文件保存到: \(path)")
                break
            } catch {
                print("   ⚠️ 尝试保存到 \(path) 失败: \(error.localizedDescription)")
            }
        }
        
        if savedPath != nil {
            return true
        } else {
            print("   ❌ 所有保存路径都失败")
            return false
        }
    }
}

// MARK: - 主程序入口
print("🎯 Photo TTS 集成功能测试")
print("📱 使用正式代码配置和逻辑进行测试")
print(String(repeating: "=", count: 50))

let test = PhotoTTSTest()
await test.runIntegrationTest()

print("\n" + String(repeating: "=", count: 50))
print("🏁 测试完成") 
