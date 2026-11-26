import Foundation

struct FortressCourseQuestion: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let prompt: String
    let fen: String
    let candidateUCI: String
    let highlight: [String]
    let explanation: String
    let expectedLegal: Bool

    var candidateLabel: String {
        let squares = Array(candidateUCI)
        guard squares.count >= 4 else { return candidateUCI }
        let suffix = squares.count == 5 ? " · 升" + (["q":"后", "r":"车", "b":"象", "n":"马"][String(squares[4])] ?? "") : ""
        return String(squares[0...1]) + " → " + String(squares[2...3]) + suffix
    }
}

struct FortressCourseChapter: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let questions: [FortressCourseQuestion]
}

struct FortressCourseCatalog: Codable, Equatable {
    let version: Int
    let chapters: [FortressCourseChapter]
    var questions: [FortressCourseQuestion] { chapters.flatMap(\.questions) }

    static func load(bundle: Bundle = .main) throws -> Self {
        guard let file = bundle.url(forResource: "fortress-course-v1", withExtension: "json") else {
            throw ChessFailure.invalid("缺少本地不败空间课程，无法加载。")
        }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: file))
        guard value.version > 0, value.chapters.count == 4,
              value.chapters.allSatisfy({ $0.questions.count == 4 }),
              Set(value.chapters.map(\.id)).count == value.chapters.count,
              Set(value.questions.map(\.id)).count == value.questions.count else {
            throw ChessFailure.invalid("不败空间课程结构不完整，已停止加载。")
        }
        return value
    }

    func validate(using engine: ChessEngine) throws {
        for chapter in chapters {
            guard !chapter.id.isEmpty, !chapter.title.isEmpty, !chapter.summary.isEmpty else {
                throw ChessFailure.invalid("课程章节说明不完整。")
            }
            for question in chapter.questions { _ = try FortressCourseEvaluation(question: question, engine: engine) }
        }
    }
}

/// The bundled move engine decides legality. Incorrect candidates are never
/// rendered as if they were legal; their comparison uses an actual legal reply.
struct FortressCourseEvaluation {
    let before: ChessFrame
    let after: ChessFrame
    let candidateIsLegal: Bool
    let evidenceMove: ChessMove

    init(question: FortressCourseQuestion, engine: ChessEngine) throws {
        guard !question.id.isEmpty, !question.title.isEmpty, !question.prompt.isEmpty,
              !question.explanation.isEmpty,
              question.candidateUCI.range(of: "^[a-h][1-8][a-h][1-8][qrbn]?$", options: .regularExpression) != nil,
              question.highlight.allSatisfy({ $0.range(of: "^[a-h][1-8]$", options: .regularExpression) != nil }),
              let start = try engine.frames(fen: question.fen).last,
              start.result == "*", !start.replies.isEmpty else {
            throw ChessFailure.invalid("本题局面或候选着无效，已停止作答。")
        }
        let candidate = start.replies.first { $0.code == question.candidateUCI }
        let legal = candidate != nil
        guard legal == question.expectedLegal, let move = candidate ?? start.replies.first,
              let end = try engine.frames(fen: question.fen, moves: [move.code]).last else {
            throw ChessFailure.invalid("本题说明与本机棋规不一致，已停止作答。")
        }
        before = start; after = end; candidateIsLegal = legal; evidenceMove = move
    }
}
