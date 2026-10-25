// PDFLibrary.swift — 本地 PDF 文件仓库
import Foundation

@MainActor
final class PDFLibrary {
    static let shared = PDFLibrary()
    private let fm = FileManager.default
    private let dir: URL = {
        let url = AppData.root.appendingPathComponent("PDF", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private init() {}

    func has(bookId: String) -> Bool { fm.fileExists(atPath: url(bookId: bookId)?.path ?? "") }

    func url(bookId: String) -> URL? {
        let file = dir.appendingPathComponent(bookId + ".pdf")
        return fm.fileExists(atPath: file.path) ? file : nil
    }

    @discardableResult
    func save(data: Data, bookId: String) throws -> URL {
        let file = dir.appendingPathComponent(bookId + ".pdf")
        try data.write(to: file, options: .atomic)
        return file
    }
}
