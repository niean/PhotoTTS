import XCTest
import UIKit
@testable import PhotoTTS

final class EndPictMediaTests: XCTestCase {
    private let manager = SessionRecordManager.shared
    private let direction = Constants.EndPicts.horizontalDirectoryName
    private var createdURLs: [URL] = []

    override func tearDown() {
        for url in createdURLs {
            try? FileManager.default.removeItem(at: url)
        }
        createdURLs.removeAll()
        try? FileManager.default.removeItem(at: configURL())
        manager.resetEndPictQueue(direction: direction)
        super.tearDown()
    }

    func testEndPictMediaKindRecognizesImagesAndVideos() {
        XCTAssertEqual(SessionRecordManager.EndPictMediaKind(fileExtension: "jpg"), .image)
        XCTAssertEqual(SessionRecordManager.EndPictMediaKind(fileExtension: "PNG"), .image)
        XCTAssertEqual(SessionRecordManager.EndPictMediaKind(fileExtension: "mp4"), .video)
        XCTAssertEqual(SessionRecordManager.EndPictMediaKind(fileExtension: "MOV"), .video)
        XCTAssertNil(SessionRecordManager.EndPictMediaKind(fileExtension: "txt"))
    }

    func testUserEndPictMediaURLsIncludeVideosInStableOrder() throws {
        let imageURL = try saveTinyImage(named: "h-100.jpg")
        let videoURL = try saveTinyVideoPlaceholder(named: "h-101.mp4")
        createdURLs.append(contentsOf: [imageURL, videoURL])

        let urls = manager.getUserEndPictMediaURLs(direction: direction)
        let names = urls.map(\.lastPathComponent)

        XCTAssertTrue(names.contains("h-100.jpg"))
        XCTAssertTrue(names.contains("h-101.mp4"))
        XCTAssertLessThan(names.firstIndex(of: "h-100.jpg")!, names.firstIndex(of: "h-101.mp4")!)
    }

    func testQueueInfoContainsUserVideoItem() throws {
        let videoURL = try saveTinyVideoPlaceholder(named: "h-queue-video.mp4")
        createdURLs.append(videoURL)

        let queueInfo = manager.getEndPictQueueInfo(direction: direction)

        XCTAssertNotNil(queueInfo)
        XCTAssertTrue(queueInfo?.items.contains(where: { $0.url?.lastPathComponent == "h-queue-video.mp4" && $0.kind == .video }) == true)
    }

    func testVideoFirstConfigPutsVideoAtFrontOfPlaybackQueue() throws {
        try saveConfig(videoFirst: true)
        let imageURL = try saveTinyImage(named: "h-200.jpg")
        let videoURL = try saveTinyVideoPlaceholder(named: "h-201.mp4")
        createdURLs.append(contentsOf: [imageURL, videoURL])
        manager.resetEndPictQueue(direction: direction)

        let queueInfo = manager.getEndPictQueueInfo(direction: direction)
        let firstIndex = try XCTUnwrap(queueInfo?.queue.first)
        let firstItem = try XCTUnwrap(queueInfo?.items[firstIndex])

        XCTAssertEqual(firstItem.kind, .video)
    }

    private func saveTinyImage(named fileName: String) throws -> URL {
        let url = userDirectionDirectory().appendingPathComponent(fileName)
        let image = UIImage(systemName: "photo") ?? UIImage()
        let data = image.pngData() ?? Data([0x89, 0x50, 0x4E, 0x47])
        try data.write(to: url)
        return url
    }

    private func saveTinyVideoPlaceholder(named fileName: String) throws -> URL {
        let url = userDirectionDirectory().appendingPathComponent(fileName)
        try Data([0, 0, 0, 20, 102, 116, 121, 112, 109, 112, 52, 50]).write(to: url)
        return url
    }

    private func saveConfig(videoFirst: Bool) throws {
        let json = """
        {"sys":{"ocr_concurrent_count":8,"tts_text_max_length":10240,"endpicts_video_first":\(videoFirst)}}
        """
        try json.data(using: .utf8)?.write(to: configURL())
    }

    private func configURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("config_local.json")
    }

    private func userDirectionDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = documents.appendingPathComponent(Constants.EndPicts.userUploadDirectoryName, isDirectory: true)
            .appendingPathComponent(direction, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
