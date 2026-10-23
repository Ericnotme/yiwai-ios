import SwiftUI

struct DecisionCapture: Identifiable { let id = UUID(); let record: GameRecord; let ply: Int; let origin: DecisionOrigin }
struct DecisionCaptureView: View {
    let capture: DecisionCapture
    @EnvironmentObject private var decisions: DecisionStore
    @Environment(\.dismiss) private var dismiss
    @State private var candidates = ""
    @State private var reason = ""
    @State private var tag: DecisionTag = .unconfirmed
    @State private var error: String?
    @FocusState private var editing: Bool
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(capture.origin.title).font(.headline).accessibilityIdentifier("decisionOrigin")
                    Text("原棋谱第 \(capture.ply) 半回合后的局面。本局最多记录两处，也可以跳过。")
                    DisclosureGroup("查看原局面") {
                        if let frame = try? ChessEngine().frames(fen:capture.record.initialFEN,moves:Array(capture.record.moves.prefix(capture.ply))).last {
                            GameBoard(frame:frame).frame(maxWidth:360)
                        }
                    }.accessibilityIdentifier("decisionBoardDisclosure")
                }
                Section("你当时考虑什么") {
                    TextField("候选着，例如 Nf3 或先检查将军",text:$candidates,axis:.vertical).lineLimit(2...4)
                        .focused($editing).accessibilityIdentifier("decisionCandidates")
                    TextEditor(text:$reason).frame(minHeight:110).focused($editing)
                        .accessibilityLabel("你自己的理由，可留空").accessibilityIdentifier("decisionReason")
                    Text("保持你的原话；不自动代写。不确定或记不清可以直接写明。").font(.caption).foregroundStyle(.secondary)
                }
                Section("由你确认的棋理标签") {
                    Picker("标签",selection:$tag) { ForEach(DecisionTag.allCases,id:\.self) { Text($0.title).tag($0) } }.accessibilityIdentifier("decisionTag")
                    Text(tag.explanation).font(.caption)
                    Text("第一版只支持这个主题；不适用时先不归类，保留理由并显示待准备。").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("decisionCaptureError") }
                    Button("保存理由，建立本地复习项") { save(skipped:false) }.accessibilityIdentifier("saveDecision").frame(minHeight:44).keyboardShortcut("s",modifiers:.command)
                    Button("这次跳过") { save(skipped:true) }.accessibilityIdentifier("skipDecision").frame(minHeight:44)
                } footer: { Text("首次复习安排在保存完成 24 小时后。可在「棋谱 → 决策回炉」提前练，但不计到期掌握。不发送提醒。若从对弈进入，记完后可手动继续对弈。") }
            }.navigationTitle("留下一处决策").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("收起键盘") { editing = false } }
            }
        }
    }
    private func save(skipped: Bool) {
        do { try decisions.record(game:capture.record,ply:capture.ply,candidates:candidates,reason:reason,origin:capture.origin,tag:tag,skipped:skipped); dismiss() }
        catch { self.error = error.localizedDescription }
    }
}

struct DecisionListView: View {
    @EnvironmentObject private var decisions: DecisionStore
    var body: some View {
        List {
            Section {
                Text("从对弈或棋谱复盘中自选最多两处，留下候选着与理由。复习时先独立落子，再看反馈。")
                Text("练习记录只描述本主题表现，不代表棋力、Elo 或人格测评。").font(.caption).foregroundStyle(.secondary)
                if let error = decisions.loadError { Text(error).foregroundStyle(.red) }
            }
            if decisions.data.items.isEmpty {
                Text("还没有待复习项。打开一盘棋，点「记录这处决策」。").accessibilityIdentifier("reforgeEmpty")
            }
            ForEach(decisions.data.items.sorted(by:{$0.dueAt < $1.dueAt})) { item in
                if let note = decisions.note(for:item) {
                    NavigationLink { DecisionDetailView(itemID:item.id) } label: {
                        VStack(alignment:.leading,spacing:6) {
                            Text(note.tag.title).font(.headline)
                            Text(note.origin.title).font(.caption)
                            Text(item.status).font(.subheadline)
                            Text(decisions.now >= item.dueAt ? "已到期" : "下次：\(item.dueAt.formatted(date:.abbreviated,time:.shortened))").font(.caption)
                        }.padding(.vertical,5)
                    }.accessibilityIdentifier("reforge-item-\(item.id)")
                }
            }
            let skipped = decisions.data.notes.filter(\.skipped)
            if !skipped.isEmpty { Section("主动跳过") { Text("\(skipped.count) 处已跳过；未替你补写理由，也不计作错误。").accessibilityIdentifier("reforgeSkipped") } }
        }.navigationTitle("决策回炉").navigationBarTitleDisplayMode(.inline)
    }
}

struct DecisionDetailView: View {
    let itemID: UUID
    @EnvironmentObject private var decisions: DecisionStore
    @EnvironmentObject private var game: GameController
    @State private var sessionID: UUID?
    @State private var showingSession = false
    @State private var error: String?
    private var item: ReforgeItem? { decisions.data.items.first { $0.id == itemID } }
    var body: some View {
        ScrollView {
            if let item, let note = decisions.note(for:item) {
                VStack(alignment:.leading,spacing:16) {
                    Text("原局面与自己的理由").font(.headline)
                    Text(note.origin.title).accessibilityIdentifier("savedDecisionOrigin")
                    if let frame = try? ChessEngine().frames(fen:note.fen).first { GameBoard(frame:frame) }
                    if let evidence = note.evidence {
                        Text(evidence.explanation).accessibilityIdentifier("linkedRuleEvidence")
                        Text("这是棋规证据，与你下方主动保存的候选着、理由和记录时机分别保留。先做一道针对性练习，完成后 24 小时再用另一新局面复测。这里的白方练习与原棋谱执棋颜色无关，只针对同一将死规则。").font(.caption)
                    }
                    Text("候选着：\(note.candidates.isEmpty ? "未记录" : note.candidates)").textSelection(.enabled).accessibilityIdentifier("savedDecisionCandidates")
                    Text("理由：\(note.reason.isEmpty ? "未记录" : note.reason)").textSelection(.enabled).accessibilityIdentifier("savedDecisionReason")
                    Picker("我的棋理标签",selection:Binding(get:{note.tag},set:{tag in
                        do { try decisions.changeTag(noteID:note.id,tag:tag); error = nil } catch { self.error = error.localizedDescription }
                    })) { ForEach(DecisionTag.allCases,id:\.self) { Text($0.title).tag($0) } }.accessibilityIdentifier("correctDecisionTag")
                    Text(note.tag.explanation).font(.caption).foregroundStyle(.secondary)
                    Text(item.status).font(.headline).accessibilityIdentifier("reforgeMastery")
                    Text("下次复习：\(item.dueAt.formatted(date:.abbreviated,time:.shortened))").accessibilityIdentifier("reforgeDue")
                    Text("新题会排除本机棋谱、原有题库和已展示局面；无法识别你在其他地方看过的题。题库用完会显示待准备。").font(.caption)
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("reforgeError") }
                    if note.evidence != nil && !decisions.data.sessions.contains(where:{$0.itemID == itemID && $0.kind == "practice" && $0.finished}) {
                        Button("开始一题针对性练习") { start(practice:true) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("startTargetPractice")
                    }
                    Button(decisions.activeSession(itemID:itemID) != nil ? "继续未提交的复习" : decisions.now >= item.dueAt ? "开始到期新题" : "提前练习（不计到期掌握）") { start() }
                        .buttonStyle(.borderedProminent).frame(minHeight:44).accessibilityIdentifier("startReforge")
                    Button("重试原局面（不计新题掌握）") { start(original:true) }
                        .frame(minHeight:44).disabled(decisions.activeSession(itemID:itemID) != nil).accessibilityIdentifier("retryOriginal")
                    Text("仅当原局面本身符合一步将死主题时提供原题重试。两次到期的新题首次无提示答对后，才显示本主题已两次独立通过。").font(.caption).foregroundStyle(.secondary)
                    ForEach(decisions.data.sessions.filter { $0.itemID == itemID && $0.finished }.reversed()) { session in
                        VStack(alignment:.leading,spacing:5) {
                            Text(session.modeLabel).font(.subheadline.weight(.semibold))
                            Text(session.resultLabel)
                            Text("\(session.submittedAt!.formatted(date:.abbreviated,time:.shortened)) · \(Int(session.elapsedSeconds ?? 0)) 秒 · 题目 v\(session.puzzle.version)").font(.caption)
                            Text("首次提交：\(session.firstMove ?? "跳过")").font(.caption.monospaced())
                            Button("查看这次记录") { sessionID = session.id; showingSession = true }
                        }.frame(maxWidth:.infinity,alignment:.leading).padding().background(.white,in:RoundedRectangle(cornerRadius:12))
                    }
                }.padding(16).frame(maxWidth:560)
            }
        }.background(Palette.paper).navigationTitle("回看这处决策").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented:$showingSession) { if let sessionID { ReforgeSessionView(sessionID:sessionID) } }
    }
    private func start(original: Bool = false, practice: Bool = false) {
        do {
            if let session = try decisions.begin(itemID:itemID,games:game.capsuleRecords(),original:original,practice:practice) { sessionID = session.id; showingSession = true }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

struct ReforgeSessionView: View {
    let sessionID: UUID
    @EnvironmentObject private var decisions: DecisionStore
    @State private var frame: ChessFrame?
    @State private var selected: String?
    @State private var pending: ChessMove?
    @State private var promotions: [ChessMove] = []
    @State private var error: String?
    private var session: ReforgeSession? { decisions.session(sessionID) }
    var body: some View {
        ScrollView {
            if let session {
                VStack(alignment:.leading,spacing:14) {
                    Text(session.modeLabel).font(.headline).accessibilityIdentifier("reforgeMode")
                    Text("\(frame?.turn == "b" ? "黑" : "白")方走棋：请找一步将死。先选起点和终点，再提交。").accessibilityIdentifier("reforgePrompt")
                    if let frame { GameBoard(frame:frame,flipped:frame.turn == "b",selected:selected,enabled:!session.finished,tap:tap) }
                    if !session.finished {
                        Text(pending.map { "待提交：\($0.code)" } ?? "尚未选择走法").accessibilityIdentifier("reforgePending")
                        Button("提交首次答案") { submit() }.buttonStyle(.borderedProminent).disabled(pending == nil)
                            .frame(minHeight:44).accessibilityIdentifier("submitReforge")
                        if session.hintAt != nil {
                            Text("已使用提示，本次不计独立掌握。").font(.caption)
                            Text(session.puzzle.hint).accessibilityIdentifier("reforgeHint")
                        } else {
                            Button("查看提示（本次不计独立掌握）") {
                                do { try decisions.revealHint(sessionID:sessionID); error = nil } catch { self.error = error.localizedDescription }
                            }.frame(minHeight:44).accessibilityIdentifier("hintReforge")
                        }
                        Button("这次跳过") { submit(skipped:true) }.frame(minHeight:44).accessibilityIdentifier("skipReforge")
                        Text("提交前不显示答案、分析或变化线。退出后会保留这次题目和已用提示状态。").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(session.resultLabel).font(.headline).accessibilityIdentifier("reforgeResult")
                        if session.outcome != "skipped" {
                            Text("首次提交：\(session.firstMove ?? "")").font(.subheadline.monospaced())
                            Text("已验证答案：\(session.puzzle.answers.joined(separator:"、"))").accessibilityIdentifier("reforgeAnswers")
                            Text(session.puzzle.explanation).accessibilityIdentifier("reforgeFeedback")
                            if let move = session.firstMove, let after = try? ChessEngine().frames(fen:session.puzzle.fen,moves:[move]).last {
                                Text(after.mate ? "棋规确认：将军且没有合法应将。" : "这步之后，对方有 \(after.replies.count) 个合法走法\(after.check ? "可应将" : "，并未被将死")。")
                                if !after.replies.isEmpty { Text("例如：\(after.replies.prefix(5).map(\.san).joined(separator:"、"))").font(.caption) }
                            }
                        }
                        Text("完成时间：\(session.submittedAt!.formatted(date:.abbreviated,time:.shortened)) · 用时 \(Int(session.elapsedSeconds ?? 0)) 秒").font(.caption)
                        Text("\(session.puzzle.source)\n版本 \(session.puzzle.version) · \(session.puzzle.license)\n\(session.puzzle.validation)").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("reforgeSessionError") }
                }.padding(16).frame(maxWidth:560)
            }
        }.background(Palette.paper).navigationTitle("先独立落子").navigationBarTitleDisplayMode(.inline)
        .task {
            if let session { do { frame = try ChessEngine().frames(fen:session.puzzle.fen)[0] } catch { self.error = error.localizedDescription } }
        }
        .confirmationDialog("选择升变",isPresented:Binding(get:{!promotions.isEmpty},set:{if !$0 { promotions = [] }})) {
            ForEach(promotions,id:\.code) { move in Button(["q":"升后","r":"升车","b":"升象","n":"升马"][move.promotion] ?? "升变") { pending = move; promotions = [] } }
        }
    }
    private func tap(_ square: String) {
        guard let frame, session?.finished == false else { return }
        if let selected {
            let moves = frame.replies.filter { $0.from == selected && $0.to == square }
            if moves.count > 1 { promotions = moves; return }
            if let move = moves.first { pending = move; return }
        }
        selected = frame.pieces.contains(where:{$0.square == square && $0.color == frame.turn}) ? square : nil
        pending = nil
    }
    private func submit(skipped: Bool = false) {
        do { try decisions.submit(sessionID:sessionID,move:pending?.code,skipped:skipped); error = nil }
        catch { self.error = error.localizedDescription }
    }
}
