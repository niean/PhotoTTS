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
    private let logger = os.Logger.sessionRecord

    // 元数据短时效缓存：避免 Siri 实体查询等场景短时间内多次磁盘扫描
    private var metadataCache: [SessionRecordMetadata]?
    private var metadataCacheTime: Date = .distantPast
    private static let metadataCacheTTL: TimeInterval = 2 // 缓存有效期 2 秒
    
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
                
                logger.info("创建会话记录目录: \(sessionsPath.path)")
            } catch {
                logger.error("创建会话记录目录失败: \(error.localizedDescription)")
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
                
                logger.info("创建Documents目录README文件，确保在'文件'应用中可见")
            } catch {
                logger.warning("创建README文件失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 初始化
    private init() {
        logger.info("会话记录管理器初始化，存储目录: \(self.sessionsDirectory.path)")
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
            - audio.<格式>: 生成的音频文件（mp3或wav，取决于TTS供应商）
            
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
            
            invalidateMetadataCache()
            logger.info("会话记录保存成功: \(record.name)")
            logger.info("会话记录路径: \(sessionDir.path)，可在'文件'应用中访问")
            logger.info("存储空间: \(formattedSize) (\(storageSize) 字节)")
            
            return (true, storageSize)
            
        } catch {
            logger.error("保存会话记录失败: \(error.localizedDescription)")
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
    
    /// 获取所有会话记录的元数据列表（按时间倒序）
    /// - Returns: 会话记录元数据数组
    /// 清除元数据缓存（会话增删改后调用）
    private func invalidateMetadataCache() {
        metadataCache = nil
    }

    func getAllSessionMetadata(caller: String = "") -> [SessionRecordMetadata] {
        // 短时效缓存命中则直接返回，避免 Siri 实体查询等场景重复磁盘扫描
        if let cached = metadataCache,
           Date().timeIntervalSince(metadataCacheTime) < Self.metadataCacheTTL {
            return cached
        }

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
            
            let callerTag = caller.isEmpty ? "" : " (caller=\(caller))"
            logger.info("加载了 \(metadataList.count) 条会话记录元数据\(callerTag)")
            
        } catch {
            logger.error("读取会话记录列表失败: \(error.localizedDescription)")
        }
        
        // 用户无记录时，展示内置默认会话
        if metadataList.isEmpty, let bundledMetadata = loadBundledDefaultSessionMetadata() {
            metadataList.append(bundledMetadata)
            logger.info("用户无记录，展示内置默认会话")
        }
        
        // 写入短时效缓存
        metadataCache = metadataList
        metadataCacheTime = Date()
        
        return metadataList
    }
    
    /// 分页查询会话记录元数据（支持搜索过滤）
    /// - Parameters:
    ///   - page: 页码（从 1 开始）
    ///   - pageSize: 每页条数
    ///   - searchKeyword: 搜索关键词（按名称模糊匹配，空字符串表示不过滤）
    ///   - caller: 调用方标识，用于日志
    /// - Returns: 当前页的元数据列表 + 匹配总数
    func getSessionMetadataPage(page: Int, pageSize: Int, searchKeyword: String = "", caller: String = "") -> (items: [SessionRecordMetadata], totalCount: Int) {
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
        } catch {
            logger.error("分页读取会话记录列表失败: \(error.localizedDescription)")
            return ([], 0)
        }
        
        // 用户无记录时，展示内置默认会话
        if metadataList.isEmpty, let bundledMetadata = loadBundledDefaultSessionMetadata() {
            metadataList.append(bundledMetadata)
        }
        
        // 按搜索关键词过滤
        let trimmed = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            metadataList = metadataList.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        }
        
        // 按名字倒序排序（Z-A），其次按创建时间倒序排序（与 getAllSessionMetadata 一致）
        metadataList.sort { lhs, rhs in
            if lhs.name != rhs.name {
                return lhs.name > rhs.name
            }
            return lhs.createdAt > rhs.createdAt
        }
        
        let totalCount = metadataList.count
        
        // 计算分页切片
        let safePage = max(1, page)
        let startIndex = (safePage - 1) * pageSize
        guard startIndex < totalCount else {
            return ([], totalCount)
        }
        let endIndex = min(startIndex + pageSize, totalCount)
        let pageItems = Array(metadataList[startIndex..<endIndex])
        
        return (pageItems, totalCount)
    }
    
    /// 根据ID加载完整的会话记录
    /// - Parameter id: 会话记录ID
    /// - Returns: 会话记录，如果不存在则返回nil
    func loadSession(id: String) -> SessionRecord? {
        // 内置默认会话从 Bundle 加载
        if isBundledDefaultSession(id) {
            return loadBundledDefaultSession()
        }
        
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        let recordURL = sessionDir.appendingPathComponent("record.json")
        
        guard fileManager.fileExists(atPath: recordURL.path) else {
            logger.warning("会话记录不存在，ID: \(id)")
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
                storageSize: record.storageSize,
                makeStatus: record.makeStatus,
                storyHighlights: record.storyHighlights,
                hasVirtualPage: record.hasVirtualPage,
                animationStyle: record.animationStyle
            )
            
            logger.info("加载会话记录成功: \(record.name)")
            return resultRecord
            
        } catch {
            logger.error("加载会话记录失败: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// 仅从缓存读取图片，用于切换页时同步显示、避免闪动；未命中返回 nil。
    func loadImageIfCached(sessionId: String, index: Int, maxDimension: CGFloat? = nil) -> UIImage? {
        let cacheKey = "\(sessionId):\(index):\(maxDimension ?? -1)"
        return Self.imageLoadCache.object(forKey: cacheKey as NSString)
    }

    /// 后台预加载相邻图到缓存，切换时即可同步显示、避免闪动。已命中缓存则跳过。
    func preloadImage(sessionId: String, index: Int, maxDimension: CGFloat? = Constants.ImageDisplay.playbackFullScreenMaxDimension) {
        let effectiveMaxD = (maxDimension ?? 0) > 0 ? maxDimension! : Constants.ImageDisplay.playbackFullScreenMaxDimension
        let cacheKey = "\(sessionId):\(index):\(effectiveMaxD)"
        if Self.imageLoadCache.object(forKey: cacheKey as NSString) != nil { return }
        let sid = sessionId
        let idx = index
        DispatchQueue.global(qos: .utility).async {
            _ = SessionRecordManager.shared.loadImage(sessionId: sid, index: idx, maxDimension: effectiveMaxD)
        }
    }
    
    /// 按需加载单张图片，用于播放/查看时降低内存占用。可选缩小最大边长以进一步省内存。
    /// 使用 Image I/O 从文件直接生成缩略图，避免先解码全尺寸再缩小导致的内存突增。
    /// - Parameters:
    ///   - sessionId: 会话 ID
    ///   - index: 图片索引
    ///   - maxDimension: 最大边长（点），超过则等比缩小；默认 1024pt 保护内存
    /// - Returns: 图片，不存在或失败返回 nil
    func loadImage(sessionId: String, index: Int, maxDimension: CGFloat? = Constants.ImageDisplay.playbackFullScreenMaxDimension) -> UIImage? {
        return loadImageImpl(sessionId: sessionId, index: index, maxDimension: maxDimension)
    }

    /// 播放专用：按需加载单张图片，支持要点图片页处理。
    /// 当索引超出真实图片数量时，自动复用最后一张图片（要点图片页机制）。
    /// - Parameters:
    ///   - sessionId: 会话 ID
    ///   - index: 图片索引（要点图片页时会自动映射到最后一张真实图片）
    ///   - maxDimension: 最大边长（点），超过则等比缩小；默认 1024pt 保护内存
    ///   - totalImageCount: 真实图片总数，用于判断要点图片页
    /// - Returns: 图片，不存在或失败返回 nil
    func loadImageForPlayback(sessionId: String, index: Int, maxDimension: CGFloat? = Constants.ImageDisplay.playbackFullScreenMaxDimension, totalImageCount: Int) -> UIImage? {
        // 要点图片页处理：当索引超出范围时，复用最后一张图片
        let effectiveIndex = index < totalImageCount ? index : max(0, totalImageCount - 1)
        return loadImageImpl(sessionId: sessionId, index: effectiveIndex, maxDimension: maxDimension)
    }

    /// 从 Bundle 加载要点图片（EndPicts），根据动画方向从对应目录随机选取
    /// - Parameters:
    ///   - animationStyle: 动画方向（横向/纵向）
    ///   - maxDimension: 最大边长（点），超过则等比缩小
    /// - Returns: 图片，加载失败返回 nil
    func loadEndPictFromBundle(animationStyle: AnimationStyle, maxDimension: CGFloat) -> UIImage? {
        // 根据动画方向确定目录和图片数量
        let directoryName: String
        let imageCount: Int
        switch animationStyle {
        case .rightToLeft:
            directoryName = Constants.EndPicts.horizontalDirectoryName
            imageCount = Constants.EndPicts.horizontalImageCount
        case .topToBottom:
            directoryName = Constants.EndPicts.verticalDirectoryName
            imageCount = Constants.EndPicts.verticalImageCount
        }

        // 随机选取一张（索引从 1 开始，匹配文件名 h-1, h-2... 或 z-1, z-2...）
        let randomIndex = Int.random(in: 1...imageCount)
        // 资源文件被扁平化复制到 Bundle 根目录，直接使用文件名
        let resourceName = "\(directoryName)-\(randomIndex)"

        // 从 Bundle 加载
        guard let imageURL = Bundle.main.url(forResource: resourceName, withExtension: "jpg") else {
            logger.warning("要点图片不存在: \(resourceName).jpg")
            return nil
        }

        // 使用 Image I/O 降采样加载
        return Self.downsampleImageFromFile(url: imageURL, maxDimension: maxDimension)
    }

    /// 内部实现：实际加载图片
    private func loadImageImpl(sessionId: String, index: Int, maxDimension: CGFloat? = Constants.ImageDisplay.playbackFullScreenMaxDimension) -> UIImage? {
        // 始终走降采样路径，保护内存；maxDimension 无效时使用默认上限
        let effectiveMaxD = (maxDimension ?? 0) > 0 ? maxDimension! : Constants.ImageDisplay.playbackFullScreenMaxDimension
        let cacheKey = "\(sessionId):\(index):\(effectiveMaxD)"
        if let cached = Self.imageLoadCache.object(forKey: cacheKey as NSString) {
            return cached
        }
        // 确定图片文件 URL（内置默认会话从 Bundle 加载）
        let imageURL: URL?
        if isBundledDefaultSession(sessionId) {
            let prefix = Constants.DefaultSession.bundleFilePrefix
            imageURL = Bundle.main.url(forResource: "\(prefix)image_\(index)", withExtension: "jpg")
        } else {
            let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
            let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)
            let candidate = imagesDir.appendingPathComponent("image_\(index).jpg")
            imageURL = fileManager.fileExists(atPath: candidate.path) ? candidate : nil
        }
        guard let imageURL else { return nil }
        guard let img = Self.downsampleImageFromFile(url: imageURL, maxDimension: effectiveMaxD) else { return nil }
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
    
    /// 当 avatar.jpg 缺失时，将传入的已解码图片降采样后写入会话目录（用于列表页回退加载后补写）
    func saveAvatarIfMissing(sessionId: String, image: UIImage) {
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent(Self.avatarFileName)
        guard !fileManager.fileExists(atPath: avatarURL.path) else { return }

        // 降采样到 96pt（与 writeAvatarImage 一致，避免超大头像文件）
        let maxDim = Constants.ImageDisplay.recordAvatarMaxDimension
        let maxPixel = Int(maxDim * max(1, UIScreen.main.scale))
        let downsampled = Self.downsampleImageToMaxPixel(image, maxPixelLength: maxPixel) ?? image

        if let jpegData = downsampled.jpegData(compressionQuality: 0.85) {
            try? jpegData.write(to: avatarURL)
        }
    }
    
    /// 从会话目录加载预生成的头像图
    func loadAvatar(sessionId: String) -> UIImage? {
        // 内置默认会话从 Bundle 加载头像
        if isBundledDefaultSession(sessionId) {
            let prefix = Constants.DefaultSession.bundleFilePrefix
            guard let avatarURL = Bundle.main.url(forResource: "\(prefix)avatar", withExtension: "jpg") else { return nil }
            return Self.downsampleImageFromFile(url: avatarURL, maxDimension: Constants.ImageDisplay.recordAvatarMaxDimension)
        }
        
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let avatarURL = sessionDir.appendingPathComponent(Self.avatarFileName)
        guard fileManager.fileExists(atPath: avatarURL.path) else { return nil }
        // 使用 Image I/O 降采样加载头像，与项目其他图片加载路径一致
        return Self.downsampleImageFromFile(url: avatarURL, maxDimension: Constants.ImageDisplay.recordAvatarMaxDimension)
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
            logger.error("写入头像失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 草稿会话（后台制作）

    /// 保存草稿会话记录（仅落盘图片和 metadata，makeStatus=making，无 OCR/音频结果）
    /// - Parameters:
    ///   - id: 会话ID（由调用方生成，保证与 BackgroundMakeManager 任务对应）
    ///   - name: 草稿名称（如 "25.03.04 未命名"）
    ///   - images: 已降采样的图片数组
    /// - Returns: 是否保存成功
    func saveDraftSession(id: String, name: String, images: [UIImage]) -> Bool {
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        do {
            // 创建会话目录
            if !fileManager.fileExists(atPath: sessionDir.path) {
                try fileManager.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            }

            // 保存图片文件
            let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)
            if !fileManager.fileExists(atPath: imagesDir.path) {
                try fileManager.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            }
            let saveMaxPixel = Int(Constants.ImageDisplay.saveImageMaxPixel)
            for (index, image) in images.enumerated() {
                let imageToSave = Self.downsampleImageToMaxPixel(image, maxPixelLength: saveMaxPixel) ?? image
                guard let jpegData = imageToSave.jpegData(compressionQuality: 1.0) else { continue }
                let imageURL = imagesDir.appendingPathComponent("image_\(index).jpg")
                try jpegData.write(to: imageURL)
            }

            // 预生成头像
            if !images.isEmpty {
                writeAvatarImage(sessionDir: sessionDir, imagesDir: imagesDir, avatarImageIndex: 0)
            }

            // 构建 record（空 OCR/音频，makeStatus=making）
            let emptySegments = Array(repeating: "", count: images.count)
            let record = SessionRecord(
                id: id,
                name: name,
                images: images,
                ocrText: "",
                ocrTextSegments: emptySegments,
                audioData: Data(),
                audioFormat: "mp3",
                audioDuration: 0,
                ocrDuration: 0,
                ttsDuration: 0,
                validImageCount: 0,
                makeStatus: .making
            )

            // 保存 metadata.json
            let metadata = SessionRecordMetadata(from: record)
            let metadataData = try JSONEncoder().encode(metadata)
            let metadataURL = sessionDir.appendingPathComponent("metadata.json")
            try metadataData.write(to: metadataURL)

            // 保存 record.json
            let recordData = try JSONEncoder().encode(record)
            let recordURL = sessionDir.appendingPathComponent("record.json")
            try recordData.write(to: recordURL)

            invalidateMetadataCache()
            logger.info("草稿会话保存成功: \(name), id=\(id), 图片数=\(images.count)")
            return true
        } catch {
            logger.error("草稿会话保存失败: \(error.localizedDescription)")
            return false
        }
    }

    /// 更新草稿会话的 OCR/TTS 结果（makeStatus 置为 completed）
    /// - Parameters:
    ///   - id: 会话ID
    ///   - audioResponse: Coordinator 返回的完整音频响应
    ///   - ocrDuration: OCR 耗时
    ///   - ttsDuration: TTS 耗时
    /// - Returns: 是否更新成功
    func updateSessionWithResults(id: String, audioResponse: AudioResponse, ocrDuration: TimeInterval, llmDuration: TimeInterval = 0, ttsDuration: TimeInterval) -> Bool {
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        let recordURL = sessionDir.appendingPathComponent("record.json")
        guard fileManager.fileExists(atPath: recordURL.path) else {
            logger.error("更新草稿失败，record.json 不存在: \(id)")
            return false
        }

        do {
            let data = try Data(contentsOf: recordURL)
            let oldRecord = try JSONDecoder().decode(SessionRecord.self, from: data)

            let ocrText = audioResponse.text
            let ocrTextSegments = audioResponse.recognizedTexts ?? []
            let audioData = audioResponse.audioData ?? Data()
            let audioFormat = audioResponse.format.isEmpty ? "mp3" : audioResponse.format

            // 处理LLM生成的名称：保留日期前缀"yy.MM.dd "，替换后半部分
            let updatedName: String
            if let storyName = audioResponse.storyName, !storyName.isEmpty {
                // 生成默认日期前缀（当前日期）
                let formatter = DateFormatter()
                formatter.dateFormat = Constants.sessionNameDatePrefixFormat
                let defaultDatePrefix = formatter.string(from: Date())
                updatedName = defaultDatePrefix + storyName
            } else {
                updatedName = oldRecord.name
            }

            let updatedRecord = SessionRecord(
                id: oldRecord.id,
                name: updatedName,
                createdAt: oldRecord.createdAt,
                updatedAt: Date(),
                imageDataList: oldRecord.imageDataList,
                ocrText: ocrText,
                ocrTextSegments: ocrTextSegments,
                audioDataBase64: "",
                audioFormat: audioFormat,
                audioDuration: audioResponse.duration,
                ocrDuration: ocrDuration,
                ttsDuration: ttsDuration,
                validImageCount: audioResponse.validImageCount ?? oldRecord.totalImageCount,
                totalImageCount: oldRecord.totalImageCount,
                textLength: ocrText.count,
                audioSize: audioData.count,
                voiceSettings: audioResponse.voiceSettings,
                avatarImageIndex: oldRecord.avatarImageIndex,
                storageSize: 0,
                makeStatus: .completed,
                storyHighlights: audioResponse.storyHighlights,
                hasVirtualPage: audioResponse.hasVirtualPage ?? false,
                animationStyle: oldRecord.animationStyle
            )

            // 保存音频文件
            if !audioData.isEmpty {
                let audioURL = sessionDir.appendingPathComponent("audio.\(audioFormat)")
                try audioData.write(to: audioURL)
            }

            // 保存 record.json
            let updatedRecordData = try JSONEncoder().encode(updatedRecord)
            try updatedRecordData.write(to: recordURL)

            // 保存 metadata.json
            let metadata = SessionRecordMetadata(from: updatedRecord)
            let metadataURL = sessionDir.appendingPathComponent("metadata.json")
            let metadataData = try JSONEncoder().encode(metadata)
            try metadataData.write(to: metadataURL)

            // 更新存储大小
            let storageSize = calculateDirectorySize(sessionDir)
            let sizeUpdatedRecord = updatedRecord.withStorageSize(storageSize)
            let sizeUpdatedRecordData = try JSONEncoder().encode(sizeUpdatedRecord)
            try sizeUpdatedRecordData.write(to: recordURL)
            let sizeUpdatedMetadata = SessionRecordMetadata(from: sizeUpdatedRecord)
            let sizeUpdatedMetadataData = try JSONEncoder().encode(sizeUpdatedMetadata)
            try sizeUpdatedMetadataData.write(to: metadataURL)

            invalidateMetadataCache()
            logger.info("草稿会话更新完成: \(oldRecord.name), id=\(id), 文本长度=\(ocrText.count), 音频大小=\(audioData.count)")
            return true
        } catch {
            logger.error("更新草稿会话失败: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - 更新会话记录
    
    /// 更新会话记录（名称、头像等可选项，仅更新传入的非 nil 参数）
    /// - Parameters:
    ///   - id: 会话记录ID
    ///   - name: 新名称（nil 表示不修改）
    ///   - avatarImageIndex: 头像图片索引（nil 表示不修改）
    /// - Returns: 更新是否成功
    func updateSession(id: String, name: String? = nil, avatarImageIndex: Int? = nil, animationStyle: AnimationStyle? = nil) -> Bool {
        // 内置默认会话不可更新
        if isBundledDefaultSession(id) {
            logger.warning("内置默认会话不可更新")
            return false
        }
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

        let newAnimationStyle = animationStyle ?? record.animationStyle

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
            storageSize: record.storageSize,
            makeStatus: record.makeStatus,
            storyHighlights: record.storyHighlights,
            hasVirtualPage: record.hasVirtualPage,
            animationStyle: newAnimationStyle
        )

        let result = saveSession(updatedRecord)
        return result.success
    }
    
    // MARK: - 删除会话记录
    
    /// 删除会话记录
    /// - Parameter id: 会话记录ID
    /// - Returns: 删除是否成功
    func deleteSession(id: String) -> Bool {
        // 内置默认会话不可删除
        if isBundledDefaultSession(id) {
            logger.warning("内置默认会话不可删除")
            return false
        }
        
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        
        // 读取记录名称用于日志
        let metadataURL = sessionDir.appendingPathComponent("metadata.json")
        let sessionName: String
        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(SessionRecordMetadata.self, from: data) {
            sessionName = metadata.name
        } else {
            sessionName = id
        }
        
        do {
            try fileManager.removeItem(at: sessionDir)
            invalidateMetadataCache()
            logger.info("删除会话记录成功: \(sessionName)")
            return true
        } catch {
            logger.error("删除会话记录失败: \(sessionName), 错误: \(error.localizedDescription)")
            return false
        }
    }
    
    // MARK: - 清空所有会话记录

    /// 清空所有会话记录
    /// - Returns: 结果，包含是否全部成功、成功数量、错误描述
    func clearAllSessions() -> (success: Bool, count: Int, errorMessage: String?) {
        let allMetadata = getAllSessionMetadata(caller: "清空记录")
        var successCount = 0
        var failedCount = 0

        for metadata in allMetadata {
            let sessionDir = sessionsDirectory.appendingPathComponent(metadata.id, isDirectory: true)
            do {
                try fileManager.removeItem(at: sessionDir)
                successCount += 1
            } catch {
                logger.error("删除会话记录失败: \(metadata.name), 错误: \(error.localizedDescription)")
                failedCount += 1
            }
        }

        invalidateMetadataCache()
        logger.info("清空会话记录完成: 成功 \(successCount) 个，失败 \(failedCount) 个")
        if failedCount > 0 {
            return (false, successCount, "共 \(allMetadata.count) 个，清空成功 \(successCount) 个，失败 \(failedCount) 个")
        }
        return (true, successCount, nil)
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
            logger.error("计算存储大小失败: \(error.localizedDescription)")
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
    
    // MARK: - 导出会话记录

    /// 导出单条会话记录到指定目录
    /// 导出结构：destinationURL/<记录名称>/（目录名与全量导出时单条记录目录命名习惯一致）
    /// - Parameters:
    ///   - id: 会话记录ID
    ///   - destinationURL: 目标父目录URL（方法会在其中创建以记录名称命名的子目录）
    /// - Returns: 导出结果
    func exportSession(id: String, to destinationURL: URL) -> (success: Bool, size: Int64?, errorMessage: String?) {
        // 内置默认会话不可导出
        if isBundledDefaultSession(id) {
            logger.warning("内置默认会话不可导出")
            return (false, nil, "内置默认会话不可导出")
        }
        let sessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
        guard fileManager.fileExists(atPath: sessionDir.path) else {
            return (false, nil, "会话目录不存在: \(id)")
        }
        // 读取记录名称，用 sanitizeFolderName 处理后作为目录名，与全量导出命名习惯一致
        // 在 do 块外读取，确保 catch 中也能使用名称记日志
        let metadataURL = sessionDir.appendingPathComponent("metadata.json")
        let sessionName: String
        if let metadataData = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(SessionRecordMetadata.self, from: metadataData) {
            sessionName = metadata.name
        } else {
            sessionName = id
        }
        do {
            try fileManager.createDirectory(at: destinationURL, withIntermediateDirectories: true)
            let folderName = sanitizeFolderName(sessionName)
            let targetDir = destinationURL.appendingPathComponent(folderName, isDirectory: true)
            if fileManager.fileExists(atPath: targetDir.path) {
                try fileManager.removeItem(at: targetDir)
            }
            try fileManager.copyItem(at: sessionDir, to: targetDir)
            let size = calculateDirectorySize(targetDir)
            logger.info("单条会话记录导出成功: \(sessionName), 文件夹: \(folderName), 大小: \(self.formatStorageSize(size))")
            return (true, size, nil)
        } catch {
            logger.error("单条会话记录导出失败: \(sessionName), 错误: \(error.localizedDescription)")
            return (false, nil, error.localizedDescription)
        }
    }

    /// 导出选中的会话记录到指定目录
    /// 导出结构：
    ///   PhotoTTS_YYMMDD 或 PhotoTTS-P_YYMMDD/
    ///     - export_manifest.json (导出清单，包含版本、导出时间、会话列表等)
    ///     - Sessions/ (选中的会话记录目录)
    ///       - {session_id_1}/
    ///       - {session_id_2}/
    ///       - ...
    /// - Parameters:
    ///   - sessionIDs: 要导出的会话 ID 列表
    ///   - destinationURL: 目标目录 URL（用户选择的目录）
    ///   - isAllSelected: 是否选中了全部记录（用于决定导出目录命名）
    /// - Returns: 导出结果
    func exportSelectedSessions(_ sessionIDs: [String], to destinationURL: URL, isAllSelected: Bool = false) -> (success: Bool, sessionCount: Int, totalSize: Int64, errorMessage: String?) {
        do {
            // 生成导出目录名称：全选时用 PhotoTTS_YYMMDD，部分选择时用 PhotoTTS-P_YYMMDD
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyMMdd"
            let dateStr = dateFormatter.string(from: Date())
            let exportDirName = isAllSelected ? "PhotoTTS_\(dateStr)" : "PhotoTTS-P_\(dateStr)"
            let exportDir = destinationURL.appendingPathComponent(exportDirName, isDirectory: true)
            
            // 创建导出目录
            try fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
            
            var exportedCount = 0
            var totalSize: Int64 = 0
            var exportedSessions: [ExportSessionInfo] = []
            
            // 确保 Sessions 导出目录存在
            let sessionsExportDir = exportDir.appendingPathComponent("Sessions", isDirectory: true)
            if !fileManager.fileExists(atPath: sessionsExportDir.path) {
                try fileManager.createDirectory(at: sessionsExportDir, withIntermediateDirectories: true)
            }
            
            // 复制每个选中的会话记录目录
            for id in sessionIDs {
                // 跳过默认会话
                if isBundledDefaultSession(id) {
                    continue
                }
                
                let sourceSessionDir = sessionsDirectory.appendingPathComponent(id, isDirectory: true)
                guard fileManager.fileExists(atPath: sourceSessionDir.path) else {
                    continue
                }
                
                // 读取元数据获取名称
                let metadataURL = sourceSessionDir.appendingPathComponent("metadata.json")
                guard let metadataData = try? Data(contentsOf: metadataURL),
                      let metadata = try? JSONDecoder().decode(SessionRecordMetadata.self, from: metadataData) else {
                    continue
                }
                
                // 计算合法的文件夹名，处理名称冲突
                let baseFolderName = sanitizeFolderName(metadata.name)
                var folderName = baseFolderName
                var collisionIndex = 1
                while fileManager.fileExists(atPath: sessionsExportDir.appendingPathComponent(folderName).path) {
                    folderName = "\(baseFolderName)_\(collisionIndex)"
                    collisionIndex += 1
                }
                let targetSessionDir = sessionsExportDir.appendingPathComponent(folderName, isDirectory: true)
                
                // 复制整个会话目录
                try fileManager.copyItem(at: sourceSessionDir, to: targetSessionDir)
                
                // 计算会话大小
                let sessionSize = calculateDirectorySize(targetSessionDir)
                totalSize += sessionSize
                exportedCount += 1
                
                exportedSessions.append(ExportSessionInfo(
                    id: metadata.id,
                    name: metadata.name,
                    createdAt: metadata.createdAt,
                    size: sessionSize,
                    folderName: folderName
                ))
                
                logger.info("导出会话记录：\(metadata.name), 文件夹：\(folderName) (\(self.formatStorageSize(sessionSize)))")
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
            var sessionNameList = ""
            if !exportedSessions.isEmpty {
                sessionNameList = "\n\n会话列表（按展示顺序）：\n"
                for (index, session) in exportedSessions.enumerated() {
                    sessionNameList += "\(index + 1). \(session.name)\n"
                }
            }
            
            let readmeContent = """
            PhotoTTS 会话记录导出包
            ======================
            
            导出时间：\(manifest.formattedExportDate)
            会话数量：\(exportedCount) 个
            总大小：\(self.formatStorageSize(totalSize))\(sessionNameList)
            
            目录结构：
            - export_manifest.json: 导出清单（包含所有会话的元数据）
            - Sessions/: 会话记录目录
              - {session_id}/: 每个会话记录的完整数据
            
            导入说明：
            将来可以通过 PhotoTTS 应用的导入功能，选择此目录进行导入。
            导入时会自动解析 export_manifest.json 并恢复所有会话记录。
            
            版本：\(manifest.version)
            """
            let readmeURL = exportDir.appendingPathComponent("README.txt")
            try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
            
            // 设置导出目录属性
            var mutableExportDir = exportDir
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try? mutableExportDir.setResourceValues(resourceValues)
            
            logger.info("导出完成：\(exportedCount) 个会话记录，总大小：\(self.formatStorageSize(totalSize))")
            logger.info("导出位置：\(exportDir.path)")
            
            return (true, exportedCount, totalSize, nil)
            
        } catch {
            logger.error("导出会话记录失败：\(error.localizedDescription)")
            return (false, 0, 0, error.localizedDescription)
        }
    }
    
    /// 导出所有会话记录到指定目录（全量导出，委托给 exportSelectedSessions）
    /// - Parameter destinationURL: 目标目录 URL（用户选择的目录）
    /// - Returns: 导出结果
    func exportAllSessions(to destinationURL: URL) -> (success: Bool, sessionCount: Int, totalSize: Int64, errorMessage: String?) {
        let allMetadata = getAllSessionMetadata(caller: "全量导出")
        let allIDs = allMetadata.map { $0.id }
        return exportSelectedSessions(allIDs, to: destinationURL, isAllSelected: true)
    }
    
    // MARK: - 导入会话记录
    
    /// 根据所选目录自动识别并导入：若为导出包(含 export_manifest.json) 则全量导入，若为单个会话目录(含 record.json) 则仅导入该条
    /// - Parameter sourceURL: 用户选择的目录（导出包根目录 或 单个会话目录）
    /// - Returns: 导入结果
    func importSessions(from sourceURL: URL) -> (success: Bool, importedCount: Int, skippedCount: Int, duplicateCount: Int, totalSize: Int64, errorMessage: String?) {
        let manifestURL = sourceURL.appendingPathComponent("export_manifest.json")
        let recordURL = sourceURL.appendingPathComponent("record.json")
        if fileManager.fileExists(atPath: manifestURL.path) {
            return importAllSessions(from: sourceURL)
        }
        if fileManager.fileExists(atPath: recordURL.path) {
            return importOneSession(from: sourceURL)
        }
        return (false, 0, 0, 0, 0, "请选择导出包目录(含 export_manifest.json) 或单个会话目录(含 record.json)")
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
    func importAllSessions(from sourceURL: URL) -> (success: Bool, importedCount: Int, skippedCount: Int, duplicateCount: Int, totalSize: Int64, errorMessage: String?) {
        // 注意：调用此方法前，调用方应该已经获取了sourceURL的安全作用域资源访问权限
        do {
            // 检查是否存在export_manifest.json
            let manifestURL = sourceURL.appendingPathComponent("export_manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else {
                return (false, 0, 0, 0, 0, "未找到导出清单文件(export_manifest.json)，请确保选择了正确的导出目录")
            }
            
            // 解析导出清单
            let manifestData = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)
            
            logger.info("开始导入会话记录，导出时间: \(manifest.formattedExportDate)，会话数量: \(manifest.totalSessions)")
            
            // 检查Sessions目录是否存在
            let sourceSessionsDir = sourceURL.appendingPathComponent("Sessions", isDirectory: true)
            guard fileManager.fileExists(atPath: sourceSessionsDir.path) else {
                return (false, 0, 0, 0, 0, "未找到Sessions目录，导出包可能已损坏")
            }
            
            // 获取所有现有会话ID，用于去重检测
            let existingMetadata = getAllSessionMetadata(caller: "全量导入")
            let existingIDs = Set(existingMetadata.map { $0.id })
            
            var importedCount = 0
            var skippedCount = 0
            var duplicateCount = 0
            var totalSize: Int64 = 0
            
            // 导入每个会话记录（folderName 为实际目录名；旧版包无此字段时回退为 id）
            for sessionInfo in manifest.sessions {
                let sourceSessionDir = sourceSessionsDir.appendingPathComponent(sessionInfo.folderName, isDirectory: true)
                
                // 检查源会话目录是否存在
                guard fileManager.fileExists(atPath: sourceSessionDir.path) else {
                    logger.warning("跳过会话记录（目录不存在）: \(sessionInfo.name), 文件夹: \(sessionInfo.folderName)")
                    skippedCount += 1
                    continue
                }
                
                // ID 重复则跳过，不导入
                if existingIDs.contains(sessionInfo.id) {
                    logger.info("跳过会话记录（ID重复）: \(sessionInfo.name)")
                    duplicateCount += 1
                    continue
                }
                
                let targetSessionDir = sessionsDirectory.appendingPathComponent(sessionInfo.id, isDirectory: true)
                
                // 复制会话目录
                do {
                    try fileManager.copyItem(at: sourceSessionDir, to: targetSessionDir)
                    
                    // 设置目录和文件权限
                    var mutableSessionDir = targetSessionDir
                    var resourceValues = URLResourceValues()
                    resourceValues.isExcludedFromBackup = false
                    try? mutableSessionDir.setResourceValues(resourceValues)
                    
                    // 修复目录内所有文件和子目录的权限
                    fixSessionDirectoryPermissions(targetSessionDir)
                    
                    // 计算导入的会话大小，并更新文件内的 storageSize 元数据
                    let sessionSize = calculateDirectorySize(targetSessionDir)
                    updateStorageSizeInFiles(sessionDir: targetSessionDir, size: sessionSize)
                    totalSize += sessionSize
                    importedCount += 1
                    
                    logger.info("导入会话记录: \(sessionInfo.name) (\(self.formatStorageSize(sessionSize)))")
                    
                } catch {
                    logger.error("导入会话记录失败: \(sessionInfo.name), 错误: \(error.localizedDescription)")
                    skippedCount += 1
                }
            }
            
            let totalCount = manifest.sessions.count
            invalidateMetadataCache()
            logger.info("导入完成: 共 \(totalCount) 个，导入 \(importedCount) 个，ID重复跳过 \(duplicateCount) 个，其他跳过 \(skippedCount) 个，总大小: \(self.formatStorageSize(totalSize))")
            
            return (true, importedCount, skippedCount, duplicateCount, totalSize, nil)
            
        } catch let error as DecodingError {
            let errorMessage = "解析导出清单失败: \(error.localizedDescription)"
            logger.error("导入失败，\(errorMessage)")
            return (false, 0, 0, 0, 0, errorMessage)
        } catch {
            logger.error("导入会话记录失败: \(error.localizedDescription)")
            return (false, 0, 0, 0, 0, error.localizedDescription)
        }
    }
    
    /// 导入单个会话记录（用户选择的目录须直接包含 record.json）
    /// - Parameter sourceURL: 单个会话目录的 URL（其下含 record.json、可选 audio.*、images/）
    /// - Returns: 导入结果
    func importOneSession(from sourceURL: URL) -> (success: Bool, importedCount: Int, skippedCount: Int, duplicateCount: Int, totalSize: Int64, errorMessage: String?) {
        let recordURL = sourceURL.appendingPathComponent("record.json")
        guard fileManager.fileExists(atPath: recordURL.path) else {
            return (false, 0, 0, 0, 0, "该目录下未找到 record.json，请选择单个会话目录")
        }
        do {
            // 读取 record.json 获取原 ID（用于去重检测与日志）
            let recordData = try Data(contentsOf: recordURL)
            let record = try JSONDecoder().decode(SessionRecord.self, from: recordData)
            let sourceID = record.id
            let sessionName = record.name
            
            let existingMetadata = getAllSessionMetadata(caller: "单条导入")
            let existingIDs = Set(existingMetadata.map { $0.id })
            
            // ID 重复则跳过，不导入
            if existingIDs.contains(sourceID) {
                logger.info("跳过单条会话记录（ID重复）: \(sessionName)")
                return (true, 0, 0, 1, 0, nil)
            }
            
            let targetSessionDir = sessionsDirectory.appendingPathComponent(sourceID, isDirectory: true)
            try fileManager.copyItem(at: sourceURL, to: targetSessionDir)
            var mutableSessionDir = targetSessionDir
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = false
            try? mutableSessionDir.setResourceValues(resourceValues)
            fixSessionDirectoryPermissions(targetSessionDir)
            // 计算导入的会话大小，并更新文件内的 storageSize 元数据
            let sessionSize = calculateDirectorySize(targetSessionDir)
            updateStorageSizeInFiles(sessionDir: targetSessionDir, size: sessionSize)
            invalidateMetadataCache()
            logger.info("导入单条会话记录: \(sessionName) (\(self.formatStorageSize(sessionSize)))")
            return (true, 1, 0, 0, sessionSize, nil)
        } catch {
            logger.error("导入单条会话记录失败: \(error.localizedDescription)")
            return (false, 0, 0, 0, 0, error.localizedDescription)
        }
    }
    
    /// 将记录名称转换为合法的文件系统文件夹名
    /// 替换 /\:*?"<>| 及控制字符，截断超长名称，空串回退为 "session"
    private func sanitizeFolderName(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters)
        var sanitized = name
            .unicodeScalars
            .map { invalidChars.contains($0) ? "_" : Character($0) }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty { sanitized = "session" }
        // iOS/macOS 文件名最大 255 字节，预留 "_999" 后缀空间
        while sanitized.utf8.count > 240 {
            sanitized = String(sanitized.dropLast())
        }
        return sanitized
    }

    /// 更新导入后会话目录中 metadata.json 和 record.json 里的 storageSize 字段
    /// - Parameters:
    ///   - sessionDir: 目标会话目录
    ///   - size: 导入后计算的实际磁盘占用（字节）
    private func updateStorageSizeInFiles(sessionDir: URL, size: Int64) {
        let metadataURL = sessionDir.appendingPathComponent("metadata.json")
        let recordURL = sessionDir.appendingPathComponent("record.json")

        if let data = try? Data(contentsOf: metadataURL),
           let metadata = try? JSONDecoder().decode(SessionRecordMetadata.self, from: data),
           let updatedData = try? JSONEncoder().encode(metadata.withStorageSize(size)) {
            try? updatedData.write(to: metadataURL)
        }

        if let data = try? Data(contentsOf: recordURL),
           let record = try? JSONDecoder().decode(SessionRecord.self, from: data),
           let updatedData = try? JSONEncoder().encode(record.withStorageSize(size)) {
            try? updatedData.write(to: recordURL)
        }
    }

    // MARK: - 会话历史（history.json）

    private static let historyFileName = "history.json"

    private let historyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let historyDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 加载指定会话的历史记录
    func loadSessionHistory(sessionId: String) -> SessionHistory {
        // 内置默认会话从 Bundle 加载历史
        if isBundledDefaultSession(sessionId) {
            let prefix = Constants.DefaultSession.bundleFilePrefix
            guard let historyURL = Bundle.main.url(forResource: "\(prefix)history", withExtension: "json"),
                  let data = try? Data(contentsOf: historyURL),
                  let history = try? historyDecoder.decode(SessionHistory.self, from: data) else {
                return SessionHistory()
            }
            return history
        }
        
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let historyURL = sessionDir.appendingPathComponent(Self.historyFileName)
        guard fileManager.fileExists(atPath: historyURL.path),
              let data = try? Data(contentsOf: historyURL),
              let history = try? historyDecoder.decode(SessionHistory.self, from: data) else {
            return SessionHistory()
        }
        return history
    }

    /// 保存指定会话的历史记录
    func saveSessionHistory(sessionId: String, history: SessionHistory) {
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        guard fileManager.fileExists(atPath: sessionDir.path) else {
            logger.warning("保存历史失败，会话目录不存在: \(sessionId)")
            return
        }
        let historyURL = sessionDir.appendingPathComponent(Self.historyFileName)
        do {
            let data = try historyEncoder.encode(history)
            try data.write(to: historyURL)
        } catch {
            logger.error("保存会话历史失败: \(error.localizedDescription)")
        }
    }

    /// 向指定会话追加一条制作事件
    func addMakeEvent(sessionId: String, timestamp: Date = Date(), identity: String) {
        // 内置默认会话不记录事件
        if isBundledDefaultSession(sessionId) { return }
        var history = loadSessionHistory(sessionId: sessionId)
        history.makeEvents.append(SessionHistoryEvent(timestamp: timestamp, identity: identity))
        history.makeEvents.sort { $0.timestamp > $1.timestamp }
        saveSessionHistory(sessionId: sessionId, history: history)
    }

    /// 向指定会话追加一条播放事件
    func addPlayEvent(sessionId: String, timestamp: Date = Date(), identity: String) {
        // 内置默认会话不记录事件
        if isBundledDefaultSession(sessionId) { return }
        var history = loadSessionHistory(sessionId: sessionId)
        history.playEvents.append(SessionHistoryEvent(timestamp: timestamp, identity: identity))
        history.playEvents.sort { $0.timestamp > $1.timestamp }
        // 裁剪到上限
        if history.playEvents.count > Constants.maxPlayHistoryRecords {
            history.playEvents = Array(history.playEvents.prefix(Constants.maxPlayHistoryRecords))
        }
        saveSessionHistory(sessionId: sessionId, history: history)
    }

    /// 加载所有会话的历史记录（聚合），返回 (sessionId, name, history) 三元组列表
    /// 内置默认会话不参与历史聚合
    func loadAllSessionHistories() -> [(id: String, name: String, history: SessionHistory)] {
        let allMetadata = getAllSessionMetadata(caller: "历史聚合")
        var result: [(id: String, name: String, history: SessionHistory)] = []
        for metadata in allMetadata {
            // 内置默认会话不出现在播放/制作历史中
            if isBundledDefaultSession(metadata.id) { continue }
            let history = loadSessionHistory(sessionId: metadata.id)
            if !history.makeEvents.isEmpty || !history.playEvents.isEmpty {
                result.append((id: metadata.id, name: metadata.name, history: history))
            }
        }
        return result
    }

    // MARK: - 内置默认会话（Bundle 资源，用户无记录时展示）

    /// 判断是否为内置默认会话
    func isBundledDefaultSession(_ id: String) -> Bool {
        return id == Constants.DefaultSession.id
    }

    /// 从 Bundle 加载内置默认会话的元数据
    private func loadBundledDefaultSessionMetadata() -> SessionRecordMetadata? {
        let prefix = Constants.DefaultSession.bundleFilePrefix
        guard let url = Bundle.main.url(forResource: "\(prefix)metadata", withExtension: "json") else {
            return nil
        }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SessionRecordMetadata.self, from: data)
    }

    /// 从 Bundle 加载内置默认会话的完整记录
    private func loadBundledDefaultSession() -> SessionRecord? {
        let prefix = Constants.DefaultSession.bundleFilePrefix
        guard let recordURL = Bundle.main.url(forResource: "\(prefix)record", withExtension: "json") else {
            logger.warning("内置默认会话 record.json 不存在")
            return nil
        }
        do {
            let data = try Data(contentsOf: recordURL)
            let record = try JSONDecoder().decode(SessionRecord.self, from: data)

            // 加载音频
            let audioURL = Bundle.main.url(forResource: "\(prefix)audio", withExtension: record.audioFormat)
            let audioData: Data = audioURL.flatMap { try? Data(contentsOf: $0) } ?? Data()

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
                storageSize: record.storageSize,
                makeStatus: record.makeStatus,
                storyHighlights: record.storyHighlights,
                hasVirtualPage: record.hasVirtualPage,
                animationStyle: record.animationStyle
            )

            logger.info("加载内置默认会话成功: \(record.name)")
            return resultRecord
        } catch {
            logger.error("加载内置默认会话失败: \(error.localizedDescription)")
            return nil
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
            logger.warning("更新会话ID失败: \(error.localizedDescription)")
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
    /// 导出时实际使用的文件夹名（经合法性校验，可能与 name 不同）；旧版包不含此字段时回退为 id
    let folderName: String

    init(id: String, name: String, createdAt: Date, size: Int64, folderName: String) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.size = size
        self.folderName = folderName
    }

    // 兼容不含 folderName 的旧版导出包
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        size = try c.decode(Int64.self, forKey: .size)
        folderName = try c.decodeIfPresent(String.self, forKey: .folderName) ?? id
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt, size, folderName
    }
}


