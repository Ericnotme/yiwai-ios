import SwiftUI

extension ChessFrame: FortressFrame {
    var fortressLegalMoves: [String] { replies.map(\.code) }
}

struct FortressLabView: View {
    @EnvironmentObject private var progress: FortressProgressStore
    @State private var catalog: FortressCourseCatalog?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("不败空间").font(.largeTitle.bold())
                Text("四章条件课：先判断一步，再沿棋规看证据。").font(.headline)
                Text("课程比较当前这一步是否合法，不把单步结果当成整局证明。攻防挑战另用三个已验证的受限经典残局。")
                    .foregroundStyle(.secondary)
                NavigationLink { FortressChallengeView() } label: {
                    Label("直接进入攻防挑战", systemImage: "shield.lefthalf.filled").font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                }.buttonStyle(.borderedProminent).accessibilityIdentifier("fortressChallengeEntry")
                if let message = progress.errorMessage {
                    Text(message).foregroundStyle(.red).accessibilityIdentifier("fortressProgressError")
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fortressError") }
                if let catalog {
                    Text(progress.errorMessage == nil ? "已作答 \(progress.answeredCount(catalog.questions, version: catalog.version)) / \(catalog.questions.count) 题" : "进度暂不可读取，旧文件已保留")
                        .font(.headline).accessibilityIdentifier("fortressCourseProgress")
                    Text("首答和最近一次作答保存在本机。重做会标记为已见题；已作答不等于已掌握，也不是棋力评分。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(catalog.chapters.enumerated()), id: \.element.id) { index, chapter in
                        NavigationLink {
                            FortressChapterView(chapter: chapter, version: catalog.version)
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Text("第 \(index + 1) 章 · \(chapter.questions.count) 题").font(.caption.weight(.semibold)).foregroundStyle(Palette.sage)
                                Text(chapter.title).font(.title3.bold()).foregroundStyle(Palette.ink)
                                Text(chapter.summary).font(.subheadline).foregroundStyle(.secondary)
                                Text("已作答 \(progress.answeredCount(chapter.questions, version: catalog.version)) / \(chapter.questions.count)")
                                    .font(.caption.weight(.semibold)).foregroundStyle(Palette.sage)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                                .background(.white, in: RoundedRectangle(cornerRadius: 18))
                        }.accessibilityIdentifier("fortressChapter-\(chapter.id)")
                    }
                } else if error == nil { ProgressView("正在核验本地课程…") }
                FortressBoundaryView()
            }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Palette.paper).navigationTitle("不败空间").navigationBarTitleDisplayMode(.inline)
        .task {
            guard catalog == nil, error == nil else { return }
            do { let loaded = try FortressCourseCatalog.load(); try loaded.validate(using: ChessEngine()); catalog = loaded }
            catch { self.error = error.localizedDescription }
        }
    }
}

private struct FortressChapterView: View {
    let chapter: FortressCourseChapter
    let version: Int
    @EnvironmentObject private var progress: FortressProgressStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(chapter.title).font(.largeTitle.bold())
                Text(chapter.summary).foregroundStyle(.secondary)
                Text("已作答 \(progress.answeredCount(chapter.questions, version: version)) / \(chapter.questions.count) 题")
                    .font(.headline).accessibilityIdentifier("fortressChapterProgress")
                ForEach(Array(chapter.questions.enumerated()), id: \.element.id) { index, question in
                    NavigationLink {
                        FortressCourseQuestionView(question: question, version: version)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(index + 1). \(question.title)").font(.headline).foregroundStyle(Palette.ink)
                            Text(question.prompt).font(.subheadline).foregroundStyle(.secondary)
                            Text(progress.entry(for: question, version: version) == nil ? "尚未作答" : "已作答 · 可回看或重做")
                                .font(.caption).foregroundStyle(Palette.sage)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                            .background(.white, in: RoundedRectangle(cornerRadius: 18))
                    }.accessibilityIdentifier("fortressQuestion-\(question.id)")
                }
                NavigationLink("进入三局攻防挑战") { FortressChallengeView() }
                    .frame(minHeight: 44).accessibilityIdentifier("fortressChapterChallenge")
            }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Palette.paper).navigationTitle("条件课程").navigationBarTitleDisplayMode(.inline)
    }
}

private struct FortressCourseQuestionView: View {
    let question: FortressCourseQuestion
    let version: Int
    @EnvironmentObject private var progress: FortressProgressStore
    @State private var evaluation: FortressCourseEvaluation?
    @State private var answer: Bool?
    @State private var showAfter = false
    @State private var redoing = false
    @State private var error: String?
    @State private var saveError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(question.title).font(.title.bold())
                Text(question.prompt).font(.headline).accessibilityIdentifier("fortressQuestionPrompt")
                Text("候选着：\(question.candidateLabel)").font(.subheadline).foregroundStyle(Palette.sage)
                if redoing { Text("重做已见题：首答保留，这次作答不计作首次表现。").font(.caption).foregroundStyle(.secondary) }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fortressError") }
                if let evaluation {
                    if answer != nil {
                        Picker("棋规证据步骤", selection: $showAfter) {
                            Text("走之前").tag(false)
                            Text(evaluation.candidateIsLegal ? "走之后" : "合法对照").tag(true)
                        }.pickerStyle(.segmented).accessibilityIdentifier("fortressEvidenceStep")
                    }
                    BoardView(frame: showAfter && answer != nil ? evaluation.after : evaluation.before, highlight: question.highlight)
                        .accessibilityIdentifier("fortressCourseBoard")
                    if answer == nil {
                        Button("合法") { submit(true, evaluation: evaluation) }
                            .buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("fortressYes")
                        Button("不合法") { submit(false, evaluation: evaluation) }
                            .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("fortressNo")
                    } else {
                        Text(answer == evaluation.candidateIsLegal ? "判断正确 · 这一步\(evaluation.candidateIsLegal ? "合法" : "不合法")" : "需要重新检查条件 · 这一步\(evaluation.candidateIsLegal ? "合法" : "不合法")")
                            .font(.headline).accessibilityIdentifier("fortressQuizFeedback")
                        Text(question.explanation).accessibilityIdentifier("fortressExplanation")
                        Text(evaluation.candidateIsLegal
                             ? "走后局面执行的是候选着 \(evaluation.evidenceMove.code)（\(evaluation.evidenceMove.san)）。"
                             : "候选着不合法，不生成非法的走后局面。此处另外演示一条合法着 \(evaluation.evidenceMove.code)（\(evaluation.evidenceMove.san)），只作棋规对照，不是最佳着推荐。")
                            .font(.subheadline).accessibilityIdentifier("fortressEvidenceMove")
                        Text(showAfter ? "走后：\(evaluation.after.result == "*" ? "棋局仍在继续" : evaluation.after.reason)" : "当前显示走之前的原局面")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("fortressEvidencePosition")
                        Text("只验证这一步及其局面变化；单步合法、不合法或一次作答，都不等于整局胜负证明、掌握程度或 Elo 提升。")
                            .font(.caption).foregroundStyle(.secondary)
                        if let row = progress.entry(for: question, version: version) {
                            Text("首答：\(row.firstAnswer.choice ? "合法" : "不合法")；最近：\(row.latestAnswer.choice ? "合法" : "不合法")；已作答 \(row.attempts) 次")
                                .font(.caption).accessibilityIdentifier("fortressSavedAnswer")
                        }
                        Button("重新作答（首答保留）") { answer = nil; showAfter = false; redoing = true; saveError = nil }
                            .buttonStyle(.bordered).frame(minHeight: 44).accessibilityIdentifier("fortressRedo")
                    }
                }
                if let saveError { Text(saveError).foregroundStyle(.red).accessibilityIdentifier("fortressSaveError") }
                NavigationLink("进入三局攻防挑战") { FortressChallengeView() }.frame(minHeight: 44)
            }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Palette.paper).navigationTitle("一步与条件").navigationBarTitleDisplayMode(.inline)
        .task {
            guard evaluation == nil, error == nil else { return }
            do {
                evaluation = try FortressCourseEvaluation(question: question, engine: ChessEngine())
                answer = progress.entry(for: question, version: version)?.latestAnswer.choice
            } catch { self.error = error.localizedDescription }
        }
    }

    private func submit(_ value: Bool, evaluation: FortressCourseEvaluation) {
        guard answer == nil else { return }
        answer = value; showAfter = false
        do { try progress.record(question: question, version: version, choice: value, legalAnswer: evaluation.candidateIsLegal); saveError = nil }
        catch { saveError = error.localizedDescription }
    }
}

private struct FortressBoundaryView: View {
    var body: some View {
        DisclosureGroup("攻防挑战的数学依据与边界") {
            VStack(alignment: .leading, spacing: 10) {
                Text("课程中的 16 题比较单步棋规，有些刻意改变象色、行棋方、角落或额外子力，不都属于下述防守条件。")
                Text("攻防挑战只使用三个已验证的白方 a 线边兵、深色象起点。深色象无法攻击浅色升变格 a8；在相应受限条件下，黑王按角落防守规则行动。没有把课程中的其他局面加入此防守器。")
                Text("如果白兵升变，黑王可立即吃掉升变子；如果白兵被吃，余下是子力不足。经典错色象边兵残局，不是标准开局和棋的证明。")
                Text("本机棋规在三次重复或五十回合时自动判和；正式比赛中这两项通常需申诉。200 半回合练习上限不是和棋判定。")
                Link("公开研究证据", destination: URL(string: "https://github.com/Ericnotme/weijia-open-studio/pull/3")!)
            }.font(.subheadline).padding(.top, 8)
        }
    }
}

private struct FortressChallengeView: View {
    @State private var engine: ChessEngine?
    @State private var session: FortressSession<ChessFrame>?
    @State private var selected: String?
    @State private var promotion: [ChessMove] = []
    @State private var error: String?
    private let seedNames = ["临门升变", "从第二横线开始", "中途的边兵"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("攻防挑战").font(.largeTitle.bold())
                Text("三个受限经典残局：你执白，尝试攻破按规则防守的堡垒。无需先答完课程。")
                    .foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fortressError") }
                if let session {
                    Text(seedNames[session.seed]).font(.title2.bold())
                    let frame = session.current.frame
                    let targets = Set(frame.replies.filter { $0.from == selected }.map(\.to))
                    GameBoard(frame: frame, selected: selected, targets: targets, enabled: session.canMove, tap: tap, drag: choose)
                    Text(status(session)).font(.subheadline).accessibilityIdentifier("fortressStatus")
                    if let reply = session.current.reply { Text("黑方按防守规则走了 \(reply)。").font(.caption).foregroundStyle(.secondary) }
                    Button("悔棋（撤回一轮）") { undo() }.buttonStyle(.bordered).disabled(session.history.count <= 1).accessibilityIdentifier("fortressUndo")
                    Button("重来") { start(session.seed) }.buttonStyle(.bordered).accessibilityIdentifier("fortressRestart")
                    Button("换一个堡垒") { start((session.seed + 1) % FortressPolicy.seeds.count) }.buttonStyle(.bordered).accessibilityIdentifier("fortressChangeSeed")
                }
                FortressBoundaryView()
            }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Palette.paper).navigationTitle("残局攻防").navigationBarTitleDisplayMode(.inline)
        .task {
            guard engine == nil else { return }
            do { engine = try ChessEngine(); start(0) } catch { self.error = error.localizedDescription }
        }
        .confirmationDialog("选择升变棋子", isPresented: Binding(get: { !promotion.isEmpty }, set: { if !$0 { promotion = [] } }), titleVisibility: .visible) {
            ForEach(promotion, id: \.code) { move in Button(["q":"后", "r":"车", "b":"象", "n":"马"][move.promotion] ?? move.san) { play(move.code) } }
            Button("取消", role: .cancel) { promotion = [] }
        }
    }
    private func replay(_ fen: String, _ moves: [String]) throws -> ChessFrame {
        guard let engine, let frame = try engine.frames(fen: fen, moves: moves).last else { throw FortressSessionError.invalidSeed }
        return frame
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
        if session.current.frame.pieces.contains(where: { $0.square == square && $0.color == "w" }) { selected = selected == square ? nil : square; return }
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
    private func undo() { session?.undo(); selected = nil; promotion = []; error = nil }
}
