import Foundation
import UIKit
import ImageIO
import os.log

// MARK: - 会话记录管理器
/// 会话记录管理器，负责会话记录的存储、读取、删除等操作
/// 使用文件系统存储，每个会话记录存储为一个独立的文件夹
class SessionRecordManager {
    
    // MARK: - 单例
    static let shared = SessionRecordManager()
    
    // MARK: - 属性
    private let fileManager = FileManager.default
    private let logger = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "SessionRecordManager")
    
    /// 会话记录存储根目录
    private var sessionsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sessionsPath = documentsPath.appendingPathComponent("Sessions", isDirectory: true)
        
        ensureDocumentsDirectoryVisible(documentsPath)
        
        // 确保目录存在
        if !fileManager.fileExists(atPath: sessionsPath.path) {
            do {
                try fileManager.createDirectory(at: sessionsPath, withIntermediateDirectories: true)
                
                // 设置目录属性，确保"文件"应用可以访问
                var mutablePath = sessionsPath
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = false  // 不排除备份，确保文件可见
                try? mutablePath.setResourceValues(resourceValues)
                
                logger.info("✅ 创建会话记录目录: \(sessionsPath.path)")
            } catch {
                logger.error("❌ 创建会话记录目录失败: \(error.localizedDescription)")
            }
        } else {
            // 即使目录已存在，也确保权限正确
            var mutablePath = sessionsPath
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try? mutablePath.setResourceValues(resourceValues)
        }
        
        return sessionsPath
    }
    
    /// 确保Documents目录在"文件"应用中可见
    /// 通过创建一个README文件来触发系统索引，并帮助用户了解目录结构
    private func ensureDocumentsDirectoryVisible(_ documentsPath: URL) {
        // 创建一个README文件，说明如何访问Sessions目录
        let readmeURL = documentsPath.appendingPathComponent("README.txt")
        
        if !fileManager.fileExists(atPath: readmeURL.path) {
            do {
                let readmeContent = """
                PhotoTTS 文件存储说明
                ====================
                
                此目录包含PhotoTTS应用的所有数据文件。
                
                重要目录：
                - Sessions/: 会话记录目录
                  每个会话记录存储为一个独立的文件夹，包含：
                  * metadata.json: 会话元数据
                  * record.json: 会话完整数据
                  * images/: 图片文件夹
                  * audio.*: 音频文件
                
                如何访问：
                1. 打开"文件"应用
                2. 在"浏览"标签页中，找到"我的iPhone"
                3. 点击"PhotoTTS"应用
                4. 即可查看和管理所有会话记录文件
                
                注意：您可以直接在"文件"应用中查看、复制或删除这些文件。
                """
                try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
                
                // 设置文件属性
                var mutableReadme = readmeURL
                var resourceValues = URLResourceValues()
                resourceValues.isExcludedFromBackup = false
                try? mutableReadme.setResourceValues(resourceValues)
                
                logger.info("✅ 创建Documents目录README文件，确保在'文件'应用中可见")
            } catch {
                logger.warning("⚠️ 创建README文件失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 初始化
    private init() {
        logger.info("📁 会话记录管理器初始化，存储目录: \(self.sessionsDirectory.path)")
    }
    
    // MARK: - 保存会话记录
    
    /// 保存会话记录
    /// - Parameters:
    ///   - record: 会话记录
    /// - Returns: 保存结果，包含是否成功和存储大小（字节）
    func saveSession(_ record: SessionRecord) -> (success: Bool, size: Int64?) {
        let sessionDir = sessionsDirectory.appendingPathComponent(record.id, isDirectory: true)
        
        do {
            // 创建会话目录
            if !fileManager.fileExists(atPath: sessionDir.path) {
                try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            }
            
            // 保存元数据JSON文件
            let metadata = SessionRecordMetadata(from: record)
            let metadataData = try JSONEncoder().encode(metadata)
            let metadataURL = sessionDir.appendingPathComponent("metadata.json")
            try metadataData.write(to: metadataURL)
            
            // 保存完整记录JSON文件
            let recordData = try JSONEncoder().encode(record)
            let recordURL = sessionDir.appendingPathComponent("record.json")
            try recordData.write(to: recordURL)
            
            // 保存图片文件(先创建目录再保存每张图片)
            let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)
            if !fileManager.fileExists(atPath: imagesDir.path) {
                try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            }
            
            var mutableImagesDir = imagesDir
            var imagesDirResourceValues = URLResourceValues()
            imagesDirResourceValues.isExcludedFromBackup = false
            try? mutableImagesDir.setResourceValues(imagesDirResourceValues)
            
            // 逐张图片写入
            let saveMaxPixel = Int(Constants.ImageDisplay.saveImageMaxPixel)
            for (index, base64String) in record.imageDataList.enumerated() {
                guard let imageData = Data(base64Encoded: base64String),
                      let image = UIImage(data: imageData) else { continue }
                let imageToSave = Self.downsampleImageToMaxPixel(image, maxPixelLength: saveMaxPixel) ?? image
                guard let jpegData = imageToSave.jpegData(compressionQuality: 1.0) else { continue }
                let imageURL = imagesDir.appendingPathComponent("image_\(index).jpg")
                try jpegData.write(to: imageURL)
                var mutableImageURL = imageURL
                var imageResourceValues = URLResourceValues()
                imageResourceValues.isExcludedFromBackup = false
                try? mutableImageURL.setResourceValues(imageResourceValues)
            }
            
            // 保存音频文件
            if let audioData = record.getAudioData() {
                let audioURL = sessionDir.appendingPathComponent("audio.\(record.audioFormat)")
                try audioData.write(to: audioURL)
                
                // 设置音频文件属性
                var mutableAudioURL = audioURL
                var audioResourceValues = URLResourceValues()
                audioResourceValues.isExcludedFromBackup = false
                try? mutableAudioURL.setResourceValues(audioResourceValues)
            }
            
            // 预生成头像并写入 avatar.jpg
            if record.totalImageCount > 0 {
                let avatarIndex = min(max(0, record.avatarImageIndex), record.totalImageCount - 1)
                writeAvatarImage(sessionDir: sessionDir, imagesDir: imagesDir, avatarImageIndex: avatarIndex)
            }
            
            // 设置JSON文件属性
            var mutableMetadataURL = metadataURL
            var metadataResourceValues = URLResourceValues()
            metadataResourceValues.isExcludedFromBackup = false
            try? mutableMetadataURL.setResourceValues(metadataResourceValues)
            
            var mutableRecordURL = recordURL
            var recordResourceValues = URLResourceValues()
            recordResourceValues.isExcludedFromBackup = false
            try? mutableRecordURL.setResourceValues(recordResourceValues)
            
            // 设置会话目录属性，确保"文件"应用可以访问
            var mutableSessionDir = sessionDir
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false  // 不排除备份，确保文件可见
            try? mutableSessionDir.setResourceValues(resourceValues)
            
            // 创建README文件
            let readmeURL = sessionDir.appendingPathComponent("README.txt")
            let readmeContent = """
            会话记录目录说明
            ================
            
            此目录包含一个会话记录的完整数据：
            
            文件结构：
            - metadata.json: 会话记录的元数据（名称、时间、统计信息等）
            - record.json: 完整的会话记录数据（文本、音频信息等，图片数据已单独存储）
            - images/: 图片文件夹
              - image_0.jpg: 第一张图片
              - image_1.jpg: 第二张图片
              - ...
            - audio.mp3: 生成的音频文件
            
            您可以通过"文件"应用查看和管理这些文件。
            """
            try? readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
            
            // 设置README文件属性
            var mutableReadmeURL = readmeURL
            var readmeResourceValues = URLResourceValues()
            readmeResourceValues.isExcludedFromBackup = false
            try? mutableReadmeURL.setResourceValues(readmeResourceValues)
            
            // 计算存储大小
            let storageSize = calculateDirectorySize(sessionDir)
            let formattedSize = formatStorageSize(storageSize)
            let updatedMetadata = metadata.withStorageSize(storageSize)
            let updatedMetadataData = try JSONEncoder().encode(updatedMetadata)
            try updatedMetadataData.write(to: metadataURL)
            let updatedRecord = record.withStorageSize(storageSize)
            let updatedRecordData = try JSONEncoder().encode(updatedRecord)
            try updatedRecordData.write(to: recordURL)
            
            logger.info("✅ 会话记录保存成功: \(record.id), 名称: \(record.name)")
            logger.info("📁 会话记录路径: \(sessionDir.path)，可在'文件'应用中访问")
            logger.info("💾 存储空间: \(formattedSize) (\(storageSize) 字节)")
            
            return (true, storageSize)
            
        } catch {
            logger.error("❌ 保存会话记录失败: \(error.localizedDescription)")
            return (false, nil)
        }
    }
    
    /// 格式化存储大小（字节转换为可读格式）
    /// - Parameter bytes: 字节数
    /// - Returns: 格式化后的字符串
    private func formatStorageSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - 读取会话记录
    
    private static let didStripRecordAudioBase64Key = "PhotoTTS.DidStripRecordAudioBase64"
    
    /// 一次性修复存量 record.json：剔除 audioDataBase64 后写回，降低占用
    private func stripRecordAudioBase64IfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.didStripRecordAudioBase64Key) else { return }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            var fixedCount = 0
            
            for url in contents {
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else { continue }
                
                let recordURL = url.appendingPathComponent("record.json")
                guard fileManager.fileExists(atPath: recordURL.path),
                      let data = try? Data(contentsOf: recordURL),
                      let record = try? JSONDecoder().decode(SessionRecord.self, from: data) else { continue }
                
                let updatedData = try JSONEncoder().encode(record)
                try updatedData.write(to: recordURL)
                fixedCount += 1
            }
            
            if fixedCount > 0 {
                logger.info("✅ 存量 record.json 剔除 audioDataBase64 完成，共处理 \(fixedCount) 条")
            }
            UserDefaults.standard.set(true, forKey: Self.didStripRecordAudioBase64Key)
        } catch {
            logger.error("❌ 存量 record.json 剔除 audioDataBase64 失败: \(error.localizedDescription)")
        }
    }
    
    /// 获取所有会话记录的元数据列表（按时间倒序）
    /// - Returns: 会话记录元数据数组
    func getAllSessionMetadata() -> [SessionRecordMetadata] {
        stripRecordAudioBase64IfNeeded()
        var metadataList: [SessionRecordMetadata] = []
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [])
            
            for url in contents {
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else {
                    continue
                }
                
                let metadataURL = url.appendingPathComponent("metadata.json")
                if fileManager.fileExists(atPath: metadataURL.path) {
                    if let data = try? Data(contentsOf: metadataURL),
                       let metadata = try? JSONDecoder().decode(SessionRecordMetadata.self, from: data) {
                        metadataList.append(metadata)
                    }
                }
            }
            
            // 首先按名字倒序排序（Z-A），其次按创建时间倒序排序
            metadataList.sort { lhs, rhs in
                if lhs.name != rhs.name {
                    return lhs.name > rhs.name
                }
                return lhs.createdAt > rhs.createdAt
            }
            
            logger.info("📋 加载了 \(metadataList.count) 条会话记录元数据")
            
        } catch {
            logger.error("❌ 读取会话记录列表失败: \(error.localizedDescription)")
        }
        
        return metadataList
    }
    
    /// 根据ID加载完整的会话记录
    /// - Parameter id: 会话记录ID
    /// - Returns: 会话记录，如果不存在则返回nil
    func loadSession(id: String) -> SessionRecord? {
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        let recordURL = sessionDir.appendingPathComponent("record.json")
        
        guard fileManager.fileExists(atPath: recordURL.path) else {
            logger.warning("⚠️ 会话记录不存在: \(id)")
            return nil
        }
        
        do {
            let data = try Data(contentsOf: recordURL)
            let record = try JSONDecoder().decode(SessionRecord.self, from: data)
            
            // 加载音频
            let audioURL = sessionDir.appendingPathComponent("audio.\(record.audioFormat)")
            let audioData: Data = (try? Data(contentsOf: audioURL)) ?? record.getAudioData() ?? Data()

            // 不预加载图片，避免大会话占用内存被系统杀进程；播放/查看时按需通过 loadImage(sessionId:index:) 加载
            let resultRecord = SessionRecord(
                id: record.id,
                name: record.name,
                createdAt: record.createdAt,
                updatedAt: record.updatedAt,
                imageDataList: record.imageDataList,
                ocrText: record.ocrText,
                ocrTextSegments: record.ocrTextSegments,
                audioDataBase64: audioData.base64EncodedString(),
                audioFormat: record.audioFormat,
                audioDuration: record.audioDuration,
                ocrDuration: record.ocrDuration,
                ttsDuration: record.ttsDuration,
                validImageCount: record.validImageCount,
                totalImageCount: record.totalImageCount,
                textLength: record.textLength,
                audioSize: audioData.count,
                voiceSettings: record.voiceSettings,
                avatarImageIndex: record.avatarImageIndex,
                storageSize: record.storageSize
            )
            
            logger.info("✅ 加载会话记录成功: \(id)")
            return resultRecord
            
        } catch {
            logger.error("❌ 加载会话记录失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 仅从缓存读取图片，用于切换页时同步显示、避免闪动；未命中返回 nil。
    func loadImageIfCached(sessionId: String, index: Int, maxDimension: CGFloat? = nil) -> UIImage? {
        let cacheKey = "\(sessionId):\(index):\(maxDimension ?? -1)"
        return Self.imageLoadCache.object(forKey: cacheKey as NSString)
    }
    
    /// 后台预加载相邻图到缓存，切换时即可同步显示、避免闪动。已命中缓存则跳过。
    func preloadImage(sessionId: String, index: Int, maxDimension: CGFloat? = nil) {
        let cacheKey = "\(sessionId):\(index):\(maxDimension ?? -1)"
        if Self.imageLoadCache.object(forKey: cacheKey as NSString) != nil { return }
        let sid = sessionId
        let idx = index
        let maxD = maxDimension
        DispatchQueue.global(qos: .utility).async {
            _ = SessionRecordManager.shared.loadImage(sessionId: sid, index: idx, maxDimension: maxD)
        }
    }
    
    /// 按需加载单张图片，用于播放/查看时降低内存占用。可选缩小最大边长以进一步省内存。
    /// 使用 Image I/O 从文件直接生成缩略图，避免先解码全尺寸再缩小导致的内存突增。
    /// - Parameters:
    ///   - sessionId: 会话 ID
    ///   - index: 图片索引
    ///   - maxDimension: 最大边长（点），超过则等比缩小；nil 表示不缩小
    /// - Returns: 图片，不存在或失败返回 nil
    func loadImage(sessionId: String, index: Int, maxDimension: CGFloat? = nil) -> UIImage? {
        let cacheKey = "\(sessionId):\(index):\(maxDimension ?? -1)"
        if let cached = Self.imageLoadCache.object(forKey: cacheKey as NSString) {
            return cached
        }
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)
        let imageURL = imagesDir.appendingPathComponent("image_\(index).jpg")
        guard fileManager.fileExists(atPath: imageURL.path) else { return nil }
        let result: UIImage?
        if let maxD = maxDimension, maxD > 0 {
            result = Self.downsampleImageFromFile(url: imageURL, maxDimension: maxD)
        } else {
            result = Self.decodeImageFromFile(url: imageURL)
        }
        guard let img = result else { return nil }
        Self.imageLoadCache.setObject(img, forKey: cacheKey as NSString)
        return img
    }
    
    private static let imageLoadCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 6
        return c
    }()
    
    /// 使用 Image I/O 从文件直接生成缩略图，不生成全尺寸位图，避免内存突增。
    private static func downsampleImageFromFile(url: URL, maxDimension: CGFloat) -> UIImage? {
        let maxPixel = Int(maxDimension * max(1, UIScreen.main.scale))
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    
    /// 无缩放时从文件解码（仅当 maxDimension 为 nil 时使用，慎用大图）
    private static func decodeImageFromFile(url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
    
    /// 将内存中的大图缩放到最长边不超过 maxPixelLength（像素），用于保存记录或播放预加载时控制像素与内存。
    static func downsampleImageToMaxPixel(_ image: UIImage, maxPixelLength: Int) -> UIImage? {
        let w = Int(image.size.width * image.scale)
        let h = Int(image.size.height * image.scale)
        if max(w, h) <= maxPixelLength { return image }
        guard let data = image.jpegData(compressionQuality: 1.0) else { return image }
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelLength
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return image
        }
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - 记录头像
    private static let avatarFileName = "avatar.jpg"
    
    /// 从会话目录加载预生成的头像图
    func loadAvatar(sessionId: String) -> UIImage? {
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent(Self.avatarFileName)
        guard fileManager.fileExists(atPath: avatarURL.path),
              let data = try? Data(contentsOf: avatarURL),
              let img = UIImage(data: data) else {
            return nil
        }
        return img
    }
    
    /// 从指定索引的图片生成头像并写入会话目录 avatar.jpg
    private func writeAvatarImage(sessionDir: URL, imagesDir: URL, avatarImageIndex: Int) {
        let sourceURL = imagesDir.appendingPathComponent("image_\(avatarImageIndex).jpg")
        guard fileManager.fileExists(atPath: sourceURL.path) else { return }
        let maxDim = Constants.ImageDisplay.recordAvatarMaxDimension
        guard let img = Self.downsampleImageFromFile(url: sourceURL, maxDimension: maxDim),
              let jpegData = img.jpegData(compressionQuality: 0.85) else { return }
        let avatarURL = sessionDir.appendingPathComponent(Self.avatarFileName)
        do {
            try jpegData.write(to: avatarURL)
            var mutable = avatarURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = false
            try? mutable.setResourceValues(values)
        } catch {
            logger.error("❌ 写入头像失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 更新会话记录
    
    /// 更新会话记录（名称、头像等可选项，仅更新传入的非 nil 参数）
    /// - Parameters:
    ///   - id: 会话记录ID
    ///   - name: 新名称（nil 表示不修改）
    ///   - avatarImageIndex: 头像图片索引（nil 表示不修改）
    /// - Returns: 更新是否成功
    func updateSession(id: String, name: String? = nil, avatarImageIndex: Int? = nil) -> Bool {
        guard let record = loadSession(id: id) else {
            return false
        }
        
        let newName = name?.trimmingCharacters(in: .whitespaces) ?? record.name
        guard !newName.isEmpty else { return false }
        
        let newAvatarIndex: Int
        if let idx = avatarImageIndex {
            newAvatarIndex = min(max(0, idx), record.totalImageCount > 0 ? record.totalImageCount - 1 : 0)
        } else {
            newAvatarIndex = record.avatarImageIndex
        }
        
        let updatedRecord = SessionRecord(
            id: record.id,
            name: newName,
            createdAt: record.createdAt,
            updatedAt: Date(),
            imageDataList: record.imageDataList,
            ocrText: record.ocrText,
            ocrTextSegments: record.ocrTextSegments,
            audioDataBase64: record.getAudioData()?.base64EncodedString() ?? record.audioDataBase64,
            audioFormat: record.audioFormat,
            audioDuration: record.audioDuration,
            ocrDuration: record.ocrDuration,
            ttsDuration: record.ttsDuration,
            validImageCount: record.validImageCount,
            totalImageCount: record.totalImageCount,
            textLength: record.textLength,
            audioSize: record.audioSize,
            voiceSettings: record.voiceSettings,
            avatarImageIndex: newAvatarIndex,
            storageSize: record.storageSize
        )
        
        let result = saveSession(updatedRecord)
        return result.success
    }
    
    // MARK: - 删除会话记录
    
    /// 删除会话记录
    /// - Parameter id: 会话记录ID
    /// - Returns: 删除是否成功
    func deleteSession(id: String) -> Bool {
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        
        do {
            try fileManager.removeItem(at: sessionDir)
            logger.info("✅ 删除会话记录成功: \(id)")
            return true
        } catch {
            logger.error("❌ 删除会话记录失败: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 获取存储统计信息
    
    /// 获取所有会话记录的总大小（字节）
    /// - Returns: 总大小（字节）
    func getTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [])
            
            for url in contents {
                if let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) {
                    if resourceValues.isDirectory == true {
                        // 递归计算目录大小
                        totalSize += calculateDirectorySize(url)
                    } else if let fileSize = resourceValues.fileSize {
                        totalSize += Int64(fileSize)
                    }
                }
            }
        } catch {
            logger.error("❌ 计算存储大小失败: \(error.localizedDescription)")
        }
        
        return totalSize
    }
    
    /// 获取指定会话记录的存储大小
    /// - Parameter id: 会话记录ID
    /// - Returns: 存储大小（字节），如果不存在则返回nil
    func getSessionStorageSize(id: String) -> Int64? {
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: sessionDir.path) else {
            return nil
        }
        return calculateDirectorySize(sessionDir)
    }
    
    /// 递归计算目录大小
    private func calculateDirectorySize(_ url: URL) -> Int64 {
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    // MARK: - 修复目录权限
    
    /// 修复所有现有会话记录目录的权限，使它们可以通过"文件"应用访问
    /// - Returns: 修复的会话记录数量
    func fixExistingSessionPermissions() -> Int {
        var fixedCount = 0
        
        do {
            // 首先检查并修复Sessions根目录的权限
            var mutableSessionsDir = sessionsDirectory
            if let currentValues = try? mutableSessionsDir.resourceValues(forKeys: [.isExcludedFromBackupKey]) {
                // 如果权限不正确，才进行修复
                if currentValues.isExcludedFromBackup == true {
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = false
                    try? mutableSessionsDir.setResourceValues(resourceValues)
                }
            }
            
            // 获取所有会话记录目录
            let sessionDirs = try fileManager.contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isExcludedFromBackupKey],
                options: []
            ).filter { url in
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else {
                    return false
                }
                return true
            }
            
            // 为每个会话记录目录设置正确的权限
            for sessionDir in sessionDirs {
                // 先检查当前权限
                if let currentValues = try? sessionDir.resourceValues(forKeys: [.isExcludedFromBackupKey]),
                   currentValues.isExcludedFromBackup == false {
                    // 权限已经正确，跳过
                    continue
                }
                
                // 权限不正确，需要修复
                var mutableSessionDir = sessionDir
                var dirResourceValues = URLResourceValues()
                dirResourceValues.isExcludedFromBackup = false
                
                if (try? mutableSessionDir.setResourceValues(dirResourceValues)) != nil {
                    fixedCount += 1
                    logger.info("✅ 修复会话记录目录权限: \(sessionDir.lastPathComponent)")
                    
                    // 同时修复目录内所有文件和子目录的权限
                    fixSessionDirectoryPermissions(sessionDir)
                }
            }
            
            if fixedCount > 0 {
                logger.info("✅ 权限修复完成，共修复 \(fixedCount) 个会话记录目录")
            }
            
        } catch {
            logger.error("❌ 修复目录权限失败: \(error.localizedDescription)")
        }
        
        return fixedCount
    }
    
    /// 修复会话记录目录内所有文件和子目录的权限
    /// - Parameter sessionDir: 会话记录目录
    private func fixSessionDirectoryPermissions(_ sessionDir: URL) {
        guard let enumerator = fileManager.enumerator(
            at: sessionDir,
            includingPropertiesForKeys: [.isDirectoryKey, .isExcludedFromBackupKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        for case let url as URL in enumerator {
            // 先检查当前权限
            if let currentValues = try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]),
               currentValues.isExcludedFromBackup == false {
                // 权限已经正确，跳过
                continue
            }
            
            // 权限不正确，需要修复
            var mutableURL = url
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try? mutableURL.setResourceValues(resourceValues)
        }
    }
    
    // MARK: - 数据迁移
    
    /// 清理所有会话记录的 record.json 文件中的图片数据，减小文件大小
    /// 图片数据已单独保存为文件，不需要在JSON中重复存储
    /// - Returns: 清理的会话记录数量
    func cleanupImageDataFromRecords() -> Int {
        var cleanedCount = 0
        
        do {
            let sessionDirs = try fileManager.contentsOfDirectory(
                at: sessionsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ).filter { url in
                guard let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                      resourceValues.isDirectory == true else {
                    return false
                }
                return true
            }
            
            for sessionDir in sessionDirs {
                let recordURL = sessionDir.appendingPathComponent("record.json")
                
                guard fileManager.fileExists(atPath: recordURL.path) else {
                    continue
                }
                
                // 读取现有记录
                guard let data = try? Data(contentsOf: recordURL),
                      let record = try? JSONDecoder().decode(SessionRecord.self, from: data) else {
                    logger.warning("⚠️ 无法解析会话记录: \(sessionDir.lastPathComponent)")
                    continue
                }
                
                // 检查是否包含图片数据（如果 imageDataList 不为空，说明需要清理）
                if !record.imageDataList.isEmpty {
                    // 检查图片文件是否存在（如果存在，说明可以安全删除JSON中的图片数据）
                    let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)
                    let hasImageFiles = fileManager.fileExists(atPath: imagesDir.path)
                    
                    if hasImageFiles {
                        // 重新编码记录（会自动排除图片数据）
                        let cleanedData = try JSONEncoder().encode(record)
                        try cleanedData.write(to: recordURL)
                        
                        cleanedCount += 1
                        logger.info("✅ 清理会话记录图片数据: \(sessionDir.lastPathComponent)")
                    } else {
                        logger.warning("⚠️ 跳过清理（图片文件不存在）: \(sessionDir.lastPathComponent)")
                    }
                }
            }
            
            if cleanedCount > 0 {
                logger.info("✅ 图片数据清理完成，共清理 \(cleanedCount) 个会话记录")
            }
            
        } catch {
            logger.error("❌ 清理图片数据失败: \(error.localizedDescription)")
        }
        
        return cleanedCount
    }
    
    // MARK: - 清理临时文件
    
    /// 清理会话记录导出用的zip文件
    /// 在Documents目录和临时目录中查找并删除所有.zip文件
    /// - Returns: 清理的zip文件数量
    func cleanupZipFiles() -> Int {
        var cleanedCount = 0
        
        // 清理Documents目录下的zip文件
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        cleanedCount += cleanupZipFilesInDirectory(documentsPath)
        
        // 清理临时目录下的zip文件
        let tempPath = fileManager.temporaryDirectory
        cleanedCount += cleanupZipFilesInDirectory(tempPath)
        
        if cleanedCount > 0 {
            logger.info("✅ 清理zip文件完成，共清理 \(cleanedCount) 个文件")
        }
        
        return cleanedCount
    }
    
    /// 在指定目录中清理zip文件
    /// - Parameter directory: 要清理的目录
    /// - Returns: 清理的文件数量
    private func cleanupZipFilesInDirectory(_ directory: URL) -> Int {
        var cleanedCount = 0
        
        do {
            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isWritableKey],
                options: [.skipsHiddenFiles]
            )
            
            for url in contents {
                // 检查是否为zip文件
                if url.pathExtension.lowercased() == "zip" {
                    // 检查文件是否存在
                    guard fileManager.fileExists(atPath: url.path) else {
                        logger.debug("📝 zip文件不存在，跳过: \(url.lastPathComponent)")
                        continue
                    }
                    
                    // 尝试获取文件属性
                    var resourceValues: URLResourceValues?
                    do {
                        resourceValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isWritableKey])
                    } catch {
                        logger.warning("⚠️ 无法获取zip文件属性: \(url.lastPathComponent), 错误: \(error.localizedDescription)")
                    }
                    
                    // 检查文件大小（如果文件大小为0或异常，可能是损坏的文件）
                    if let size = resourceValues?.fileSize, size > 0 {
                        logger.debug("📦 发现zip文件: \(url.lastPathComponent), 大小: \(self.formatStorageSize(Int64(size)))")
                    }
                    
                    // 尝试删除文件
                    do {
                        // 先尝试检查文件是否可写（某些情况下文件可能被锁定）
                        if let isWritable = resourceValues?.isWritable, !isWritable {
                            logger.warning("⚠️ zip文件不可写，可能被锁定: \(url.lastPathComponent)")
                            // 即使不可写，也尝试删除（某些情况下仍然可以删除）
                        }
                        
                        try fileManager.removeItem(at: url)
                        cleanedCount += 1
                        logger.info("🗑️ 删除zip文件成功: \(url.lastPathComponent)")
                    } catch {
                        // 详细记录错误信息
                        let errorDescription = error.localizedDescription
                        let errorDomain = (error as NSError).domain
                        let errorCode = (error as NSError).code
                        
                        logger.warning("⚠️ 删除zip文件失败: \(url.lastPathComponent)")
                        logger.warning("   错误域: \(errorDomain), 错误码: \(errorCode)")
                        logger.warning("   错误描述: \(errorDescription)")
                        logger.warning("   文件路径: \(url.path)")
                        
                        // 如果是权限问题或文件被占用，记录更详细的信息
                        if errorCode == 513 || errorCode == 516 { // 权限错误
                            logger.warning("   可能原因: 文件权限不足或文件被系统锁定")
                        } else if errorCode == 260 { // 文件不存在（虽然我们已经检查过，但可能在检查后被删除）
                            logger.debug("   文件可能已被其他进程删除")
                        } else {
                            logger.warning("   可能原因: 文件正在被其他进程使用或系统限制")
                        }
                    }
                }
            }
        } catch {
            logger.warning("⚠️ 扫描目录失败: \(directory.path), 错误: \(error.localizedDescription)")
        }
        
        return cleanedCount
    }
    
    // MARK: - 导出会话记录
    
    /// 导出所有会话记录到指定目录
    /// 导出结构：
    ///   PhotoTTS_YYYYMMDD/
    ///     - export_manifest.json (导出清单，包含版本、导出时间、会话列表等)
    ///     - Sessions/ (所有会话记录目录)
    ///       - {session_id_1}/
    ///       - {session_id_2}/
    ///       - ...
    /// - Parameter destinationURL: 目标目录URL（用户选择的目录）
    /// - Returns: 导出结果
    func exportAllSessions(to destinationURL: URL) -> (success: Bool, sessionCount: Int, totalSize: Int64, errorMessage: String?) {
        // 注意：调用此方法前，调用方应该已经获取了destinationURL的安全作用域资源访问权限
        do {
            // 生成导出目录名称：PhotoTTS_20260211 形式
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            let dateStr = dateFormatter.string(from: Date())
            let exportDirName = "PhotoTTS_\(dateStr)"
            let exportDir = destinationURL.appendingPathComponent(exportDirName, isDirectory: true)
            
            // 创建导出目录
            try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
            
            // 获取所有会话记录
            let allMetadata = getAllSessionMetadata()
            var exportedCount = 0
            var totalSize: Int64 = 0
            var exportedSessions: [ExportSessionInfo] = []
            
            // 复制每个会话记录目录
            for metadata in allMetadata {
                let sourceSessionDir = sessionsDirectory.appendingPathComponent(metadata.id, isDirectory: true)
                let targetSessionDir = exportDir.appendingPathComponent("Sessions", isDirectory: true)
                    .appendingPathComponent(metadata.id, isDirectory: true)
                
                // 确保Sessions目录存在
                if !fileManager.fileExists(atPath: targetSessionDir.deletingLastPathComponent().path) {
                    try fileManager.createDirectory(at: targetSessionDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                }
                
                // 复制整个会话目录
                if fileManager.fileExists(atPath: sourceSessionDir.path) {
                    try fileManager.copyItem(at: sourceSessionDir, to: targetSessionDir)
                    
                    // 计算会话大小
                    let sessionSize = calculateDirectorySize(targetSessionDir)
                    totalSize += sessionSize
                    exportedCount += 1
                    
                    exportedSessions.append(ExportSessionInfo(
                        id: metadata.id,
                        name: metadata.name,
                        createdAt: metadata.createdAt,
                        size: sessionSize
                    ))
                    
                    logger.info("✅ 导出会话记录: \(metadata.name) (\(self.formatStorageSize(sessionSize)))")
                }
            }
            
            // 创建导出清单文件
            let manifest = ExportManifest(
                version: "1.0",
                exportDate: Date(),
                appName: "PhotoTTS",
                totalSessions: exportedCount,
                totalSize: totalSize,
                sessions: exportedSessions
            )
            
            let manifestData = try JSONEncoder().encode(manifest)
            let manifestURL = exportDir.appendingPathComponent("export_manifest.json")
            try manifestData.write(to: manifestURL)
            
            // 创建导出说明文件
            // 生成会话名称列表（按展示顺序排序）
            var sessionNameList = ""
            if !allMetadata.isEmpty {
                sessionNameList = "\n\n会话列表（按展示顺序）：\n"
                for (index, metadata) in allMetadata.enumerated() {
                    sessionNameList += "\(index + 1). \(metadata.name)\n"
                }
            }
            
            let readmeContent = """
            PhotoTTS 会话记录导出包
            ======================
            
            导出时间: \(manifest.formattedExportDate)
            会话数量: \(exportedCount) 个
            总大小: \(self.formatStorageSize(totalSize))\(sessionNameList)
            
            目录结构：
            - export_manifest.json: 导出清单（包含所有会话的元数据）
            - Sessions/: 会话记录目录
              - {session_id}/: 每个会话记录的完整数据
            
            导入说明：
            将来可以通过PhotoTTS应用的导入功能，选择此目录进行导入。
            导入时会自动解析 export_manifest.json 并恢复所有会话记录。
            
            版本: \(manifest.version)
            """
            let readmeURL = exportDir.appendingPathComponent("README.txt")
            try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
            
            // 设置导出目录属性
            var mutableExportDir = exportDir
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try? mutableExportDir.setResourceValues(resourceValues)
            
            logger.info("✅ 导出完成: \(exportedCount) 个会话记录，总大小: \(self.formatStorageSize(totalSize))")
            logger.info("📁 导出位置: \(exportDir.path)")
            
            return (true, exportedCount, totalSize, nil)
            
        } catch {
            logger.error("❌ 导出会话记录失败: \(error.localizedDescription)")
            return (false, 0, 0, error.localizedDescription)
        }
    }
    
    // MARK: - 导入会话记录
    
    /// 根据所选目录自动识别并导入：若为导出包(含 export_manifest.json) 则全量导入，若为单个会话目录(含 record.json) 则仅导入该条
    /// - Parameter sourceURL: 用户选择的目录（导出包根目录 或 单个会话目录）
    /// - Returns: 导入结果
    func importSessions(from sourceURL: URL) -> (success: Bool, importedCount: Int, skippedCount: Int, totalSize: Int64, errorMessage: String?) {
        let manifestURL = sourceURL.appendingPathComponent("export_manifest.json")
        let recordURL = sourceURL.appendingPathComponent("record.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return importAllSessions(from: sourceURL)
        }
        if fileManager.fileExists(atPath: recordURL.path) {
            return importOneSession(from: sourceURL)
        }
        return (false, 0, 0, 0, "请选择导出包目录(含 export_manifest.json) 或单个会话目录(含 record.json)")
    }
    
    /// 从导出包目录全量导入会话记录
    /// 导入结构：
    ///   PhotoTTS_YYYYMMDD/
    ///     - export_manifest.json (导出清单)
    ///     - Sessions/ (所有会话记录目录)
    ///       - {session_id_1}/
    ///       - {session_id_2}/
    ///       - ...
    /// - Parameter sourceURL: 源目录URL（用户选择的导出目录）
    /// - Returns: 导入结果
    func importAllSessions(from sourceURL: URL) -> (success: Bool, importedCount: Int, skippedCount: Int, totalSize: Int64, errorMessage: String?) {
        // 注意：调用此方法前，调用方应该已经获取了sourceURL的安全作用域资源访问权限
        do {
            // 检查是否存在export_manifest.json
            let manifestURL = sourceURL.appendingPathComponent("export_manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                return (false, 0, 0, 0, "未找到导出清单文件(export_manifest.json)，请确保选择了正确的导出目录")
            }
            
            // 解析导出清单
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
            
            logger.info("📦 开始导入会话记录，导出时间: \(manifest.formattedExportDate)，会话数量: \(manifest.totalSessions)")
            
            // 检查Sessions目录是否存在
            let sourceSessionsDir = sourceURL.appendingPathComponent("Sessions", isDirectory: true)
            guard fileManager.fileExists(atPath: sourceSessionsDir.path) else {
                return (false, 0, 0, 0, "未找到Sessions目录，导出包可能已损坏")
            }
            
            // 获取所有现有会话ID，用于检测冲突
            let existingMetadata = getAllSessionMetadata()
            let existingIDs = Set(existingMetadata.map { $0.id })
            
            var importedCount = 0
            var skippedCount = 0
            var totalSize: Int64 = 0
            
            // 导入每个会话记录
            for sessionInfo in manifest.sessions {
                let sourceSessionDir = sourceSessionsDir.appendingPathComponent(sessionInfo.id, isDirectory: true)
                
                // 检查源会话目录是否存在
                guard fileManager.fileExists(atPath: sourceSessionDir.path) else {
                    logger.warning("⚠️ 跳过会话记录（目录不存在）: \(sessionInfo.name) (ID: \(sessionInfo.id))")
                    skippedCount += 1
                    continue
                }
                
                // 检查ID是否已存在
                var targetSessionID = sessionInfo.id
                if existingIDs.contains(targetSessionID) {
                    // ID冲突，生成新ID
                    targetSessionID = UUID().uuidString
                    logger.info("⚠️ 会话ID冲突，生成新ID: \(sessionInfo.name) (原ID: \(sessionInfo.id) -> 新ID: \(targetSessionID))")
                }
                
                let targetSessionDir = sessionsDirectory.appendingPathComponent(targetSessionID, isDirectory: true)
                
                // 如果目标目录已存在，跳过
                if fileManager.fileExists(atPath: targetSessionDir.path) {
                    logger.warning("⚠️ 跳过会话记录（目标目录已存在）: \(sessionInfo.name) (ID: \(targetSessionID))")
                    skippedCount += 1
                    continue
                }
                
                // 复制会话目录
                do {
                    try fileManager.copyItem(at: sourceSessionDir, to: targetSessionDir)
                    
                    // 如果ID被修改，需要更新record.json和metadata.json中的ID
                    if targetSessionID != sessionInfo.id {
                        updateSessionID(in: targetSessionDir, newID: targetSessionID)
                    }
                    
                    // 设置目录和文件权限
                    var mutableSessionDir = targetSessionDir
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = false
                    try? mutableSessionDir.setResourceValues(resourceValues)
                    
                    // 修复目录内所有文件和子目录的权限
                    fixSessionDirectoryPermissions(targetSessionDir)
                    
                    // 计算导入的会话大小
                    let sessionSize = calculateDirectorySize(targetSessionDir)
                    totalSize += sessionSize
                    importedCount += 1
                    
                    logger.info("✅ 导入会话记录: \(sessionInfo.name) (\(self.formatStorageSize(sessionSize)))")
                    
                } catch {
                    logger.error("❌ 导入会话记录失败: \(sessionInfo.name), 错误: \(error.localizedDescription)")
                    skippedCount += 1
                }
            }
            
            if importedCount > 0 {
                logger.info("✅ 导入完成: 成功导入 \(importedCount) 个会话记录，跳过 \(skippedCount) 个，总大小: \(self.formatStorageSize(totalSize))")
            } else {
                logger.warning("⚠️ 导入完成: 没有成功导入任何会话记录，跳过 \(skippedCount) 个")
            }
            
            return (true, importedCount, skippedCount, totalSize, nil)
            
        } catch let error as DecodingError {
            let errorMessage = "解析导出清单失败: \(error.localizedDescription)"
            logger.error("❌ \(errorMessage)")
            return (false, 0, 0, 0, errorMessage)
        } catch {
            logger.error("❌ 导入会话记录失败: \(error.localizedDescription)")
            return (false, 0, 0, 0, error.localizedDescription)
        }
    }
    
    /// 导入单个会话记录（用户选择的目录须直接包含 record.json）
    /// - Parameter sourceURL: 单个会话目录的 URL（其下含 record.json、可选 audio.*、images/）
    /// - Returns: 导入结果
    func importOneSession(from sourceURL: URL) -> (success: Bool, importedCount: Int, skippedCount: Int, totalSize: Int64, errorMessage: String?) {
        let recordURL = sourceURL.appendingPathComponent("record.json")
        guard fileManager.fileExists(atPath: recordURL.path) else {
            return (false, 0, 0, 0, "该目录下未找到 record.json，请选择单个会话目录")
        }
        do {
            // 读取 record.json 获取原 ID（用于冲突检测与日志）
            let recordData = try Data(contentsOf: recordURL)
            let record = try JSONDecoder().decode(SessionRecord.self, from: recordData)
            let sourceID = record.id
            let sessionName = record.name
            
            let existingMetadata = getAllSessionMetadata()
            let existingIDs = Set(existingMetadata.map { $0.id })
            var targetSessionID = sourceID
            if existingIDs.contains(sourceID) {
                targetSessionID = UUID().uuidString
                logger.info("⚠️ 单条导入会话ID冲突，生成新ID: \(sessionName) (原ID: \(sourceID) -> 新ID: \(targetSessionID))")
            }
            
            let targetSessionDir = sessionsDirectory.appendingPathComponent(targetSessionID, isDirectory: true)
            if fileManager.fileExists(atPath: targetSessionDir.path) {
                return (true, 0, 1, 0, nil) // 目标已存在，视为跳过
            }
            
            try fileManager.copyItem(at: sourceURL, to: targetSessionDir)
            if targetSessionID != sourceID {
                updateSessionID(in: targetSessionDir, newID: targetSessionID)
            }
            var mutableSessionDir = targetSessionDir
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try? mutableSessionDir.setResourceValues(resourceValues)
            fixSessionDirectoryPermissions(targetSessionDir)
            let sessionSize = calculateDirectorySize(targetSessionDir)
            logger.info("✅ 导入单条会话记录: \(sessionName) (\(self.formatStorageSize(sessionSize)))")
            return (true, 1, 0, sessionSize, nil)
        } catch {
            logger.error("❌ 导入单条会话记录失败: \(error.localizedDescription)")
            return (false, 0, 0, 0, error.localizedDescription)
        }
    }
    
    /// 更新会话记录目录中的ID（当导入时ID冲突需要生成新ID时使用）
    /// - Parameters:
    ///   - sessionDir: 会话记录目录
    ///   - newID: 新ID
    private func updateSessionID(in sessionDir: URL, newID: String) {
        do {
            // 更新record.json - 直接修改JSON中的ID字段
            let recordURL = sessionDir.appendingPathComponent("record.json")
            if fileManager.fileExists(atPath: recordURL.path),
               let recordData = try? Data(contentsOf: recordURL),
               var recordDict = try? JSONSerialization.jsonObject(with: recordData) as? [String: Any] {
                // 更新ID字段
                recordDict["id"] = newID
                
                // 写回文件
                let updatedRecordData = try JSONSerialization.data(withJSONObject: recordDict)
                try updatedRecordData.write(to: recordURL)
            }
            
            // 更新metadata.json - 直接修改JSON中的ID字段
            let metadataURL = sessionDir.appendingPathComponent("metadata.json")
            if fileManager.fileExists(atPath: metadataURL.path),
               let metadataData = try? Data(contentsOf: metadataURL),
               var metadataDict = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any] {
                // 更新ID字段
                metadataDict["id"] = newID
                
                // 写回文件
                let updatedMetadataData = try JSONSerialization.data(withJSONObject: metadataDict)
                try updatedMetadataData.write(to: metadataURL)
            }
            
        } catch {
            logger.warning("⚠️ 更新会话ID失败: \(error.localizedDescription)")
        }
    }
}

// MARK: - 导出数据结构

/// 导出清单数据模型
struct ExportManifest: Codable {
    /// 导出格式版本
    let version: String
    /// 导出时间
    let exportDate: Date
    /// 应用名称
    let appName: String
    /// 会话总数
    let totalSessions: Int
    /// 总大小（字节）
    let totalSize: Int64
    /// 会话列表
    let sessions: [ExportSessionInfo]
    
    /// 格式化导出日期
    var formattedExportDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: exportDate)
    }
}

/// 导出会话信息
struct ExportSessionInfo: Codable {
    /// 会话ID
    let id: String
    /// 会话名称
    let name: String
    /// 创建时间
    let createdAt: Date
    /// 存储大小（字节）
    let size: Int64
}

