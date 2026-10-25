// SourceContracts.swift — 书源引擎对应用层暴露的协议与错误
import Foundation

protocol SourceEngineProtocol: AnyObject, Sendable {
    func search(_ keyword: String, source: BookSource, page: Int) async throws -> [SourceBook]
    func bookInfo(_ book: SourceBook, source: BookSource) async throws -> SourceBookInfo
    func toc(_ info: SourceBookInfo, source: BookSource) async throws -> [SourceChapter]
    func content(_ chapter: SourceChapter, info: SourceBookInfo?, source: BookSource) async throws -> ChapterContent
    func explore(_ source: BookSource) async throws -> [SourceBook]
    func checkLogin(_ source: BookSource) async -> Bool
}

struct EngineDiagnostics: Sendable {
    var sourceName: String
    var stage: String
    var message: String
    var timestamp: Date = Date()
}
