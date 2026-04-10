import Foundation
import UIKit
import CoreImage
import ImageIO
import os.log

// MARK: - 封面图片管理器
/// 负责封面图片的生成、裁剪、旋转和保存
final class CoverImageManager {

    // MARK: - Properties

    private let fileManager = FileManager.default
    private let ciContext = CIContext()

    private var sessionsDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Sessions", isDirectory: true)
    }

    private static let logger = os.Logger(subsystem: "com.photoTTS.PhotoTTS", category: "CoverImageManager")

    // MARK: - Error

    enum CoverError: LocalizedError {
        case imageNotFound
        case loadFailed
        case processingFailed
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .imageNotFound:
                return "封面图片不存在"
            case .loadFailed:
                return "图片加载失败"
            case .processingFailed:
                return "图片处理失败"
            case .saveFailed:
                return "封面保存失败"
            }
        }

        var technicalDescription: String {
            switch self {
            case .imageNotFound:
                return "CoverError: image file not found"
            case .loadFailed:
                return "CoverError: failed to load image"
            case .processingFailed:
                return "CoverError: failed to process image"
            case .saveFailed:
                return "CoverError: failed to save cover image"
            }
        }
    }

    // MARK: - Public Methods

    /// 生成封面图片
    /// - Parameters:
    ///   - sessionId: 会话 ID
    ///   - firstImagePath: 第一张图片的完整路径
    /// - Returns: 封面文件路径（相对于 session 目录）
    func generateCover(sessionId: String, firstImagePath: String) async throws -> String {
        // 检查第一张图片是否存在
        let firstImageURL = URL(fileURLWithPath: firstImagePath)
        guard fileManager.fileExists(atPath: firstImagePath) else {
            Self.logger.error("第一张图片不存在: \(firstImagePath)")
            throw CoverError.imageNotFound
        }

        // 加载图片
        guard let imageData = try? Data(contentsOf: firstImageURL),
              let ciImage = CIImage(data: imageData) else {
            Self.logger.error("图片加载失败: \(firstImagePath)")
            throw CoverError.loadFailed
        }

        // 居中裁剪为 16:9
        let croppedImage = cropToAspectRatio(image: ciImage, aspectRatio: Constants.HomeCard.coverAspectRatio)

        // 缩放到最大边 1024px
        let resizedImage = resizeImage(croppedImage, maxDimension: Constants.HomeCard.coverMaxDimension)

        // 转换为 JPEG Data
        guard let jpegData = convertToJPEG(ciImage: resizedImage, quality: Constants.HomeCard.coverJPEGQuality) else {
            Self.logger.error("图片转换 JPEG 失败")
            throw CoverError.processingFailed
        }

        // 保存封面文件
        let coverPath = try saveCover(data: jpegData, sessionId: sessionId)
        Self.logger.info("封面生成成功: \(coverPath)")
        return coverPath
    }

    /// 裁剪并旋转图片
    /// - Parameters:
    ///   - imagePath: 图片路径
    ///   - rotation: 旋转角度（0/90/180/270）
    /// - Returns: 处理后的 JPEG Data
    func cropAndRotate(imagePath: String, rotation: Int) async throws -> Data? {
        // 检查图片是否存在
        guard fileManager.fileExists(atPath: imagePath) else {
            Self.logger.error("图片不存在: \(imagePath)")
            throw CoverError.imageNotFound
        }

        // 加载图片
        guard let imageData = try? Data(contentsOf: URL(fileURLWithPath: imagePath)),
              var ciImage = CIImage(data: imageData) else {
            Self.logger.error("图片加载失败: \(imagePath)")
            throw CoverError.loadFailed
        }

        // 应用旋转
        if rotation != 0 {
            ciImage = rotateImage(ciImage, degrees: rotation)
        }

        // 居中裁剪为 16:9
        let croppedImage = cropToAspectRatio(image: ciImage, aspectRatio: Constants.HomeCard.coverAspectRatio)

        // 缩放到最大边 1024px
        let resizedImage = resizeImage(croppedImage, maxDimension: Constants.HomeCard.coverMaxDimension)

        // 转换为 JPEG Data
        guard let jpegData = convertToJPEG(ciImage: resizedImage, quality: Constants.HomeCard.coverJPEGQuality) else {
            Self.logger.error("图片转换 JPEG 失败")
            throw CoverError.processingFailed
        }

        return jpegData
    }

    /// 保存封面文件
    /// - Parameters:
    ///   - data: JPEG 数据
    ///   - sessionId: 会话 ID
    /// - Returns: 封面文件路径（相对于 session 目录）
    func saveCover(data: Data, sessionId: String) throws -> String {
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let coverURL = sessionDir.appendingPathComponent("cover.jpg")

        do {
            try data.write(to: coverURL)
            Self.logger.info("封面保存成功: \(coverURL.path)")
        } catch {
            Self.logger.error("封面保存失败: \(error.localizedDescription)")
            throw CoverError.saveFailed
        }

        return "cover.jpg"
    }

    /// 获取会话的封面文件完整路径
    /// - Parameter sessionId: 会话 ID
    /// - Returns: 封面文件完整路径，不存在则返回 nil
    func coverImageFullPath(for sessionId: String) -> String? {
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let coverURL = sessionDir.appendingPathComponent("cover.jpg")

        if fileManager.fileExists(atPath: coverURL.path) {
            return coverURL.path
        }
        return nil
    }

    /// 获取第一张图片的路径
    /// - Parameter sessionId: 会话 ID
    /// - Returns: 第一张图片的完整路径，不存在则返回 nil
    func firstImagePath(for sessionId: String) -> String? {
        let sessionDir = sessionsDirectory.appendingPathComponent(sessionId, isDirectory: true)
        let imagesDir = sessionDir.appendingPathComponent("images", isDirectory: true)
        let firstImageURL = imagesDir.appendingPathComponent("image_0.jpg")

        if fileManager.fileExists(atPath: firstImageURL.path) {
            return firstImageURL.path
        }
        return nil
    }

    // MARK: - Private Methods

    /// 居中裁剪图片为指定宽高比
    private func cropToAspectRatio(image: CIImage, aspectRatio: CGFloat) -> CIImage {
        let extent = image.extent
        let imageAspect = extent.width / extent.height

        var cropRect: CGRect

        if imageAspect > aspectRatio {
            // 图片较宽，按高度裁剪
            let newWidth = extent.height * aspectRatio
            let x = (extent.width - newWidth) / 2
            cropRect = CGRect(x: x, y: 0, width: newWidth, height: extent.height)
        } else {
            // 图片较高，按宽度裁剪
            let newHeight = extent.width / aspectRatio
            let y = (extent.height - newHeight) / 2
            cropRect = CGRect(x: 0, y: y, width: extent.width, height: newHeight)
        }

        return image.cropped(to: cropRect)
    }

    /// 旋转图片
    private func rotateImage(_ image: CIImage, degrees: Int) -> CIImage {
        let radians = CGFloat(degrees) * .pi / 180
        var transform = CGAffineTransform(rotationAngle: radians)

        // 处理旋转后的边界
        let rotated = image.transformed(by: transform)

        // 重新定位到正确位置
        let extent = rotated.extent
        transform = CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y)

        return rotated.transformed(by: transform)
    }

    /// 缩放图片到最大边限制
    private func resizeImage(_ image: CIImage, maxDimension: CGFloat) -> CIImage {
        let extent = image.extent
        let maxSide = max(extent.width, extent.height)

        if maxSide <= maxDimension {
            return image
        }

        let scale = maxDimension / maxSide
        let transform = CGAffineTransform(scaleX: scale, y: scale)

        return image.transformed(by: transform)
    }

    /// 将 CIImage 转换为 JPEG Data
    private func convertToJPEG(ciImage: CIImage, quality: CGFloat) -> Data? {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
}