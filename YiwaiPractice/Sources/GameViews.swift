import SwiftUI
import Charts

struct GameBoard: View {
    let frame: ChessFrame
    var flipped = false
    var selected: String? = nil
    var targets: Set<String> = []
    var enabled = false
    var tap: (String) -> Void = { _ in }
    var drag: (String,String) -> Void = { _,_ in }
    var body: some View {
        VStack(spacing:3) {
            GeometryReader { geometry in
                let size = geometry.size.width / 8
                VStack(spacing:0) {
                    ForEach(0..<8,id:\.self) { row in
                        HStack(spacing:0) {
                            ForEach(0..<8,id:\.self) { column in
                                let file = flipped ? 7-column : column
                                let rank = flipped ? row+1 : 8-row
                                let square = String(Array("abcdefgh")[file])+String(rank)
                                let piece = frame.pieces.first { $0.square == square }
                                Button { tap(square) } label: {
                                    ZStack {
                                        Rectangle().fill((file+rank)%2 == 0 ? Color(red:0.75,green:0.82,blue:0.76) : Color(red:0.96,green:0.94,blue:0.88))
                                        if [frame.from,frame.to].contains(square) { Rectangle().fill(Color.yellow.opacity(0.30)) }
                                        if targets.contains(square) { Circle().fill(Palette.sage.opacity(0.5)).frame(width:size*0.25,height:size*0.25) }
                                        if let piece { Text(piece.symbol).font(.system(size:size*0.79)).foregroundStyle(piece.color == "w" ? Color.white : Palette.ink).shadow(color:Palette.ink.opacity(piece.color == "w" ? 0.8 : 0),radius:0.6,x:0,y:1).shadow(color:Palette.ink.opacity(piece.color == "w" ? 0.8 : 0),radius:0.6,x:0,y:-1) }
                                        if selected == square { Rectangle().strokeBorder(Palette.coral,lineWidth:3) }
                                        if piece?.type == "k" && piece?.color == frame.turn && frame.check { Rectangle().strokeBorder(.red,lineWidth:2) }
                                        if column == 0 { VStack { HStack { Text(String(rank)).font(.system(size:9,weight:.bold)); Spacer() }; Spacer() }.padding(2).foregroundStyle(Palette.ink) }
                                    }.frame(width:size,height:size)
                                }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel("\(square)，\(piece?.name ?? "空格")\(targets.contains(square) ? "，可以走到" : "")").accessibilityIdentifier("square-\(square)")
                            }
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius:3))
                    .simultaneousGesture(DragGesture(minimumDistance:12).onEnded { value in
                        guard enabled else { return }
                        func square(_ point: CGPoint) -> String? {
                            guard point.x >= 0, point.y >= 0, point.x < geometry.size.width, point.y < geometry.size.width else { return nil }
                            let column = Int(point.x/size), row = Int(point.y/size)
                            return String(Array("abcdefgh")[flipped ? 7-column : column])+String(flipped ? row+1 : 8-row)
                        }
                        if let from = square(value.startLocation), let to = square(value.location), from != to { drag(from,to) }
                    })
            }.aspectRatio(1,contentMode:.fit)
            HStack(spacing:0) { ForEach(flipped ? Array("hgfedcba") : Array("abcdefgh"),id:\.self) { file in Text(String(file)).font(.caption2).frame(maxWidth:.infinity) } }.foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}

struct GamePlayView: View {
    @EnvironmentObject var game: GameController
    @EnvironmentObject private var decisions: DecisionStore
    @State private var decisionCapture: DecisionCapture?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var setup = false
    @State private var human = "w"
    @State private var level = 1
    @State private var review: GameRecord?
    @State private var resign = false
    private var rowLayout: AnyLayout { textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)) : AnyLayout(HStackLayout(alignment:.top,spacing:8)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    if let state = game.snapshot, let record = game.current {
                        playerBar("Seed 0.2",subtitle:"本机电脑 · 未评级",color:record.human == "w" ? "b" : "w",active:game.thinking)
                        GameBoard(frame:state.frame,flipped:record.human == "b",selected:game.selected,targets:game.targets,enabled:game.canMove,tap:game.tap,drag:{ from,to in game.selected = nil; game.tap(from); game.tap(to) })
                        playerBar("你",subtitle:record.human == "w" ? "执白" : "执黑",color:record.human,active:game.canMove)
                        Text("\(record.moves.count) 半回合").font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("plyCount")
                        if game.canMove && decisions.canRecord(gameID:record.id) && !decisions.data.notes.contains(where:{$0.gameID == record.id && $0.ply == record.moves.count}) {
                            Button("记下此刻的候选着与理由（可跳过）") { game.pause(); decisionCapture = DecisionCapture(record:record,ply:record.moves.count,origin:.beforeMove) }
                                .font(.subheadline).frame(minHeight:44).accessibilityIdentifier("captureLiveDecision")
                        }
                        HStack(spacing:8) { if game.thinking { ProgressView() }; Text(game.status).font(.subheadline.weight(.medium)).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("gameStatus") }.frame(minHeight:40,alignment:.leading)
                        rowLayout {
                            Button { game.undo() } label: { Label("悔棋",systemImage:"arrow.uturn.backward") }.disabled(!game.canUndo).accessibilityIdentifier("undoGame")
                            if !textSize.isAccessibilitySize { Spacer() }
                            if state.result == "*" {
                                Button { game.paused ? game.resume() : game.pause() } label: { Label(game.paused ? "继续对弈" : "暂停",systemImage:game.paused ? "play.fill" : "pause.fill") }.accessibilityIdentifier("pauseGame")
                            }
                        }.buttonStyle(.bordered).frame(minHeight:44)
                        Button { game.finish(resign:false); review = game.current } label: { Label("保存并复盘 · AI Coach",systemImage:"sparkle.magnifyingglass").font(.headline).frame(maxWidth:.infinity,minHeight:48) }.buttonStyle(.borderedProminent).disabled(record.moves.isEmpty).accessibilityIdentifier("reviewGame")
                        if !state.sans.isEmpty {
                            Text(state.sans.enumerated().map { "\($0.offset % 2 == 0 ? "\($0.offset/2+1). " : "")\($0.element)" }.joined(separator:" ")).font(.subheadline.monospaced()).foregroundStyle(.secondary).lineLimit(3).accessibilityIdentifier("liveMoves")
                        }
                        if state.result == "*" && record.ending == nil { Button("认输并保存棋局",role:.destructive) { resign = true }.font(.subheadline).frame(minHeight:44) }
                    } else {
                        ContentUnavailableView("留给自己一盘棋的时间",systemImage:"checkerboard.rectangle",description:Text("选择执白或执黑。电脑在本机思考，棋局结束后一起复盘。"))
                        Button("开始人机对弈") { setup = true }.buttonStyle(.borderedProminent).frame(maxWidth:.infinity,minHeight:48).accessibilityIdentifier("startGame")
                    }
                    Text("离开此页或切到后台会暂停思考。棋谱仅保存在本机；卸载 App 会清除记录。").font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(maxWidth:560)
            }.background(Palette.paper).navigationTitle("弈外 · 对弈").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { Button("新局") { setup = true }.accessibilityIdentifier("newGame") } }
            .sheet(isPresented:$setup) { NavigationStack {
                Form {
                    Section("选择颜色") { Picker("你执",selection:$human) { Text("白方先行").tag("w"); Text("黑方后行").tag("b") }.pickerStyle(.segmented).accessibilityIdentifier("chooseColor") }
                    Section("思考时间") {
                        Picker("电脑",selection:$level) { Text("轻快 · 约0.3秒").tag(0); Text("从容 · 约1秒").tag(1); Text("认真 · 约1.8秒").tag(2) }
                        Text("时间是单次搜索上限，实际速度依设备和局面变化；不是 Elo 等级。").font(.caption)
                    }
                    Section { Text("当前棋局会保留在「棋谱」，可以随时继续。") }
                }.safeAreaInset(edge:.bottom) {
                    Button { game.newGame(human:human,level:level); setup = false } label: {
                        Text("开始新局").font(.headline).frame(maxWidth:.infinity,minHeight:48)
                    }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmNewGame").padding(.horizontal,20).padding(.vertical,12).background(.regularMaterial)
                }.navigationTitle("新的一局").toolbar { Button("取消") { setup = false } }
            }.presentationDetents([.medium,.large]) }
            .confirmationDialog("兵到达底线，选择升变",isPresented:Binding(get:{!game.promotions.isEmpty},set:{if !$0 { game.promotions = [] }}),titleVisibility:.visible) {
                ForEach(game.promotions,id:\.code) { move in Button(["q":"升后","r":"升车","b":"升象","n":"升马"][move.promotion] ?? move.promotion) { game.play(move.code) } }
                Button("取消",role:.cancel) { game.promotions = [] }
            }
            .confirmationDialog("确认认输？棋局会保留供复盘。",isPresented:$resign,titleVisibility:.visible) { Button("认输",role:.destructive) { game.finish(resign:true) } }
            .sheet(item:$review) { record in NavigationStack { GameReviewView(record:record).toolbar { Button("完成") { review = nil } } } }
            .sheet(item:$decisionCapture) { DecisionCaptureView(capture:$0) }
            .onChange(of:scenePhase) { _, phase in if phase != .active { game.pause() } }
            .onDisappear { game.pause() }
        }
    }
    private func playerBar(_ name: String,subtitle: String,color: String,active: Bool) -> some View {
        HStack(spacing:10) {
            Image(systemName:color == "w" ? "circle" : "circle.fill").font(.title3).frame(width:36,height:36).background(Palette.sage.opacity(0.1),in:RoundedRectangle(cornerRadius:6))
            VStack(alignment:.leading,spacing:2) { Text(name).font(.subheadline.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if active { Text("走棋中").font(.caption.weight(.medium)).foregroundStyle(Palette.sage) }
        }.padding(.vertical,3)
    }
}

struct GameHistoryView: View {
    @State private var importing = false
    @EnvironmentObject var game: GameController
    let resume: (UUID) -> Void
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { TimeCapsuleView() } label: {
                        Label("时间胶囊 · 备注与完整导出",systemImage:"archivebox")
                    }.accessibilityIdentifier("openTimeCapsule")
                    NavigationLink { LearningPatternView() } label: {
                        Label("从我的棋谱找练习",systemImage:"magnifyingglass")
                    }.accessibilityIdentifier("openLearningPattern")
                    NavigationLink { DecisionListView() } label: {
                        Label("决策回炉 · 到期复习",systemImage:"arrow.clockwise")
                    }.accessibilityIdentifier("openDecisionReforge")
                }
                if game.records.isEmpty { ContentUnavailableView("你的棋局会留在这里",systemImage:"books.vertical",description:Text("先和电脑下一盘。每一步自动保存，支持完整回放与 PGN 导出。")) }
                ForEach(game.records) { record in
                    VStack(alignment:.leading,spacing:10) {
                        NavigationLink { GameReviewView(record:record) } label: {
                            VStack(alignment:.leading,spacing:6) {
                                Text(record.title).font(.headline)
                                Text(record.created,format:.dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                Text(record.ending == "resigned" ? "已认输 · 查看复盘" : "逐步回放 · AI Coach").font(.subheadline)
                            }.padding(.vertical,5)
                        }.accessibilityIdentifier("record-\(record.id.uuidString)")
                        if record.ending != "resigned" && record.source == nil {
                            Button("继续这盘棋") { resume(record.id) }
                                .buttonStyle(.borderless).font(.subheadline).frame(minHeight:44)
                                .accessibilityIdentifier("resume-record-\(record.id.uuidString)")
                        }
                    }
                }
            }.scrollContentBackground(.hidden).background(Palette.paper).navigationTitle("棋谱")
            .toolbar { Button("导入 FEN / PGN") { importing = true }.accessibilityIdentifier("importPosition") }
            .sheet(isPresented:$importing) { PositionImportView() }
        }
    }
}

@MainActor final class ReviewController: ObservableObject {
    let record: GameRecord
    @Published var frames: [ChessFrame] = []
    @Published var report: GameReviewReport?
    @Published var failures: [Int:String] = [:]
    @Published var running = false
    @Published var loading = true
    @Published var error: String?
    @Published var pgnURL: URL?
    @Published var result = "*"
    @Published var reason = ""
    @Published var completed = 0
    @Published var duration = 450
    @Published var engine: StockfishReviewEngine?
    private var task: Task<Void,Never>?
    private var requestID = UUID()
    private static let loadQueue = DispatchQueue(label:"yiwai.review-loading",qos:.userInitiated)
    private var loadID = UUID()
    private var loadCancellation: SearchCancellation?
    private var loaded = false
    var results: [Int:ReviewedMove] { Dictionary(uniqueKeysWithValues:(report?.entries ?? []).map { ($0.ply-1,$0) }) }
    init(record: GameRecord) { self.record = record }
    func load() {
        guard !loaded, loadCancellation == nil else { return }
        let id = UUID(), cancellation = SearchCancellation()
        loadID = id; loadCancellation = cancellation; loading = true; error = nil
        let record = record
        Self.loadQueue.async { [weak self] in
            do {
                guard !cancellation.isCancelled else { return }
                let engine = try ChessEngine(cancellation:cancellation); let frames = try engine.frames(fen:record.initialFEN,moves:record.moves)
                let snapshot = try engine.game(record)
                var cached: GameReviewReport?
                if let report = record.reviewReport, report.matches(record) {
                    do {
                        try engine.validateReview(report,record:record)
                        cached = report
                    } catch { cached = nil }
                }
                guard !cancellation.isCancelled else { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("Yiwai-\(record.id.uuidString).pgn")
                try snapshot.pgn.write(to:url,atomically:true,encoding:.utf8)
                DispatchQueue.main.async {
                    guard let self, self.loadID == id, !cancellation.isCancelled else { return }
                    self.frames = frames; self.pgnURL = url; self.result = snapshot.result; self.reason = snapshot.reason
                    self.report = cached; self.duration = cached?.duration ?? 450; self.loading = false
                    self.loaded = true; self.loadCancellation = nil
                }
            } catch { DispatchQueue.main.async {
                guard let self, self.loadID == id, !cancellation.isCancelled else { return }
                self.error = error.localizedDescription; self.loading = false; self.loadCancellation = nil
            } }
        }
    }
    func cancel() {
        loadCancellation?.cancel(); loadCancellation = nil; loadID = UUID()
        task?.cancel(); task = nil; engine?.cancel(); engine = nil; requestID = UUID(); running = false; completed = 0
    }
    func analyze(save: @escaping @MainActor (GameReviewReport) -> Void) {
        guard !loading, !running, !frames.isEmpty else { return }
        let id = UUID(); requestID = id; running = true; completed = 0; failures = [:]; error = nil
        let worker = StockfishReviewEngine(); engine = worker
        worker.onProgress = { [weak self] completed,_ in
            guard self?.requestID == id else { return }; self?.completed = completed
        }
        let record = record, duration = duration
        task = Task { [weak self] in
            defer { worker.cancel(); if self?.requestID == id { self?.running = false; self?.engine = nil } }
            do {
                let report = try await worker.analyze(record,duration:duration)
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                self.report = report; save(report)
            } catch {
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                self.error = "分析未完成：\(error.localizedDescription)"; self.failures[0] = error.localizedDescription
            }
        }
    }
}

struct EvidenceReplay: Identifiable {
    let id = UUID(); let title: String; let fen: String; let moves: [String]; let prefix: Int
    var flipped = false
}
struct GameReviewView: View {
    let record: GameRecord
    @EnvironmentObject var game: GameController
    @EnvironmentObject private var decisions: DecisionStore
    @State private var decisionCapture: DecisionCapture?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var textSize
    @StateObject private var model: ReviewController
    @State private var ply = 0
    @State private var plotPly: Int?
    @State private var evidence: EvidenceReplay?
    @State private var editingNote = false
    private var currentNote: String { game.records.first(where:{$0.id == record.id})?.personalNote ?? "" }
    private var rowLayout: AnyLayout { textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)) : AnyLayout(HStackLayout(alignment:.top,spacing:8)) }
    init(record: GameRecord) { self.record = record; _model = StateObject(wrappedValue:ReviewController(record:record)) }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                HStack {
                    Text("\(model.result) · \(model.reason.isEmpty ? "棋局未结束" : model.reason)").font(.subheadline).accessibilityIdentifier("reviewResult")
                    Spacer()
                    if let url = model.pgnURL { ShareLink(item:url) { Image(systemName:"square.and.arrow.up").frame(width:44,height:44) }.accessibilityLabel("导出完整 PGN") }
                }
                Button { editingNote = true } label: {
                    Label(currentNote.isEmpty ? "添加个人备注" : "查看 / 编辑个人备注",systemImage:"square.and.pencil").frame(minHeight:44)
                }.accessibilityIdentifier("editPersonalNote")
                if decisions.canRecord(gameID:record.id) && !decisions.data.notes.contains(where:{$0.gameID == record.id && $0.ply == max(0,ply-1)}) {
                    Button("记录这处决策（事后回忆，可跳过）") {
                        decisionCapture = DecisionCapture(record:record,ply:max(0,ply-1),origin:.recollection)
                    }.frame(minHeight:44).accessibilityIdentifier("captureReviewDecision")
                }
                if model.loading { ProgressView("载入完整棋谱…") }
                if let error = model.error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("reviewError") }
                if model.frames.indices.contains(ply) {
                    GameBoard(frame:model.frames[ply],flipped:record.human == "b")
                    if !record.moves.isEmpty { replayControls }
                    ScrollView(.horizontal) { HStack(spacing:4) {
                        ForEach(1..<model.frames.count,id:\.self) { index in
                            let fields = model.frames[index-1].fen.split(separator:" ")
                            let label = "\(fields[5])\(fields[1] == "w" ? "." : "…") \(model.frames[index].san)"
                            Button(label) { ply = index }.font(.subheadline.monospaced()).padding(10)
                                .background(ply == index ? Palette.sage.opacity(0.20) : .white,in:RoundedRectangle(cornerRadius:6)).accessibilityIdentifier("move-\(index)")
                        }
                    } }
                    if record.moves.isEmpty {
                        positionCard
                    } else if let report = model.report {
                        if model.running { Text("正在更新；当前显示上一份完整报告。").font(.caption).foregroundStyle(.secondary) }
                        accuracyCard(report)
                        Chart {
                            RuleMark(y:.value("均势",50)).lineStyle(StrokeStyle(lineWidth:1,dash:[3])).foregroundStyle(.secondary.opacity(0.4))
                            ForEach(Array(report.evaluations.enumerated()),id:\.offset) { item in
                                LineMark(x:.value("半回合",item.offset),y:.value("白方",item.element.win)).foregroundStyle(Palette.sage)
                            }
                            RuleMark(x:.value("当前",ply)).foregroundStyle(Palette.coral)
                        }.chartYScale(domain:0...100).chartXScale(domain:0...max(1,record.moves.count))
                            .chartYAxis(.hidden).chartXSelection(value:$plotPly).frame(height:90)
                            .accessibilityLabel("局势变化，上方对白方有利；也可通过走子列表逐步查看")
                        Text("局势变化 · 上方对白方有利 · 点图跳到对应走法").font(.caption2).foregroundStyle(.secondary)
                    } else {
                        VStack(alignment:.leading,spacing:6) {
                            Text("整局准确度").font(.headline)
                            Text("完成分析后显示双方准确度与关键失误。未分析或取消的局面不会当作好棋。").font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth:.infinity,alignment:.leading).padding(14).background(.white,in:RoundedRectangle(cornerRadius:12))
                    }
                    analysisControls
                    if ply > 0, let entry = model.results[ply-1] { coachCard(entry) }
                    else if !record.moves.isEmpty { Text(ply == 0 ? "选择某一步，查看它背后的原因。" : "这一步尚无完整分析。").font(.subheadline).foregroundStyle(.secondary) }
                    if let report = model.report {
                        let highlights = report.entries.filter { $0.color == record.human && $0.loss >= 5 }.sorted { $0.loss > $1.loss }.prefix(5)
                        if !highlights.isEmpty {
                            VStack(alignment:.leading,spacing:8) {
                                Text("你的关键节点").font(.headline)
                                ForEach(Array(highlights)) { entry in
                                    Button { ply = entry.ply } label: {
                                        HStack { Text(entry.moveLabel); Spacer(); Text(entry.label); Image(systemName:"chevron.right") }.font(.subheadline).frame(minHeight:44)
                                    }
                                }
                            }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:12))
                        }
                    }
                }
            }.padding(12).frame(maxWidth:560)
        }.background(Palette.paper).navigationTitle(record.moves.isEmpty ? "局面分析 · 弈外" : "复盘 · 弈外").navigationBarTitleDisplayMode(.inline)
        .background { if let engine = model.engine { ReviewEngineHost(engine:engine).frame(width:1,height:1).opacity(0.01).allowsHitTesting(false).accessibilityHidden(true) } }
        .task { model.load() }
        .onDisappear { model.cancel() }
        .onChange(of:scenePhase) { _,phase in if phase != .active { model.cancel() } else { model.load() } }
        .onChange(of:plotPly) { _,value in if let value { ply = min(record.moves.count,max(0,value)) } }
        .sheet(item:$evidence) { item in EvidenceView(item:item) }
        .sheet(isPresented:$editingNote) { GameNoteView(recordID:record.id,note:currentNote) }
        .sheet(item:$decisionCapture) { DecisionCaptureView(capture:$0) }
    }
    private var positionCard: some View {
        VStack(alignment:.leading,spacing:10) {
            Text("独立局面 · 不计算整局准确度").font(.headline)
            Text("\(model.frames[0].turn == "w" ? "白" : "黑")方走棋 · \(model.frames[0].replies.count) 个合法走法").accessibilityIdentifier("positionTurn")
            Text(record.initialFEN).font(.caption.monospaced()).textSelection(.enabled).accessibilityIdentifier("positionFEN")
            if let value = model.report?.evaluations.first {
                Text(value.label).font(.headline).accessibilityIdentifier("positionScore")
                Text("Stockfish · 实际深度 \(value.depth) · 限时估值可能遗漏更深战术").font(.caption).foregroundStyle(.secondary)
                if !value.pv.isEmpty {
                    Button("查看候选与变化") { evidence = EvidenceReplay(title:"局面候选与变化",fen:record.initialFEN,moves:value.pv,prefix:0) }.accessibilityIdentifier("positionEvidence")
                }
            }
        }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:12))
    }
    private var replayControls: some View {
        VStack(spacing:2) {
            Text(ply == 0 ? "开局" : "\(ply) / \(record.moves.count) · \(model.frames[ply].san)").font(.subheadline.monospacedDigit()).accessibilityIdentifier("reviewPly")
            HStack {
                Button { ply = 0 } label: { Image(systemName:"backward.end.fill").frame(maxWidth:.infinity,minHeight:44) }.accessibilityLabel("回到开局").disabled(ply == 0)
                Button { ply = max(0,ply-1) } label: { Image(systemName:"chevron.left").frame(maxWidth:.infinity,minHeight:44) }.accessibilityLabel("上一步").accessibilityIdentifier("reviewPrevious").disabled(ply == 0)
                Button { ply = min(record.moves.count,ply+1) } label: { Image(systemName:"chevron.right").frame(maxWidth:.infinity,minHeight:44) }.accessibilityLabel("下一步").accessibilityIdentifier("reviewNext").disabled(ply == record.moves.count)
                Button { ply = record.moves.count } label: { Image(systemName:"forward.end.fill").frame(maxWidth:.infinity,minHeight:44) }.accessibilityLabel("跳到最后").disabled(ply == record.moves.count)
            }.background(.white,in:RoundedRectangle(cornerRadius:8))
        }
    }
    private var analysisControls: some View {
        VStack(alignment:.leading,spacing:10) {
            Label("AI Coach · 看懂这一手",systemImage:"sparkles").font(.headline)
            Picker("分析质量",selection:$model.duration) { Text("快速").tag(450); Text("细致").tag(1400) }.pickerStyle(.segmented).disabled(model.running).accessibilityIdentifier("analysisQuality")
            rowLayout {
                Text(record.moves.isEmpty ? (model.running ? "正在分析局面…" : model.report == nil ? "尚未分析局面" : "局面分析完成") : model.running ? "已分析 \(min(record.moves.count,max(0,model.completed-1))) / \(record.moves.count) 步" : "已分析 \(model.results.count) / \(record.moves.count) 步").font(.subheadline).accessibilityIdentifier("analysisProgress")
                if !textSize.isAccessibilitySize { Spacer() }
                if model.running { Button("取消") { model.cancel() }.accessibilityIdentifier("cancelAnalysis") }
                else { Button(model.report == nil ? (record.moves.isEmpty ? "分析局面" : "分析整局") : "重新分析") { model.analyze { game.saveReview($0,record:record) } }.accessibilityIdentifier("analyzeGame") }
            }.frame(minHeight:44)
            if model.running { ProgressView(value:Double(model.completed),total:Double(record.moves.count+1)) }
            if let error = model.error {
                Text(error + "。棋谱已保留，可点上方按钮重试。")
                    .font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("analysisError")
            }
            Text("Stockfish 19 lite 在本机分析；规则讲解，不是大模型对话。取消后保留上一份完整报告。").font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:12))
    }
    private func accuracyCard(_ report: GameReviewReport) -> some View {
        VStack(alignment:.leading,spacing:10) {
            Text(report.gameComplete ? "整局准确度" : "当前棋谱准确度 · 棋局未结束").font(.headline)
            rowLayout {
                accuracyNumber("白方\(record.source != nil ? "" : record.human == "w" ? " · 你" : " · 电脑")",value:report.white).accessibilityIdentifier("whiteAccuracy")
                if !textSize.isAccessibilitySize { Spacer() }
                accuracyNumber("黑方\(record.source != nil ? "" : record.human == "b" ? " · 你" : " · 电脑")",value:report.black).accessibilityIdentifier("blackAccuracy")
            }
            DisclosureGroup("评分口径") {
                Text("与弈外网站使用相同 lite 引擎与准确度公式。分别汇总双方走法，结合局势波动和调和平均；不是简单的好棋占比，也不是 Elo。限时搜索会受设备性能影响，数值可能波动。将死单独显示，准确度计算按网站映射处理。").font(.caption)
                Text("\(report.engine) · \(report.duration) ms / 局面 · 实际深度 \(report.minDepth)–\(report.maxDepth)").font(.caption2).foregroundStyle(.secondary)
            }.font(.caption)
        }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:12))
    }
    private func accuracyNumber(_ title: String,value: Double?) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.subheadline)
            Text(value.map { String(format:"%.1f%%",$0) } ?? "暂无走子").font(.system(.title,design:.rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Palette.sage)
        }.accessibilityElement(children:.combine)
    }
    private func coachCard(_ entry: ReviewedMove) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text("\(entry.moveLabel) · \(entry.label)").font(.headline).accessibilityIdentifier("coachTitle")
            Text(entry.coach.summary).font(.subheadline.weight(.medium))
            VStack(alignment:.leading,spacing:6) {
                Text("为什么比较这一步").font(.subheadline.weight(.semibold))
                Text(entry.coach.why)
                Text("实际走法漏看了什么").font(.subheadline.weight(.semibold)).padding(.top,4)
                Text(entry.coach.missed)
            }.font(.subheadline).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("coachExplanation")
            evidenceButton("本次首选",moves:entry.bestPV,sans:entry.coach.bestSAN,entry:entry)
            evidenceButton("实际走法的应对",moves:entry.playedPV,sans:entry.coach.playedSAN,entry:entry)
            if let report = model.report {
                Text("落子前 \(report.evaluations[entry.ply-1].label) → 落子后 \(report.evaluations[entry.ply].label)").font(.caption).foregroundStyle(.secondary)
            }
            Text(entry.coach.habit).font(.subheadline.weight(.medium))
            Text(entry.coach.boundary).font(.caption).foregroundStyle(.secondary)
        }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:12))
    }
    private func evidenceButton(_ title: String,moves: [String],sans: [String],entry: ReviewedMove) -> some View {
        Button { evidence = EvidenceReplay(title:title,fen:record.initialFEN,moves:Array(record.moves.prefix(entry.ply-1))+moves,prefix:entry.ply-1,flipped:record.human == "b") } label: {
            VStack(alignment:.leading,spacing:5) {
                Label(title,systemImage:"play.circle").font(.subheadline.weight(.semibold))
                Text(sans.joined(separator:" ")).font(.subheadline.monospaced()).multilineTextAlignment(.leading)
            }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(Palette.paper,in:RoundedRectangle(cornerRadius:8))
        }.accessibilityIdentifier(title == "本次首选" ? "bestEvidence" : "playedEvidence")
    }
}
struct EvidenceView: View {
    let item: EvidenceReplay
    @Environment(\.dismiss) var dismiss
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var frames: [ChessFrame] = []
    @State private var index = 0
    @State private var error: String?
    var body: some View {
        NavigationStack { ScrollView { VStack(spacing:18) {
            Text("参考变化线 · 对手实际可能选择其他走法").font(.subheadline).foregroundStyle(.secondary)
            if frames.indices.contains(index) {
                GameBoard(frame:frames[index],flipped:item.flipped)
                Text(index == 0 ? "落子前局面" : "\(index) / \(frames.count-1) · \(frames[index].san)").accessibilityIdentifier("evidencePly")
                let controls = textSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)) : AnyLayout(HStackLayout())
                controls { Button("上一步") { index = max(0,index-1) }.disabled(index == 0); if !textSize.isAccessibilitySize { Spacer() }; Button("下一步") { index = min(frames.count-1,index+1) }.disabled(index == frames.count-1).accessibilityIdentifier("evidenceNext") }.buttonStyle(.bordered).frame(minHeight:44)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.padding(20) }.background(Palette.paper).navigationTitle(item.title).navigationBarTitleDisplayMode(.inline).toolbar { Button("完成") { dismiss() } }
            .task { do { frames = Array(try ChessEngine().frames(fen:item.fen,moves:item.moves).dropFirst(item.prefix)) } catch { self.error = error.localizedDescription } }
        }
    }
}
