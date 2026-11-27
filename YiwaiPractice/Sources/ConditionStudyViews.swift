import SwiftUI

struct ConditionStudyHome:View {
    @EnvironmentObject private var study:ConditionStudyStore
    @EnvironmentObject private var game:GameController
    @EnvironmentObject private var decisions:DecisionStore
    @State private var selected:UUID?
    @State private var opening=false
    @State private var error:String?
    var body:some View {
        List {
            Section {
                Text("改变条件、发现盲区").font(.title2.weight(.semibold))
                Text("自愿参加的本机练习：三种结构各四个局面，交错呈现。比较指定吃子机会与防守关系改变时，你实际提交了什么。只涉及一步将死，也可能没有一步将死。")
                Text("这些记录只说明你提交了什么，不能完整反映你当时看到了什么。").font(.headline).accessibilityIdentifier("conditionBoundary")
                Text("可随时暂停。先提交首答；完成 12 题或主动结束后再统一看反馈。其他棋子与走法并未全部控制，记录不是注意力测量、心理诊断或棋力提升证据。")
            }
            Section {
                if study.preparing { ProgressView("核验题目证明与引擎记录…") }
                if let active=study.activeRun {
                    Button("继续本轮 · 已提交 \(active.completedCount)/\(active.trials.count)") { open(active.id) }.disabled(study.preparing).accessibilityIdentifier("resumeConditionStudy")
                } else {
                    Button("开始 12 题本机练习") { start(demo:false) }.disabled(study.positions.filter{$0.family != "transfer"}.count != 12).accessibilityIdentifier("startConditionStudy")
                    Button("演示模式（不纳入比较）") { start(demo:true) }.disabled(study.positions.filter{$0.family != "transfer"}.count != 12).accessibilityIdentifier("startConditionDemo")
                    Text("演示也会留下已展示局面的标记，以后不能再把它们算作本机新题。可直接开始正式练习，不需要先演示。").font(.caption)
                }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("conditionHomeError") }
                if let message=study.loadError { Text(message).foregroundStyle(.red) }
                ForEach(study.issues,id:\.self) { Text("暂不可用：\($0)").font(.caption) }
            }
            Section("本机记录与到期复测") {
                ForEach(study.data.runs.filter{$0.feedbackAt != nil}.reversed()) { run in
                    VStack(alignment:.leading,spacing:10) {
                        Button("\(run.demonstration ? "演示" : run.phase=="transfer" ? "延时复测" : "条件练习") · \(run.completedCount)/\(run.trials.count) 项已提交") { open(run.id) }.frame(minHeight:44)
                        Text(run.startedAt,format:.dateTime.month().day().hour().minute()).font(.caption)
                        if run.phase=="comparison", let due=run.transferDueAt {
                            Text("延时新题可开始：\(due.formatted(date:.abbreviated,time:.shortened))").font(.caption)
                            Button(study.data.runs.contains(where:{$0.sourceRunID==run.id}) ? "查看已有延时复测" : "开始 4 题延时复测") {
                                do { open(try study.startTransfer(sourceID:run.id,seed:UInt64.random(in:0...UInt64.max),known:known())) }
                                catch { self.error=error.localizedDescription }
                            }.frame(minHeight:44).accessibilityIdentifier("startConditionTransfer")
                        }
                    }.padding(.vertical,8).buttonStyle(.borderless)
                }
                Text("延时复测按本轮实际结束时间 +24 小时安排，共四个本机未记录、未展示的局面。不会请求通知权限。题库不满足条件时显示待准备。")
            }
        }.navigationTitle("条件对照 · 实验").navigationBarTitleDisplayMode(.inline)
        .task { await study.prepare() }
        .navigationDestination(isPresented:$opening) { if let selected { ConditionRunView(runID:selected) } }
    }
    private func open(_ id:UUID) { selected=id;opening=true }
    private func start(demo:Bool) { do { open(try study.start(seed:UInt64.random(in:0...UInt64.max),demonstration:demo)) } catch { self.error=error.localizedDescription } }
    private func known() throws -> Set<String> { try ReforgeRules().knownKeys(games:game.capsuleRecords(),notes:decisions.data.notes,seen:decisions.data.seen) }
}
struct ConditionRunView:View {
    let runID:UUID
    @EnvironmentObject private var study:ConditionStudyStore
    @EnvironmentObject private var game:GameController
    @EnvironmentObject private var decisions:DecisionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var error:String?
    @State private var confirmEnd=false
    private var run:ConditionRun? { study.run(runID) }
    var body:some View {
        Group {
            if let run {
                if run.feedbackAt != nil { ConditionFeedbackView(runID:runID) }
                else if run.paused {
                    VStack(spacing:18) { Text("已暂停，未展示反馈").font(.headline);Button("恢复本题") { perform { try study.pause(runID,resume:true);try present() } }.buttonStyle(.borderedProminent).accessibilityIdentifier("resumeConditionTrial");Button("返回列表") { dismiss() } }
                } else if let trial=run.current, trial.shownAt != nil {
                    ConditionTrialView(runID:runID,trial:trial,onSubmitted:next).id(trial.id)
                } else { ProgressView("准备下一局面…").task { perform { try present() } } }
            }
        }
        .navigationTitle(run?.demonstration==true ? "演示作答" : run?.phase=="transfer" ? "延时复测" : "先独立作答").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge:.bottom) {
            if run?.feedbackAt==nil {
                VStack(spacing:8) {
                    if let error { Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("conditionRunError") }
                    HStack { Button("暂停并返回") { perform { try study.pause(runID);dismiss() } }.accessibilityIdentifier("pauseConditionStudy");Spacer();Button("结束并查看反馈") { confirmEnd=true }.accessibilityIdentifier("endConditionStudy") }
                }.padding(12).background(.regularMaterial)
            }
        }
        .alert("结束本轮并查看反馈？",isPresented:$confirmEnd) {
            Button("继续作答",role:.cancel) { }
            Button("结束并查看") { perform { try study.finish(runID,expose:decisions.recordExposure) } }
        } message: { Text("未提交的题保持未提交，不算答错。反馈会暴露本组其余局面；之后相关题不能计入首次独立比较。") }
        .task(id:run?.current?.id) { if run?.feedbackAt==nil && run?.paused==false { perform { try present() } } }
        .onDisappear { try? study.pause(runID) }
        .onChange(of:scenePhase) { _,phase in if phase != .active { try? study.pause(runID) } }
    }
    private func perform(_ action:()throws->Void) { do { try action();error=nil } catch { self.error=error.localizedDescription } }
    private func present() throws {
        let known=try ReforgeRules().knownKeys(games:game.capsuleRecords(),notes:decisions.data.notes,seen:decisions.data.seen)
        _=try study.present(runID:runID,known:known,expose:decisions.recordExposure)
    }
    private func next() { if let run,run.current==nil { perform { try study.finish(runID,expose:decisions.recordExposure) } } }
}
private struct ConditionTrialView:View {
    let runID:UUID;let trial:ConditionTrial;let onSubmitted:()->Void
    @EnvironmentObject private var study:ConditionStudyStore
    @State private var frame:ChessFrame?
    @State private var selected:String?
    @State private var choice:String?
    @State private var promotions:[ChessMove]=[]
    @State private var candidates=""
    @State private var threat=""
    @State private var notesExpanded=false
    @State private var error:String?
    private enum InputField:Hashable { case candidates,threat }
    @FocusState private var editing:InputField?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:16) {
                if let run=study.run(runID) {
                    Text("\(run.demonstration ? "演示 · " : "")第 \(run.completedCount+1) / \(run.trials.count) 题").font(.headline).accessibilityIdentifier("conditionProgress")
                    if run.demonstration { Text("示例记录，不纳入个人条件比较。").font(.caption) }
                }
                Text("\(frame?.turn=="b" ? "黑" : "白")方走：请选择一步将死的走法，或判断没有一步将死。").accessibilityIdentifier("conditionQuestion")
                if let frame { GameBoard(frame:frame,flipped:frame.turn=="b",selected:selected,enabled:true,tap:tap) }
                Text(choice=="none" ? "待提交：没有一步将死" : choice.map{"待提交：\($0)"} ?? "尚未选择答案").accessibilityIdentifier("conditionPending")
                Button("没有一步将死") { choice="none";selected=nil }.buttonStyle(.bordered).frame(minHeight:44).accessibilityIdentifier("conditionNoMate")
                Button { notesExpanded.toggle() } label: { Label("可选：我考虑的候选着与威胁",systemImage:notesExpanded ? "chevron.down":"chevron.right").frame(minHeight:44) }
                    .accessibilityValue(notesExpanded ? "已展开":"已收起").accessibilityIdentifier("conditionOptionalNotes")
                if notesExpanded {
                    TextField("候选着（可空）",text:$candidates,axis:.vertical).lineLimit(1...3).textFieldStyle(.roundedBorder).frame(minHeight:44).focused($editing,equals:.candidates).accessibilityIdentifier("conditionCandidates")
                    TextField("我注意到的威胁（可空）",text:$threat,axis:.vertical).lineLimit(1...3).textFieldStyle(.roundedBorder).frame(minHeight:44).focused($editing,equals:.threat).accessibilityIdentifier("conditionThreat")
                    Text("这是自述，不是注意力测量；没有写不等于没看见。").font(.caption)
                    Button("标记：我已见过此题或参考了外部提示") { perform { try study.markAssisted(runID:runID,trialID:trial.id) } }.accessibilityIdentifier("conditionAssisted")
                }
                Button("提交首答并继续") {
                    perform { try study.draft(runID:runID,trialID:trial.id,candidates:candidates,threat:threat);try study.submit(runID:runID,trialID:trial.id,submissionID:trial.submissionID,choice:choice!);onSubmitted() }
                }.buttonStyle(.borderedProminent).frame(minHeight:44).disabled(choice==nil).accessibilityIdentifier("submitConditionAnswer").keyboardShortcut(.return,modifiers:.command)
                Text("提交后保留首次答案，暂不显示对错、评分或变化线。全部提交或主动结束后统一看反馈。").font(.caption)
                if !trial.exclusions.isEmpty { Text("本题排除原因：\(trial.exclusions.joined(separator:"；"))").font(.caption) }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("conditionAnswerError") }
            }.padding(16).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(Palette.paper)
        .task { candidates=trial.candidates;threat=trial.threat;do { frame=try ChessEngine().frames(fen:trial.position.fen)[0] } catch { self.error=error.localizedDescription } }
        .onChange(of:candidates) { _,_ in saveDraft() }.onChange(of:threat) { _,_ in saveDraft() }
        .toolbar { ToolbarItemGroup(placement:.keyboard) { Spacer();Button("收起键盘") { editing=nil } } }
        .confirmationDialog("选择升变",isPresented:Binding(get:{!promotions.isEmpty},set:{if !$0 { promotions=[] }})) {
            ForEach(promotions,id:\.code) { move in Button(["q":"升后","r":"升车","b":"升象","n":"升马"][move.promotion] ?? "升变") { choice=move.code;promotions=[] } }
        }
    }
    private func perform(_ action:()throws->Void) { do { try action();error=nil } catch { self.error=error.localizedDescription } }
    private func saveDraft() { perform { try study.draft(runID:runID,trialID:trial.id,candidates:candidates,threat:threat) } }
    private func tap(_ square:String) {
        guard let frame else { return }
        if let selected {
            let moves=frame.replies.filter{$0.from==selected && $0.to==square}
            if moves.count>1 { promotions=moves;return };if let move=moves.first { choice=move.code;return }
        }
        selected=frame.pieces.contains(where:{$0.square==square && $0.color==frame.turn}) ? square:nil;choice=nil
    }
}
struct ConditionFeedbackView:View {
    let runID:UUID
    @EnvironmentObject private var study:ConditionStudyStore
    var body:some View {
        List {
            if let run=study.run(runID),run.feedbackAt != nil {
                Section("本轮记录，非心理测量") {
                    Text(ConditionSummary.evaluate(run).message).accessibilityIdentifier("conditionSummary")
                    Text("这些记录只说明你提交了什么，不能完整反映你当时看到了什么。未控制所有变量，不作显著性、提升比例或因果判断。")
                    Text("完整提交 \(run.completedCount)/\(run.trials.count)；缺失保持缺失。\(run.demonstration ? "本轮为演示，全部排除。" : "")").accessibilityIdentifier("conditionCompletion")
                }
                ForEach(run.trials) { trial in
                    Section(run.phase=="transfer" ? "延时局面" : "\(title(trial.position.family)) · 条件 \(trial.position.condition)") {
                        if run.phase != "transfer" { Text("指定吃子机会：\(trial.position.captureOpportunity ? "有":"无") · 防守关系：\(trial.position.defenseChanged ? "改变":"原样")").font(.caption) }
                        if let answer=trial.firstAnswer {
                            Text("首答：\(answer.choice=="none" ? "没有一步将死":answer.choice) · \(answer.correct ? "符合棋规答案":"与棋规答案不同")").accessibilityIdentifier("conditionFirstAnswer")
                            Text("候选着：\(answer.candidates.isEmpty ? "未填写":answer.candidates)\n威胁：\(answer.threat.isEmpty ? "未填写":answer.threat)").font(.caption)
                        } else { Text("未提交，不记为错误").accessibilityIdentifier("conditionMissing") }
                        if !trial.exclusions.isEmpty { Text("排除：\(trial.exclusions.joined(separator:"；"))").font(.caption) }
                        NavigationLink("查看局面、证明与单独重试") { ConditionResultView(runID:runID,trialID:trial.id) }
                    }
                }
                Section("相反或不足的证据") {
                    ForEach(ConditionSummary.evaluate(run).contrary,id:\.self) { line in Text(readable(line)).font(.caption) }
                    Text("若各组不一致、存在已见/示例/缺失记录，不能据此给出稳定倾向。即使一致，也仅给暂定的棋规练习提示。")
                }
                if let due=run.transferDueAt { Section { Text("四题延时复测：\(due.formatted(date:.abbreviated,time:.shortened)) 之后，从列表进入。不会自动提醒。") } }
                if !run.retries.isEmpty { Section { Text("另存 \(run.retries.count) 次反馈后重试，未覆盖首次答案。") } }
            }
        }.navigationTitle("统一反馈").navigationBarTitleDisplayMode(.inline).accessibilityIdentifier("conditionFeedback")
    }
    private func title(_ id:String)->String { study.data.catalog?.families.first{$0.id==id}?.title ?? "延时局面" }
    private func readable(_ s:String)->String { (study.data.catalog?.families ?? []).reduce(s) { $0.replacingOccurrences(of:$1.id,with:$1.title) } }
}
struct ConditionResultView:View {
    let runID:UUID;let trialID:UUID
    @EnvironmentObject private var study:ConditionStudyStore
    @State private var retrying=false
    @State private var recall=""
    @State private var message:String?
    private var trial:ConditionTrial? { study.run(runID)?.trials.first{$0.id==trialID} }
    var body:some View {
        ScrollView {
            if let trial,study.run(runID)?.feedbackAt != nil {
                VStack(alignment:.leading,spacing:16) {
                    if let frame=try? ChessEngine().frames(fen:trial.position.fen).first { GameBoard(frame:frame) }
                    Text(trial.position.answers.isEmpty ? "完整枚举：没有一步将死。" : "完整一步杀答案：\(trial.position.answers.joined(separator:"、"))").font(.headline).accessibilityIdentifier("conditionVerifiedAnswers")
                    Text(trial.position.relation)
                    if let critical=trial.position.critical, let after=try? ChessEngine().frames(fen:trial.position.fen,moves:[critical]).last {
                        Text("关键着 \(critical) 之后：\(after.mate ? "将军，且没有合法应将" : "没有将死")。")
                        if !after.replies.isEmpty { Text("对方合法应对例如：\(after.replies.prefix(6).map(\.san).joined(separator:"、"))。") }
                    }
                    Text("题目 v\(trial.position.version) · 合法 PGN 重放与全部一步杀枚举；本地 Stockfish 复核。") .font(.caption)
                    DisclosureGroup("查看合法到达证明与来源") { Text(trial.position.pgn).font(.caption.monospaced()).textSelection(.enabled);Text(study.data.catalog?.source ?? "");Text(study.data.catalog?.license ?? "") }
                    Button("反馈后重试（另记，不覆盖首答）") { retrying=true }.accessibilityIdentifier("conditionRetry")
                    TextField("现在补记（已看反馈，不计首答）",text:$recall,axis:.vertical).lineLimit(2...5).accessibilityIdentifier("conditionRecall")
                    Button("保存事后补记") { do { try study.recall(runID:runID,trialID:trialID,text:recall);recall="";message="已另存事后补记，不纳入首答比较。" } catch { message=error.localizedDescription } }
                    ForEach(study.run(runID)?.recalls.filter{$0.trialID==trialID} ?? []) { entry in Text("反馈后补记：\(entry.text)").font(.caption) }
                    if let message { Text(message) }
                }.padding(16).frame(maxWidth:560).frame(maxWidth:.infinity)
            }
        }.navigationTitle("棋规证据").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented:$retrying) { if let trial { ConditionRetryView(runID:runID,trial:trial) } }
    }
}
private struct ConditionRetryView:View {
    let runID:UUID;let trial:ConditionTrial
    @EnvironmentObject private var study:ConditionStudyStore
    @Environment(\.dismiss) private var dismiss
    @State private var frame:ChessFrame?
    @State private var selected:String?
    @State private var choice:String?
    @State private var promotions:[ChessMove]=[]
    @State private var error:String?
    var body:some View {
        NavigationStack {
            ScrollView { VStack(alignment:.leading,spacing:16) {
                Text("已看过反馈的重试；首次答案保持不变。")
                if let frame { GameBoard(frame:frame,flipped:frame.turn=="b",selected:selected,enabled:true,tap:tap) }
                Text(choice=="none" ? "没有一步将死" : choice ?? "请选择走法")
                Button("没有一步将死") { choice="none" }
                Button("另存重试") { do { try study.retry(runID:runID,trialID:trial.id,choice:choice!);dismiss() } catch { self.error=error.localizedDescription } }.disabled(choice==nil).accessibilityIdentifier("saveConditionRetry")
                if let error { Text(error) }
            }.padding(16).frame(maxWidth:560) }.navigationTitle("反馈后重试").toolbar { Button("关闭") { dismiss() } }
        }.task { frame=try? ChessEngine().frames(fen:trial.position.fen)[0] }
        .confirmationDialog("选择升变",isPresented:Binding(get:{!promotions.isEmpty},set:{if !$0 { promotions=[] }})) {
            ForEach(promotions,id:\.code) { move in Button(["q":"升后","r":"升车","b":"升象","n":"升马"][move.promotion] ?? "升变") { choice=move.code;promotions=[] } }
        }
    }
    private func tap(_ square:String) {
        guard let frame else { return }
        if let selected {
            let moves=frame.replies.filter{$0.from==selected && $0.to==square}
            if moves.count>1 { promotions=moves;return };if let move=moves.first { choice=move.code;return }
        }
        selected=frame.pieces.contains(where:{$0.square==square && $0.color==frame.turn}) ? square:nil;choice=nil
    }
}
