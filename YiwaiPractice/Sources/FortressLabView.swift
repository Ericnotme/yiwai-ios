import SwiftUI

extension ChessFrame: FortressFrame {
    var fortressLegalMoves: [String] { replies.map(\.code) }
}

struct FortressLabView: View {
    @State private var engine: ChessEngine?
    @State private var quiz = 0
    @State private var quizFrame: ChessFrame?
    @State private var answer: Bool?
    @State private var quizScore = 0
    @State private var challenge = false
    @State private var session: FortressSession<ChessFrame>?
    @State private var selected: String?
    @State private var promotion: [ChessMove] = []
    @State private var error: String?
    private var question: FortressQuestion { FortressQuestion.examples[quiz] }
    private var canAnswer: Bool { answer == nil && quizFrame != nil && error == nil }
    private let seedNames = ["临门升变", "从第二横线开始", "中途的边兵"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("不败空间").font(.largeTitle.bold())
                Text("先预测，再攻击。亲眼看见一个结论为什么成立，又为什么失效。")
                    .foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fortressError") }
                if !challenge { quizContent } else { challengeContent }
                DisclosureGroup("数学依据与边界") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("深色象无法攻击浅色升变格 a8。黑王在 a7、b7、a8、b8 的区域内，总有回角防守；在角落，合法走法仍在区域内。")
                        Text("如果白兵升变，黑王可立即吃掉升变子；如果白兵被吃，余下是子力不足。经典错色象边兵残局，不是标准开局和棋的证明。")
                        Text("本机棋规在三次重复或五十回合时自动判和；正式比赛中这两项通常需申诉。200 半回合练习上限不是和棋判定。")
                        Link("公开研究证据", destination: URL(string: "https://github.com/Ericnotme/weijia-open-studio/pull/3")!)
                    }.font(.subheadline).padding(.top, 8)
                }
            }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .navigationTitle("数学棋局").navigationBarTitleDisplayMode(.inline)
        .background(Palette.paper)
        .task { if engine == nil { prepare() } }
        .confirmationDialog("选择升变棋子", isPresented: Binding(get: { !promotion.isEmpty }, set: { if !$0 { promotion = [] } }), titleVisibility: .visible) {
            ForEach(promotion, id: \.code) { move in
                Button(["q":"后", "r":"车", "b":"象", "n":"马"][move.promotion] ?? move.san) { play(move.code) }
            }
            Button("取消", role: .cancel) { promotion = [] }
        }
    }
    private var quizContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预测 \(quiz + 1) / \(FortressQuestion.examples.count)").font(.caption.weight(.semibold)).foregroundStyle(Palette.sage)
            Text(question.title).font(.title2.bold())
            if let quizFrame { BoardView(frame: quizFrame, highlight: answer == nil ? [] : ["a7", "a8"]) }
            Text("黑王从 a7 到 a8，这一步合法吗？").font(.headline)
            if answer == nil {
                Button("合法") { submit(true) }.buttonStyle(.borderedProminent).disabled(!canAnswer).accessibilityIdentifier("fortressYes")
                Button("不合法") { submit(false) }.buttonStyle(.bordered).disabled(!canAnswer).accessibilityIdentifier("fortressNo")
            } else {
                Text(answer == question.expected ? "判断正确" : "看看改变结论的条件").font(.headline).accessibilityIdentifier("fortressQuizFeedback")
                Text(question.explanation)
                Button(quiz + 1 == FortressQuestion.examples.count ? "开始攻破堡垒" : "下一个局面") { next() }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier("fortressNext")
            }
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
    private var challengeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预测完成：\(quizScore) / \(FortressQuestion.examples.count)").font(.caption.weight(.semibold))
            Text("挑战：你执白，尝试攻破堡垒").font(.title2.bold())
            if let session {
                Text(seedNames[session.seed]).font(.subheadline)
                let frame = session.current.frame
                let targets = Set(frame.replies.filter { $0.from == selected }.map(\.to))
                GameBoard(frame: frame, selected: selected, targets: targets, enabled: session.canMove, tap: tap, drag: choose)
                Text(status(session)).font(.subheadline).accessibilityIdentifier("fortressStatus")
                if let reply = session.current.reply { Text("黑方按防守规则走了 \(reply)。").font(.caption).foregroundStyle(.secondary) }
                Button("悔棋（撤回一轮）") { undo() }.buttonStyle(.bordered).disabled(session.history.count <= 1).accessibilityIdentifier("fortressUndo")
                Button("重来") { start(session.seed) }.buttonStyle(.bordered).accessibilityIdentifier("fortressRestart")
                Button("换一个堡垒") { start((session.seed + 1) % FortressPolicy.seeds.count) }.buttonStyle(.bordered).accessibilityIdentifier("fortressChangeSeed")
            }
            Button("重新预测") { challenge = false; quiz = 0; quizScore = 0; session = nil; loadQuiz() }.buttonStyle(.bordered)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
    private func replay(_ fen: String, _ moves: [String]) throws -> ChessFrame {
        guard let engine, let frame = try engine.frames(fen: fen, moves: moves).last else { throw FortressSessionError.invalidSeed }
        return frame
    }
    private func prepare() {
        do { engine = try ChessEngine(); loadQuiz() } catch { self.error = error.localizedDescription }
    }
    private func loadQuiz() {
        answer = nil; error = nil; quizFrame = nil
        do {
            let frame = try replay(question.fen, [])
            guard question.answer(using: frame) == question.expected else { throw FortressSessionError.invalidSeed }
            quizFrame = frame
        } catch { self.error = error.localizedDescription }
    }
    private func submit(_ value: Bool) {
        guard canAnswer else { return }; answer = value
        if value == question.expected { quizScore += 1 }
    }
    private func next() {
        guard answer != nil else { return }
        if quiz + 1 < FortressQuestion.examples.count { quiz += 1; loadQuiz() }
        else { challenge = true; start(0) }
    }
    private func start(_ seed: Int) {
        selected = nil; promotion = []; error = nil
        do { session = try FortressSession(seed: seed, replay: replay) }
        catch { session = nil; self.error = error.localizedDescription }
    }
    private func status(_ session: FortressSession<ChessFrame>) -> String {
        if session.current.frame.result == "1/2-1/2" { return "本局和棋 · \(session.current.frame.reason)" }
        if session.limitReached { return "练习达到步数上限；没有宣称和棋。" }
        return "第 \(session.current.moves.count / 2 + 1) 回合 · 轮到白方"
    }
    private func tap(_ square: String) {
        guard let session, session.canMove else { return }
        if session.current.frame.pieces.contains(where: { $0.square == square && $0.color == "w" }) {
            selected = selected == square ? nil : square; return
        }
        if let selected { choose(selected, square) }
    }
    private func choose(_ from: String, _ to: String) {
        guard let session, session.canMove else { return }
        let moves = session.current.frame.replies.filter { $0.from == from && $0.to == to }
        if moves.count > 1 { promotion = moves }
        else if let move = moves.first { play(move.code) }
        else { error = "这一步不合法，请选择标记的目标格。" }
    }
    private func play(_ code: String) {
        guard var next = session else { return }
        promotion = []; error = nil
        do { try next.play(code, replay: replay); session = next; selected = nil }
        catch { self.error = error.localizedDescription }
    }
    private func undo() {
        session?.undo(); selected = nil; promotion = []; error = nil
    }
}
