import XCTest
import Foundation

// MARK: - 阿里千问TTS功能测试（真实API调用）
/// 此测试直接调用 DashScope Qwen3-TTS-Flash API，用于调试请求格式。
/// 需要 config_local.json 中配置有效的 aliqwen secret_key。
/// 每次运行会消耗 API 配额，不适合自动化 CI，仅用于手动验证。
/// 官方文档: https://help.aliyun.com/zh/model-studio/qwen-tts-api
final class AliqwenTTSTests: XCTestCase {

    // MARK: - 测试配置

    private struct TestConfig {
        static let configPath = "config_local.json"
        static let testText = "从前有一只小白兔，住在森林里的蘑菇屋。"
        static let shortText = "你好"
    }

    private var aliqwenConfig: [String: Any]?
    private var secretKey: String?
    private var baseURL: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        // [SKIP] 功能测试需要真实 API 配置，setUp 中不加断言，避免 XCTSkip 前失败
        // 配置检查延迟到各测试方法内执行
        let config = loadConfiguration()
        let tts = config?["tts"] as? [String: Any]
        aliqwenConfig = tts?["aliqwen"] as? [String: Any]
        secretKey = aliqwenConfig?["secret_key"] as? String
        baseURL = aliqwenConfig?["base_url"] as? String
            ?? "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"
    }

    // MARK: - 测试1: 最小请求体（扁平input格式）

    func testMinimalRequest() async throws {
        throw XCTSkip("功能测试需要真实 API 配置，默认跳过。如需运行请注释此行。")

        let requestBody: [String: Any] = [
            "model": aliqwenConfig?["model"] as? String ?? "qwen3-tts-flash",
            "input": [
                "text": TestConfig.shortText,
                "voice": aliqwenConfig?["voice"] as? String ?? "Cherry",
                "language_type": "Chinese"
            ]
        ]

        let result = try await callDashScopeAPI(requestBody: requestBody, label: "最小请求体")
        XCTAssertNil(result.errorCode, "不应返回错误: \(result.errorCode ?? "")")
        XCTAssertNotNil(result.audioData, "应返回音频数据")
        XCTAssertGreaterThan(result.audioData?.count ?? 0, 100, "音频数据应有合理大小")
        print("[testMinimalRequest] 音频大小: \(result.audioData?.count ?? 0) 字节")
    }

    // MARK: - 测试2: 完整配置（模拟正式代码请求格式）

    func testFullConfigRequest() async throws {
        throw XCTSkip("功能测试需要真实 API 配置，默认跳过。如需运行请注释此行。")

        guard let cfg = aliqwenConfig else {
            XCTFail("aliqwen 配置缺失")
            return
        }

        let requestBody: [String: Any] = [
            "model": cfg["model"] as? String ?? "qwen3-tts-flash",
            "input": [
                "text": TestConfig.testText,
                "voice": cfg["voice"] as? String ?? "Cherry",
                "language_type": cfg["language_type"] as? String ?? "Chinese"
            ]
        ]

        let result = try await callDashScopeAPI(requestBody: requestBody, label: "完整配置")
        XCTAssertNil(result.errorCode, "不应返回错误: \(result.errorCode ?? ""): \(result.errorMessage ?? "")")
        XCTAssertNotNil(result.audioData, "应返回音频数据")
        XCTAssertGreaterThan(result.audioData?.count ?? 0, 1000, "音频数据应有合理大小(>1KB)")
        print("[testFullConfigRequest] 音频大小: \(result.audioData?.count ?? 0) 字节")
    }

    // MARK: - API调用辅助

    private struct APIResult {
        var audioData: Data?
        var duration: Double?
        var errorCode: String?
        var errorMessage: String?
        var httpStatus: Int?
    }

    private func callDashScopeAPI(requestBody: [String: Any], label: String) async throws -> APIResult {
        guard let secretKey = secretKey, !secretKey.isEmpty else {
            XCTFail("secret_key 未配置")
            return APIResult(errorCode: "NO_KEY", errorMessage: "secret_key 未配置")
        }

        guard let url = URL(string: baseURL ?? "") else {
            XCTFail("base_url 无效")
            return APIResult(errorCode: "INVALID_URL", errorMessage: "base_url 无效")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(secretKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 120

        let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [.sortedKeys, .prettyPrinted])
        request.httpBody = jsonData

        if let bodyString = String(data: jsonData, encoding: .utf8) {
            print("[\(label)] 请求body:\n\(bodyString)")
        }

        print("[\(label)] 发送请求到: \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            return APIResult(errorCode: "NO_HTTP_RESPONSE", errorMessage: "非HTTP响应")
        }

        print("[\(label)] HTTP状态: \(httpResponse.statusCode)")

        if httpResponse.statusCode != 200 {
            let raw = String(data: data, encoding: .utf8) ?? ""
            print("[\(label)] 错误响应: \(raw)")
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return APIResult(
                    errorCode: json["code"] as? String ?? "HTTP_\(httpResponse.statusCode)",
                    errorMessage: json["message"] as? String ?? raw,
                    httpStatus: httpResponse.statusCode
                )
            }
            return APIResult(errorCode: "HTTP_\(httpResponse.statusCode)", errorMessage: raw, httpStatus: httpResponse.statusCode)
        }

        // 解析JSON响应
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return APIResult(errorCode: "INVALID_JSON", errorMessage: "响应不是有效JSON")
        }

        // 检查API错误
        if let code = json["code"] as? String, !code.isEmpty {
            return APIResult(errorCode: code, errorMessage: json["message"] as? String, httpStatus: httpResponse.statusCode)
        }

        // 打印响应结构（不含音频数据）
        var debugJson = json
        if var output = debugJson["output"] as? [String: Any],
           var audio = output["audio"] as? [String: Any] {
            if let urlStr = audio["url"] as? String {
                audio["url"] = String(urlStr.prefix(60)) + "...(truncated)"
            }
            output["audio"] = audio
            debugJson["output"] = output
        }
        if let debugData = try? JSONSerialization.data(withJSONObject: debugJson, options: .prettyPrinted),
           let debugStr = String(data: debugData, encoding: .utf8) {
            print("[\(label)] 响应结构:\n\(debugStr)")
        }

        // 从 output.audio.url 下载音频（http -> https 以符合ATS）
        if let output = json["output"] as? [String: Any],
           let audio = output["audio"] as? [String: Any],
           let audioURLString = audio["url"] as? String, !audioURLString.isEmpty {
            let secureURL = audioURLString.hasPrefix("http://")
                ? "https://" + audioURLString.dropFirst(7)
                : audioURLString
            guard let audioURL = URL(string: secureURL) else {
                return APIResult(errorCode: "INVALID_URL", errorMessage: "音频URL无效")
            }

            print("[\(label)] 下载音频: \(secureURL.prefix(60))...")
            let (audioData, audioResponse) = try await URLSession.shared.data(from: audioURL)
            let audioHTTP = audioResponse as? HTTPURLResponse
            print("[\(label)] 音频下载完成: HTTP \(audioHTTP?.statusCode ?? -1), 大小: \(audioData.count) 字节")

            guard audioHTTP?.statusCode == 200, !audioData.isEmpty else {
                return APIResult(errorCode: "DOWNLOAD_FAILED", errorMessage: "音频下载失败: HTTP \(audioHTTP?.statusCode ?? -1)")
            }

            let characters = (json["usage"] as? [String: Any])?["characters"] as? Int
            print("[\(label)] 成功, 字符数: \(characters ?? 0), 音频大小: \(audioData.count) 字节")

            return APIResult(audioData: audioData, httpStatus: httpResponse.statusCode)
        }

        return APIResult(errorCode: "NO_AUDIO_URL", errorMessage: "响应中未找到 output.audio.url")
    }

    // MARK: - 配置加载

    private func loadConfiguration() -> [String: Any]? {
        // 通过 #filePath 定位项目根目录（当前文件在 PhotoTTSTests/FunctionalTests/ 下）
        let thisFile = URL(fileURLWithPath: #filePath)
        let projectRoot = thisFile
            .deletingLastPathComponent() // FunctionalTests/
            .deletingLastPathComponent() // PhotoTTSTests/
            .deletingLastPathComponent() // project root
        let configURL = projectRoot
            .appendingPathComponent("PhotoTTS")
            .appendingPathComponent("Resources")
            .appendingPathComponent(TestConfig.configPath)

        guard FileManager.default.fileExists(atPath: configURL.path),
              let data = try? Data(contentsOf: configURL),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("配置文件加载失败: \(configURL.path)")
            return nil
        }

        print("配置文件加载成功: \(configURL.path)")
        return dict
    }
}
