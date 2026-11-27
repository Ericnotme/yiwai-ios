import SwiftUI
import UniformTypeIdentifiers

struct PersonalStudyHome:View {
    @EnvironmentObject private var store:PersonalStore
    @State private var pgn="";@State private var side="";@State private var message:String?;@State private var selected:UUID?
    @State private var importing=false
    @FocusState private var editing:Bool
    var body:some View {
        List {
            Section {
                Text("从棋谱到可检验的问题").font(.title2.bold())
                Text("只检查漏走一步将死。先给棋规和引擎证据，再请你纠正可能的解释；不能自动知道你的心理原因。无需注册，全程在本机。")
                Button("体验一局 · 实际本地分析") {create(PersonalRules.demoPGN,side:"w",demo:true)}.accessibilityIdentifier("personalDemo")
                Text("完整合法构造棋谱，非真实用户对局；实时运行本地引擎，没有预计算进度。示例记录不计个人复测。").font(.caption)
            }
            Section("导入我的 PGN") {
                TextEditor(text:$pgn).frame(minHeight:120).focused($editing).accessibilityLabel("个人棋谱 PGN").accessibilityIdentifier("personalPGN")
                Button("从文件读取 PGN") {importing=true}.accessibilityIdentifier("personalFile")
                Picker("确认我的执棋方",selection:$side) {Text("请选择").tag("");Text("白方").tag("w");Text("黑方").tag("b")}.pickerStyle(.segmented).accessibilityIdentifier("personalSide")
                Button("开始本地检查") {editing=false;create(pgn,side:side,demo:false)}.disabled(side.isEmpty||pgn.isEmpty).accessibilityIdentifier("personalAnalyze")
                Text("一盘一次，标准开局，最多 200 KB / 200 半回合；只分析主线，原文注释与变例保留。FEN 起始棋谱及变体暂不进入此流程，仍可从原导入入口保存。超限会拒绝，不截断。重复棋谱打开已有记录，不覆盖首答或原文。").font(.caption)
            }
            if let message {Section{Text(message).foregroundStyle(.red).accessibilityIdentifier("personalImportError")}}
            if let error=store.error {Section{Text(error).foregroundStyle(.red)}}
            Section("本机检查记录") {
                ForEach(store.data.cases.reversed()) {item in
                    NavigationLink {PersonalCaseView(caseID:item.id)} label: {
                        VStack(alignment:.leading,spacing:5) {Text(item.demonstration ? "构造示例 · 非个人成绩":"我的棋谱 · 执\(item.side=="w" ? "白":"黑")");Text("\(item.game.moves.count) 半回合 · \(item.createdAt.formatted(date:.abbreviated,time:.shortened))").font(.caption)}
                    }.accessibilityIdentifier("personal-case-\(item.id)")
                }
            }
        }.navigationTitle("个人棋谱实验").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item:$selected){PersonalCaseView(caseID:$0)}
        .toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("收起键盘"){editing=false}}}
        .fileImporter(isPresented:$importing,allowedContentTypes:[.plainText,.data]){result in
            do {let url=try result.get();let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                let attributes=try FileManager.default.attributesOfItem(atPath:url.path);guard (attributes[.size] as? NSNumber)?.intValue ?? 200001 <= 200000 else{throw ChessFailure.invalid("文件超过 200 KB，请导出单盘棋谱")}
                pgn=try String(contentsOf:url,encoding:.utf8);message=nil
            }catch{message=error.localizedDescription}
        }
    }
    private func create(_ text:String,side:String,demo:Bool){do{let record=try PersonalRules().parse(text,side:side);selected=try store.add(record,side:side,demo:demo);message=nil}catch{message=error.localizedDescription}}
}

struct PersonalCaseView:View {
    let caseID:UUID
    @EnvironmentObject private var store:PersonalStore
    @EnvironmentObject private var decisions:DecisionStore
    @EnvironmentObject private var game:GameController
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var pipeline=PersonalPipeline()
    @State private var message:String?;@State private var confirmEnd=false;@State private var recollection="";@State private var correction=""
    private var item:PersonalCase? {store.item(caseID)}
    var body:some View {
        Group {
            if let item,let round=item.active,let trial=round.current {
                PersonalQuestion(caseID:caseID,trial:trial,index:round.trials.filter{$0.first != nil}.count+1,total:round.trials.count,kind:round.kind)
                    .id(trial.id).task(id:trial.id){perform{try store.present(caseID,known:known(),expose:decisions.recordExposure)}}
            } else {summary}
        }.navigationTitle(item?.demonstration==true ? "示例 · 个人棋谱流程":"棋谱证据与复习").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if item?.active != nil {ToolbarItem(placement:.topBarTrailing){Button("结束看反馈"){confirmEnd=true}.accessibilityIdentifier("personalEnd")}}
        }
        .alert("结束本轮并展示答案？",isPresented:$confirmEnd){Button("继续作答",role:.cancel){};Button("结束并查看"){perform{try store.finish(caseID,expose:decisions.recordExposure)}}}message:{Text("未提交会保留为空；本轮相关局面以后不能当作未见题。首答不会覆盖。")}
        .task {if let item,item.rounds.isEmpty,item.status != "complete-no-pair" {pipeline.run(caseID,store:store)}}
        .onDisappear{pipeline.cancel()}
        .onChange(of:scenePhase){_,phase in if phase != .active {pipeline.cancel()}}
        .safeAreaInset(edge:.bottom){if let message {Text(message).font(.caption).foregroundStyle(.red).padding().background(.background).accessibilityIdentifier("personalError")}}
        .background {if let engine=pipeline.engine {ReviewEngineHost(engine:engine).frame(width:1,height:1).opacity(0.01).accessibilityHidden(true)}}
    }
    private var summary:some View {
        List {
            if let item {
                if item.demonstration {Section{Text("构造示例，所有作答排除于个人独立表现；模拟跨日仅供体验。").font(.caption).accessibilityIdentifier("personalDemoBanner")}}
                if pipeline.running {
                    Section {ProgressView();Text(pipeline.progress).accessibilityIdentifier("personalProgress");Button("暂停检查"){pipeline.cancel()}.accessibilityIdentifier("personalPause")}
                } else if item.rounds.isEmpty && item.status != "complete-no-pair" {
                    Section {Text(pipeline.progress);Button("继续本地检查"){pipeline.run(caseID,store:store)}.accessibilityIdentifier("personalResume")}
                }
                if let error=pipeline.error {Section{Text(error).foregroundStyle(.red).accessibilityIdentifier("personalPipelineError")}}
                if item.status=="complete-no-pair" {
                    Section {Text("已分析，但暂无可靠个人原因题").font(.headline).accessibilityIdentifier("personalNoPair");Text("本次没有通过完整校验的成对局面。只检测一步将死，不表示你没有其他问题，也不拿通用示例替代个人生成。")}
                }
                if let round=item.active,round.current==nil {
                    Section {Text("本轮首答已保存，尚未展示反馈。");Button("查看本轮反馈"){perform{try store.finish(caseID,expose:decisions.recordExposure)}}.accessibilityIdentifier("personalFeedback")}
                }
                if item.active==nil {
                    if let scan=item.scan,item.rounds.first?.feedbackAt != nil || item.status=="complete-no-pair" {
                        Section("棋规事实 · 不是心理诊断") {Text("完整检查 \(scan.examined) 个己方回合，发现 \(scan.misses) 处漏走当步将死。仅优先验证前 \(min(3,scan.misses)) 处，每处最多 2 个替代分支，最多提供一组。").accessibilityIdentifier("personalRuleFacts");if let evidence=item.evidence{Text(evidence.explanation)}}
                    }
                    if item.rounds.first?.feedbackAt != nil {
                        Section("可纠正的棋理假说") {
                            Text(item.hypothesis).accessibilityIdentifier("personalHypothesis")
                            if let branch=item.branch {Text("合法分支把前一步 \(branch.replaced) 换为 \(branch.replacementSAN)。相同候选着仍合法，但全部合法着中没有一步将死。多个关系可能同时改变，不能据此证明失误原因。")
                                Text("在这个分支走 \(branch.criticalSAN) 后，对手的全部合法应对：\(branch.criticalReplies.isEmpty ? "无（需区分逼和等终局）":branch.criticalReplies.joined(separator:"、"))。规则状态：\(branch.outcomeLabel)")}
                            TextField("我现在的回忆（可跳过）",text:$recollection,axis:.vertical).accessibilityIdentifier("personalRecall")
                            TextField("修正这个假说（可空）",text:$correction,axis:.vertical).accessibilityIdentifier("personalCorrection")
                            Button("保存事后补记 / 跳过"){perform{try store.recollect(caseID,text:recollection,correction:correction);recollection=""}}.accessibilityIdentifier("personalSaveRecall")
                            Text("这次输入是反馈后的事后回忆，独立于棋谱实际走法及复盘首答。不能补写成当时原话。").font(.caption)
                            ForEach(Array(item.recollections.enumerated()),id:\.offset){_,r in Text(r.text.isEmpty ? "已跳过补记":r.text).font(.caption)}
                            if let correction=item.hypothesisCorrection,!correction.isEmpty{Text("用户修正：\(correction)")}
                        }
                        ForEach(item.rounds.filter{$0.feedbackAt != nil}) {round in
                            Section(round.kind=="review" ? "原局与分支 · 事后复盘":round.kind=="practice" ? "匹配题 · 针对练习":"到期未见题 · 本次表现") {
                                ForEach(round.trials) {trial in PersonalFeedback(trial:trial)}
                            }
                        }
                        Section("下一步") {
                            if !item.rounds.contains(where:{$0.kind=="practice"}) {
                                Button("开始一题匹配练习"){start("practice")}.accessibilityIdentifier("personalPractice")
                            }else if !item.rounds.contains(where:{$0.kind=="transfer"}),let due=item.dueAt {
                                Text("到期：\(due.formatted(date:.abbreviated,time:.shortened))，从实际练习完成起 24 小时。")
                                Button("开始到期未见题复测"){start("transfer")}.disabled(store.now<due && item.demoTimeAdvancedAt==nil).accessibilityIdentifier("personalTransfer")
                                if item.demonstration && item.demoTimeAdvancedAt==nil {Button("仅示例：模拟来到到期时间"){perform{try store.advanceDemo(caseID)}}.accessibilityIdentifier("personalAdvanceDemo")}
                                if item.demoTimeAdvancedAt != nil{Text("示例已模拟跨日，并未真实等待 24 小时。").font(.caption)}
                            }else{Text("本轮记录已保留。一次答对只说明这次表现，不表示已掌握习惯或提高 Elo。")}
                            Text("练习与复测来自有合法历史证明的匹配题库，明确不是从你的棋谱生成的反事实。未见仅指本机记录；近重复、翻转和相邻局面会排除。题库不足会停止提供。").font(.caption)
                        }
                    }
                    if !item.attempts.isEmpty,item.rounds.first?.feedbackAt != nil || item.status=="complete-no-pair" {Section {DisclosureGroup("检查预算与拒绝记录") {ForEach(Array(item.attempts.enumerated()),id:\.offset){_,a in Text("ply \(a.ply): \(a.outcome)").font(.caption)}}}}
                }
            }
            Text("这些记录只说明你提交了什么，不能完整反映你当时看到了什么。可随时返回暂停；数据保存在本地时间胶囊。").font(.caption)
        }
    }
    private func known()throws->Set<String>{try ReforgeRules().knownKeys(games:game.capsuleRecords(),notes:decisions.data.notes,seen:decisions.data.seen)}
    private func start(_ kind:String){perform{try store.startCatalog(caseID,kind:kind,known:known())}}
    private func perform(_ action:()throws->Void){do{try action();message=nil}catch{message=error.localizedDescription}}
}

private struct PersonalQuestion:View {
    let caseID:UUID;let trial:PersonalTrial;let index:Int;let total:Int;let kind:String
    @EnvironmentObject private var store:PersonalStore
    @State private var frame:ChessFrame?;@State private var selected:String?;@State private var choice:String?
    @State private var promotions:[ChessMove]=[];@State private var candidates="";@State private var reason="";@State private var error:String?;@State private var notes=false
    @FocusState private var editing:Bool
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                Text("\(kind=="review" ? "事后复答":kind=="practice" ? "匹配练习":"到期复测") · \(index) / \(total)").font(.headline).accessibilityIdentifier("personalQuestionCount")
                Text("\(frame?.turn=="b" ? "黑":"白")方走：选一步将死的走法，或没有一步将死。")
                if let frame{GameBoard(frame:frame,flipped:frame.turn=="b",selected:selected,enabled:true,tap:tap)}
                Text(choice=="none" ? "待提交：没有一步将死":choice.map{"待提交：\($0)"} ?? "请点起点和终点").accessibilityIdentifier("personalChoice")
                Button("没有一步将死"){choice="none";selected=nil}.buttonStyle(.bordered).accessibilityIdentifier("personalNoMate")
                Button("可选：候选着与理由"){notes.toggle()}.accessibilityIdentifier("personalNotes")
                if notes {
                    TextField("候选着（可空）",text:$candidates,axis:.vertical).textFieldStyle(.roundedBorder).focused($editing).accessibilityIdentifier("personalCandidates")
                    TextField("现在的理由（可空）",text:$reason,axis:.vertical).textFieldStyle(.roundedBorder).focused($editing).accessibilityIdentifier("personalReason")
                    Button("使用检查提示 / 标记已看过"){perform{try store.hint(caseID)}}.accessibilityIdentifier("personalHint")
                }
                if store.item(caseID)?.active?.current?.hintAt != nil{Text("检查将军、吃掉将军子、挡住线路和王的逃格。已标记辅助，本题不计独立表现。").font(.caption)}
                Button("提交首答"){perform{try store.draft(caseID,candidates:candidates,reason:reason);try store.submit(caseID,trialID:trial.id,submissionID:trial.submissionID,choice:choice!)}}.buttonStyle(.borderedProminent).disabled(choice==nil||trial.shownAt==nil).accessibilityIdentifier("personalSubmit").keyboardShortcut(.return,modifiers:.command)
                if trial.exclusions.contains("locally seen or near duplicate") {Text("本机已见或与已见局面接近：本题不计独立未见题表现。").font(.caption)}
                Text("本轮结束前隐藏答案、规律与引擎变化。首答永久保留；可不写理由。原局复答属于事后复盘，不是未见题测试。").font(.caption)
                if let error{Text(error).foregroundStyle(.red)}
            }.padding(16).frame(maxWidth:560).frame(maxWidth:.infinity)
        }.background(Palette.paper).task{do{frame=try ChessEngine().frames(fen:trial.position.fen).first;candidates=trial.candidates;reason=trial.reason}catch{self.error=error.localizedDescription}}
        .onChange(of:candidates){_,_ in draft()}.onChange(of:reason){_,_ in draft()}
        .toolbar{ToolbarItemGroup(placement:.keyboard){Spacer();Button("收起键盘"){editing=false}}}
        .confirmationDialog("选择升变",isPresented:Binding(get:{!promotions.isEmpty},set:{if !$0{promotions=[]}})){ForEach(promotions,id:\.code){move in Button(move.san){choice=move.code;promotions=[]}}}
    }
    private func tap(_ square:String){guard let frame else{return};if let selected{let moves=frame.replies.filter{$0.from==selected && $0.to==square};if moves.count>1{promotions=moves;return};if let m=moves.first{choice=m.code;return}};selected=frame.pieces.contains(where:{$0.square==square && $0.color==frame.turn}) ? square:nil;choice=nil}
    private func perform(_ action:()throws->Void){do{try action();error=nil}catch{self.error=error.localizedDescription}}
    private func draft(){perform{try store.draft(caseID,candidates:candidates,reason:reason)}}
}
private struct PersonalFeedback:View {
    let trial:PersonalTrial
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            if let frame=try? ChessEngine().frames(fen:trial.position.fen).first{GameBoard(frame:frame).frame(maxWidth:380)}
            Text(trial.first.map{"首次：\($0.choice) · \(trial.correct==true ? "本次正确":"本次未答对")"} ?? "未提交；不计为错误").accessibilityIdentifier("personalFirstResult")
            Text("完整一步将死答案：\(trial.position.answers.isEmpty ? "没有":trial.position.answers.joined(separator:"、"))").accessibilityIdentifier("personalAnswerSet")
            if let first=trial.first {Text(first.reason.isEmpty ? "未填写理由":first.reason);Text("记录时机：\(first.context)").font(.caption)}
            Text("排除原因：\(trial.exclusions.isEmpty ? "无；仅表示本次独立提交":trial.exclusions.joined(separator:"；"))").font(.caption)
            DisclosureGroup("查看可重放证明、题源与引擎") {
                Text(trial.position.source).font(.caption);Text(trial.position.license).font(.caption)
                Text("版本 \(trial.position.version) · 标准起始 UCI：\(trial.position.history.joined(separator:" "))").font(.caption.monospaced()).textSelection(.enabled)
                if let check=trial.position.catalogCheck {Text("题库预核验（非本次现场分析）：\(check.engine)，\(check.checkedAt)，深度 \(check.depth)。完整 PV：\(check.pv.joined(separator:" "))。旧题库记录未包含逐次搜索预算；这里的无一步杀判定仍由全部合法着枚举核验。").font(.caption.monospaced())}
                ForEach(Array(trial.position.probes.enumerated()),id:\.offset){_,p in
                    Text("\(p.engine) · \(p.budgetMS) ms · depth \(p.evaluation.depth) · nodes \(p.evaluation.nodes)\n\(p.evaluation.label) · 原始 \(p.rawScore.type) \(p.rawScore.value)（当前走棋方视角）\n完整 PV：\(p.evaluation.pv.joined(separator:" "))\n\(p.settings)\n\(p.stopReason) · \(p.elapsedMS) ms").font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }.padding(.vertical,8)
    }
}
