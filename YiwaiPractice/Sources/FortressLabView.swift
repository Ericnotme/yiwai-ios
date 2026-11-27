import SwiftUI

extension ChessFrame: FortressFrame {
    var fortressLegalMoves: [String] { replies.map(\.code) }
}

struct FortressLabView: View {
    @EnvironmentObject private var progress: FortressProgressStore
    @State private var catalog: FortressCourseCatalog?
    @State private var error: String?
    private let invitations = ["象走哪种格，王又能走到哪里。", "多一枚棋子，这一步还成立吗？", "升变之后，别忘了看看谁在保护。", "换个角落，重新检查刚才的判断。"]
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:26) {
                VStack(alignment:.leading,spacing:12) {
                    YiwaiEyebrow(text:"四章小课 · 十六道判断题")
                    Text("换个角度，\n再看这一步。")
                        .font(.system(.largeTitle,design:.serif).weight(.regular)).lineSpacing(4)
                        .fixedSize(horizontal:false,vertical:true)
                    Text("先看看一步棋成立的条件，\n再到残局里，亲手试试。")
                        .font(.body).foregroundStyle(Palette.muted).lineSpacing(4)
                }.padding(.top,12)
                if let message = progress.errorMessage {
                    Text(message).foregroundStyle(.red).accessibilityIdentifier("fortressProgressError")
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fortressError") }
                if let catalog {
                    let answered = progress.answeredCount(catalog.questions,version:catalog.version)
                    VStack(alignment:.leading,spacing:10) {
                        Text(progress.errorMessage == nil ? "已作答 \(answered) / \(catalog.questions.count) 题" : "进度暂不可读取，旧文件已保留")
                            .font(.subheadline.weight(.medium)).accessibilityIdentifier("fortressCourseProgress")
                        if progress.errorMessage == nil {
                            ProgressView(value:Double(answered),total:Double(catalog.questions.count))
                                .tint(Palette.sage).accessibilityHidden(true)
                            Text(answered == 0 ? "从第一章开始，或挑一章感兴趣的。" : "不用赶进度，上次留下的判断还在这里。")
                                .font(.caption).foregroundStyle(Palette.muted)
                        }
                    }
                    VStack(spacing:0) {
                        ForEach(Array(catalog.chapters.enumerated()),id:\.element.id) { index, chapter in
                            if index > 0 { Divider().overlay(Palette.rule) }
                            NavigationLink { FortressChapterView(chapter:chapter,version:catalog.version) } label: {
                                HStack(alignment:.top,spacing:16) {
                                    Text(String(format:"%02d",index+1))
                                        .font(.system(.title2,design:.serif)).foregroundStyle(Palette.coral)
                                        .frame(minWidth:32,alignment:.leading).accessibilityHidden(true)
                                    VStack(alignment:.leading,spacing:8) {
                                        Text(chapter.title).font(.headline.weight(.medium)).foregroundStyle(Palette.ink)
                                        Text(invitations[index % invitations.count]).font(.subheadline).foregroundStyle(Palette.muted)
                                        Text("已作答 \(progress.answeredCount(chapter.questions,version:catalog.version)) / \(chapter.questions.count)")
                                            .font(.caption).foregroundStyle(Palette.sage)
                                    }.fixedSize(horizontal:false,vertical:true)
                                    Spacer(minLength:0)
                                    Image(systemName:"chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Palette.muted).padding(.top,5)
                                }.multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,20).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("fortressChapter-\(chapter.id)")
                        }
                    }.padding(.horizontal,20).background(Palette.surface,in:RoundedRectangle(cornerRadius:20))
                        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Palette.rule.opacity(0.65),lineWidth:0.7))
                } else if error == nil { ProgressView("正在打开课程…") }
                NavigationLink { FortressChallengeView() } label: {
                    YiwaiLinkRow(title:"把想法走出来",detail:"三个经典残局，随时可以开始攻防。",symbol:"shield.lefthalf.filled")
                }.buttonStyle(.plain).yiwaiSurface().accessibilityIdentifier("fortressChallengeEntry")
                DisclosureGroup("关于课程与作答记录") {
                    Text("这 16 题比较当前一步是否合法，不把单步结果当成整局证明。第一次与最近一次判断都保存在本机，重做不会覆盖首答。作答进度不是掌握程度，也不是棋力评分。")
                        .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4).padding(.top,8)
                }.font(.subheadline).tint(Palette.sage)
                FortressBoundaryView()
            }.padding(.horizontal,24).padding(.bottom,28).frame(maxWidth:640).frame(maxWidth:.infinity)
        }.background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle("不败空间").navigationBarTitleDisplayMode(.inline)
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
            VStack(alignment:.leading,spacing:24) {
                VStack(alignment:.leading,spacing:12) {
                    YiwaiEyebrow(text:"一次看清一个细节")
                    Text(chapter.title).font(.system(.largeTitle,design:.serif).weight(.regular))
                    Text(chapter.summary).font(.body).foregroundStyle(Palette.muted).lineSpacing(4)
                    Text("已作答 \(progress.answeredCount(chapter.questions,version:version)) / \(chapter.questions.count) 题")
                        .font(.caption.weight(.medium)).foregroundStyle(Palette.sage).accessibilityIdentifier("fortressChapterProgress")
                }.padding(.top,12)
                VStack(spacing:0) {
                    ForEach(Array(chapter.questions.enumerated()),id:\.element.id) { index, question in
                        if index > 0 { Divider().overlay(Palette.rule) }
                        NavigationLink { FortressCourseQuestionView(question:question,version:version) } label: {
                            HStack(alignment:.top,spacing:14) {
                                Text(String(format:"%02d",index+1)).font(.system(.title3,design:.serif)).foregroundStyle(Palette.coral).accessibilityHidden(true)
                                VStack(alignment:.leading,spacing:8) {
                                    Text(question.title).font(.body.weight(.medium)).foregroundStyle(Palette.ink)
                                    Text(progress.entry(for:question,version:version) == nil ? "想一想，再看证据" : "已作答 · 回看或再试一次")
                                        .font(.caption).foregroundStyle(Palette.muted)
                                }.fixedSize(horizontal:false,vertical:true)
                                Spacer(minLength:0)
                                Image(systemName:"chevron.right").font(.caption2).foregroundStyle(Palette.muted).padding(.top,5)
                            }.multilineTextAlignment(.leading).frame(maxWidth:.infinity,minHeight:54,alignment:.leading).padding(.vertical,18).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("fortressQuestion-\(question.id)")
                    }
                }.padding(.horizontal,20).background(Palette.surface,in:RoundedRectangle(cornerRadius:20))
                    .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Palette.rule.opacity(0.65),lineWidth:0.7))
                NavigationLink("想动手试试？进入攻防挑战") { FortressChallengeView() }
                    .font(.subheadline).foregroundStyle(Palette.sage).frame(minHeight:44).accessibilityIdentifier("fortressChapterChallenge")
            }.padding(.horizontal,24).padding(.bottom,28).frame(maxWidth:640).frame(maxWidth:.infinity)
        }.background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle("条件课程").navigationBarTitleDisplayMode(.inline)
    }
}

private struct FortressCourseQuestionView: View {
    let question: FortressCourseQuestion
    let version: Int
    @EnvironmentObject private var progress: FortressProgressStore
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var evaluation: FortressCourseEvaluation?
    @State private var answer: Bool?
    @State private var showAfter = false
    @State private var redoing = false
    @State private var error: String?
    @State private var saveError: String?
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:12) {
                    YiwaiEyebrow(text:answer == nil ? "先留下自己的判断" : "回到棋盘，看清原因")
                    Text(question.title).font(.system(.title,design:.serif).weight(.medium))
                    Text(question.prompt).font(.body).lineSpacing(4).accessibilityIdentifier("fortressQuestionPrompt")
                    Text("候选着：\(question.candidateLabel)")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Palette.sage)
                    if redoing { Text("这题已经见过。第一次的判断会保留，也可以再作一次判断。")
                        .font(.caption).foregroundStyle(Palette.muted) }
                }.padding(.top,12)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fortressError") }
                if let evaluation {
                    VStack(spacing:14) {
                        if answer != nil {
                            Picker("棋规证据步骤",selection:$showAfter) {
                                Text("走之前").tag(false)
                                Text(evaluation.candidateIsLegal ? "走之后" : "合法对照").tag(true)
                            }.pickerStyle(.segmented).accessibilityIdentifier("fortressEvidenceStep")
                        }
                        BoardView(frame:showAfter && answer != nil ? evaluation.after : evaluation.before,highlight:question.highlight)
                            .accessibilityIdentifier("fortressCourseBoard")
                    }.padding(12).background(Palette.surface,in:RoundedRectangle(cornerRadius:20))
                        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(Palette.rule.opacity(0.65),lineWidth:0.7))
                    if answer == nil {
                        let layout = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:12)) : AnyLayout(HStackLayout(spacing:12))
                        layout {
                            Button("合法") { submit(true,evaluation:evaluation) }.accessibilityIdentifier("fortressYes")
                            Button("不合法") { submit(false,evaluation:evaluation) }.accessibilityIdentifier("fortressNo")
                        }.buttonStyle(YiwaiActionStyle(primary:false))
                        Text("不必急着选，先留意棋子之间的位置。")
                            .font(.caption).foregroundStyle(Palette.muted)
                    } else {
                        VStack(alignment:.leading,spacing:16) {
                            HStack(alignment:.top,spacing:10) {
                                Image(systemName:answer == evaluation.candidateIsLegal ? "checkmark.circle" : "arrow.turn.up.left")
                                    .foregroundStyle(answer == evaluation.candidateIsLegal ? Palette.sage : Palette.coral)
                                Text(answer == evaluation.candidateIsLegal ? "判断正确 · 这一步\(evaluation.candidateIsLegal ? "合法" : "不合法")" : "再看一处细节 · 这一步\(evaluation.candidateIsLegal ? "合法" : "不合法")")
                                    .font(.headline).accessibilityIdentifier("fortressQuizFeedback")
                            }
                            Text(question.explanation).font(.body).lineSpacing(5).accessibilityIdentifier("fortressExplanation")
                            Divider().overlay(Palette.rule)
                            YiwaiEyebrow(text:"棋盘上的证据")
                            Text(evaluation.candidateIsLegal
                                 ? "走后局面执行的是候选着 \(evaluation.evidenceMove.code)（\(evaluation.evidenceMove.san)）。"
                                 : "候选着不合法，不生成非法的走后局面。此处另外演示一条合法着 \(evaluation.evidenceMove.code)（\(evaluation.evidenceMove.san)），只作棋规对照，不是最佳着推荐。")
                                .font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4).accessibilityIdentifier("fortressEvidenceMove")
                            Text(showAfter ? "走后：\(evaluation.after.result == "*" ? "棋局仍在继续" : evaluation.after.reason)" : "当前显示走之前的原局面")
                                .font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("fortressEvidencePosition")
                        }.yiwaiSurface()
                        if let row = progress.entry(for:question,version:version) {
                            Text("首答：\(row.firstAnswer.choice ? "合法" : "不合法")；最近：\(row.latestAnswer.choice ? "合法" : "不合法")；已作答 \(row.attempts) 次")
                                .font(.caption).foregroundStyle(Palette.muted).accessibilityIdentifier("fortressSavedAnswer")
                        }
                        Button("再想一次 · 首答会保留") { answer = nil; showAfter = false; redoing = true; saveError = nil }
                            .buttonStyle(YiwaiActionStyle(primary:false)).accessibilityIdentifier("fortressRedo")
                        Text("这里验证一步棋及其变化。一次作答不代表整局胜负、掌握程度或棋力提升。")
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                if let saveError { Text(saveError).foregroundStyle(.red).accessibilityIdentifier("fortressSaveError") }
                NavigationLink("想动手试试？进入攻防挑战") { FortressChallengeView() }
                    .font(.subheadline).foregroundStyle(Palette.sage).frame(minHeight:44)
            }.padding(.horizontal,22).padding(.bottom,28).frame(maxWidth:640).frame(maxWidth:.infinity)
        }.background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle("一步与条件").navigationBarTitleDisplayMode(.inline)
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
            }.font(.subheadline).foregroundStyle(Palette.muted).lineSpacing(4).padding(.top, 8)
        }.font(.subheadline).tint(Palette.sage)
    }
}

private struct FortressChallengeView: View {
    @State private var engine: ChessEngine?
    @State private var session: FortressSession<ChessFrame>?
    @State private var selected: String?
    @State private var promotion: [ChessMove] = []
    @State private var error: String?
    @Environment(\.dynamicTypeSize) private var textSize
    private let seedNames = ["临门升变", "从第二横线开始", "中途的边兵"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                YiwaiEyebrow(text:"把想法放到棋盘上")
                Text("轮到你，走走看。").font(.system(.title,design:.serif).weight(.regular))
                Text("你执白方，从三个经典残局里寻找突破口。黑王会按已核验的防守规则回应。")
                    .font(.body).foregroundStyle(Palette.muted).lineSpacing(4)
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("fortressError") }
                if let session {
                    Text(seedNames[session.seed]).font(.headline.weight(.medium))
                    let frame = session.current.frame
                    let targets = Set(frame.replies.filter { $0.from == selected }.map(\.to))
                    GameBoard(frame: frame, selected: selected, targets: targets, enabled: session.canMove, tap: tap, drag: choose)
                    Text(status(session)).font(.subheadline).accessibilityIdentifier("fortressStatus")
                    if let reply = session.current.reply { Text("黑方按防守规则走了 \(reply)。").font(.caption).foregroundStyle(.secondary) }
                    let actions = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing:12)) : AnyLayout(HStackLayout(spacing:12))
                    actions {
                        Button("悔棋 · 撤回一轮") { undo() }.disabled(session.history.count <= 1).accessibilityIdentifier("fortressUndo")
                        Button("重新开始") { start(session.seed) }.accessibilityIdentifier("fortressRestart")
                    }.buttonStyle(YiwaiActionStyle(primary:false))
                    Button("换一个堡垒") { start((session.seed + 1) % FortressPolicy.seeds.count) }.buttonStyle(YiwaiActionStyle(primary:false)).accessibilityIdentifier("fortressChangeSeed")
                }
                FortressBoundaryView()
            }.padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.background(Palette.paper).foregroundStyle(Palette.ink).navigationTitle("残局攻防").navigationBarTitleDisplayMode(.inline)
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
