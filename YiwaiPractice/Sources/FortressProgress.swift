import Foundation
import Combine

struct FortressRecordedAnswer: Codable, Equatable {
    let choice: Bool
    let correct: Bool
    let at: Date
}

struct FortressProgressEntry: Codable, Equatable {
    let catalogVersion: Int
    let question: FortressCourseQuestion
    let firstAnswer: FortressRecordedAnswer
    var latestAnswer: FortressRecordedAnswer
    var attempts: Int
    var key: String { "\(catalogVersion):\(question.id)" }
}

struct FortressProgressArchive: Codable, Equatable {
    var schemaVersion = 1
    var records: [FortressProgressEntry] = []
}

/// A separate local file. The existing game, notebook and study files are never
/// read or changed here. Commit in-memory progress only after an atomic save.
@MainActor final class FortressProgressStore: ObservableObject {
    @Published private(set) var data = FortressProgressArchive()
    @Published private(set) var errorMessage: String?
    private let file: URL
    private let clock: () -> Date
    private var readFailed = false
    private var saveFailed = false
    private var hadFile = false

    init(file: URL? = nil, clock: @escaping () -> Date = Date.init) {
        self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YiwaiPractice/fortress-progress-v1.json")
        self.clock = clock
        hadFile = FileManager.default.fileExists(atPath: self.file.path)
        do { data = try readCurrent() }
        catch { blockRead(error) }
    }

    func entry(for question: FortressCourseQuestion, version: Int) -> FortressProgressEntry? {
        data.records.first { $0.catalogVersion == version && $0.question == question }
    }

    func answeredCount(_ questions: [FortressCourseQuestion], version: Int) -> Int {
        questions.filter { entry(for: $0, version: version) != nil }.count
    }

    func record(question: FortressCourseQuestion, version: Int, choice: Bool, legalAnswer: Bool) throws {
        guard !readFailed else { throw ChessFailure.invalid(errorMessage ?? "课程记录不可读，原文件已保留。") }
        guard version > 0, legalAnswer == question.expectedLegal else { throw ChessFailure.invalid("作答与课程棋规校验不一致。") }
        var next: FortressProgressArchive
        do { next = try readCurrent() }
        catch { blockRead(error); throw ChessFailure.invalid(errorMessage!) }
        let answer = FortressRecordedAnswer(choice: choice, correct: choice == legalAnswer, at: clock())
        if let index = next.records.firstIndex(where: { $0.catalogVersion == version && $0.question.id == question.id }) {
            guard next.records[index].question == question else {
                throw ChessFailure.invalid("本题内容与已保存版本不同，旧记录已保留，暂不写入。")
            }
            guard next.records[index].attempts < 1_000_000 else { throw ChessFailure.invalid("本题记录已达到保存上限。") }
            next.records[index].latestAnswer = answer
            next.records[index].attempts += 1
        } else {
            next.records.append(.init(catalogVersion: version, question: question, firstAnswer: answer, latestAnswer: answer, attempts: 1))
        }
        do {
            try Self.validate(next)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .secondsSince1970
            try encoder.encode(next).write(to: file, options: .atomic)
            data = next; hadFile = true; saveFailed = false; errorMessage = nil
        } catch {
            saveFailed = true
            errorMessage = "这次作答未能保存，旧记录未被替换；本次答案只在当前页面显示。\(error.localizedDescription)"
            throw ChessFailure.invalid(errorMessage!)
        }
    }

    func exportArchive() throws -> FortressProgressArchive {
        guard !readFailed, !saveFailed else {
            throw ChessFailure.invalid(errorMessage ?? "不败空间记录未完整保存，不能生成完整导出。")
        }
        do {
            let current = try readCurrent()
            data = current
            return current
        } catch {
            blockRead(error)
            throw ChessFailure.invalid(errorMessage!)
        }
    }

    private func readCurrent() throws -> FortressProgressArchive {
        guard FileManager.default.fileExists(atPath: file.path) else {
            guard !hadFile else { throw ChessFailure.invalid("原课程记录文件已无法找到。") }
            return FortressProgressArchive()
        }
        let bytes = try Data(contentsOf: file)
        guard bytes.count <= 1_000_000 else { throw ChessFailure.invalid("课程记录文件超出可读取范围。") }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let archive = try decoder.decode(FortressProgressArchive.self, from: bytes)
        try Self.validate(archive)
        return archive
    }

    private static func validate(_ archive: FortressProgressArchive) throws {
        guard archive.schemaVersion == 1, archive.records.count <= 1_000,
              Set(archive.records.map(\.key)).count == archive.records.count,
              archive.records.allSatisfy({ row in
                  row.catalogVersion > 0 && !row.question.id.isEmpty && (1...1_000_000).contains(row.attempts)
                  && row.firstAnswer.correct == (row.firstAnswer.choice == row.question.expectedLegal)
                  && row.latestAnswer.correct == (row.latestAnswer.choice == row.question.expectedLegal)
                  && row.firstAnswer.at.timeIntervalSince1970.isFinite && row.latestAnswer.at.timeIntervalSince1970.isFinite
              }) else { throw ChessFailure.invalid("课程记录格式无法核验。") }
    }

    private func blockRead(_ error: Error) {
        readFailed = true
        errorMessage = "不败空间进度读取失败，原文件已保留。已停止写入和完整导出，请先保留 App 数据再排查。\(error.localizedDescription)"
    }
}
