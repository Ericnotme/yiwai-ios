import SwiftUI

@main struct YiwaiApp: App {
    @StateObject private var notebook: Notebook
    @StateObject private var game: GameController
    @StateObject private var decisions: DecisionStore
    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-simulate-no-network") {
            URLProtocol.registerClass(OfflineTestProtocol.self)
        }
        #endif
        let testMode = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        let testFile = testMode ? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("YiwaiPractice/ui-test-notebook.json") : nil
        if ProcessInfo.processInfo.arguments.contains("-reset-test-data"), let testFile { try? FileManager.default.removeItem(at:testFile) }
        _notebook = StateObject(wrappedValue:Notebook(file:testFile))
        let gameFile = testMode ? testFile?.deletingLastPathComponent().appendingPathComponent("ui-test-games.json") : nil
        if ProcessInfo.processInfo.arguments.contains("-reset-test-data"), let gameFile { try? FileManager.default.removeItem(at:gameFile) }
        // Release UI tests use the real bundled engine with an isolated game file.
        if testMode, let gameFile, let fixture = ProcessInfo.processInfo.environment["YIWAI_UI_GAME_MOVES"],
           let data = fixture.data(using:.utf8), let moves = try? JSONDecoder().decode([String].self,from:data) {
            try? FileManager.default.createDirectory(at:gameFile.deletingLastPathComponent(),withIntermediateDirectories:true)
            try? JSONEncoder().encode([GameRecord(moves:moves,ending:"saved")]).write(to:gameFile,options:.atomic)
        }
        let controller = GameController(file:gameFile)
        #if DEBUG
        if testMode && ProcessInfo.processInfo.arguments.contains("-ui-promotion-fixture") {
            controller.newGame(human:"w",level:0,fen:"7k/P7/8/8/8/8/8/4K3 w - - 0 1")
        }
        #endif
        _game = StateObject(wrappedValue:controller)
        let decisionFile = testMode ? gameFile?.deletingLastPathComponent().appendingPathComponent("ui-test-decisions.json") : nil
        if testMode && ProcessInfo.processInfo.arguments.contains("-reset-test-data"), let decisionFile { try? FileManager.default.removeItem(at:decisionFile) }
        var decisionClock: () -> Date = Date.init
        var clockOrigin = "device clock"
        #if DEBUG
        if testMode, let dateText = ProcessInfo.processInfo.environment["YIWAI_UI_CLOCK"], let date = ISO8601DateFormatter().date(from:dateText) {
            decisionClock = { date }; clockOrigin = "injected UI test clock; synthetic data only"
        }
        #endif
        _decisions = StateObject(wrappedValue:DecisionStore(file:decisionFile,clock:decisionClock,clockOrigin:clockOrigin))
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(notebook).environmentObject(game).environmentObject(decisions).tint(Palette.coral).preferredColorScheme(.light) }
    }
}
#if DEBUG
// Test-only HTTP(S) failure injection. Does not change any host or device network setting.
final class OfflineTestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { ["http", "https"].contains(request.url?.scheme ?? "") }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self,didFailWithError:URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif
enum Palette {
    static let paper = Color(red:0.97,green:0.96,blue:0.94)
    static let ink = Color(red:0.14,green:0.20,blue:0.20)
    static let coral = Color(red:0.78,green:0.29,blue:0.21)
    static let sage = Color(red:0.29,green:0.42,blue:0.37)
}
struct RootView: View {
    @EnvironmentObject var notebook: Notebook
    @EnvironmentObject var game: GameController
    @State private var tab = ProcessInfo.processInfo.arguments.contains("-ui-testing") ? 0 : 3
    @State private var lessonIndex = 0
    @State private var positionIndex = 0
    @State private var session = UUID()
    var body: some View {
        TabView(selection:$tab) {
            GamePlayView().tabItem { Label("下棋",systemImage:"checkerboard.rectangle") }.tag(3)
            GameHistoryView { id in tab = 3; game.resume(id) }.tabItem { Label("棋谱",systemImage:"books.vertical") }.tag(4)
            PracticeView(lessonIndex:$lessonIndex,positionIndex:$positionIndex,session:$session).id(session)
                .tabItem { Label("练一题",systemImage:"checkerboard.rectangle") }.tag(0)
            NotebookView { id in
                for (i,lesson) in Lesson.all.enumerated() {
                    if let j = lesson.positions.firstIndex(where:{$0.id == id}) { lessonIndex = i; positionIndex = j; session = UUID(); tab = 0; break }
                }
            }.tabItem { Label("错题本",systemImage:"bookmark") }.tag(1)
            AboutView().tabItem { Label("关于",systemImage:"leaf") }.tag(2)
        }
        .alert("棋谱提示",isPresented:Binding(get:{game.errorMessage != nil},set:{if !$0 { game.errorMessage = nil }})) { Button("知道了",role:.cancel) { game.errorMessage = nil } } message: { Text(game.errorMessage ?? "") }
        .alert("本地保存提示",isPresented:Binding(get:{notebook.errorMessage != nil},set:{if !$0 { notebook.errorMessage = nil }})) {
            Button("知道了",role:.cancel) { notebook.errorMessage = nil }
        } message: { Text(notebook.errorMessage ?? "") }
    }
}

struct PracticeView: View {
    @Binding var lessonIndex: Int
    @Binding var positionIndex: Int
    @Binding var session: UUID
    @EnvironmentObject var notebook: Notebook
    @State private var frames: [ChessFrame] = []
    @State private var frameIndex = 0
    @State private var answer: Bool?
    @State private var engineError: String?
    @State private var chooseLesson = false
    @State private var playing = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var lesson: Lesson { Lesson.all[lessonIndex] }
    var position: Position { lesson.positions[positionIndex] }
    var correct: Bool { answer == position.isMate }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    HStack(alignment:.top) {
                        VStack(alignment:.leading,spacing:6) {
                            Text("弈外").font(.system(size:32,weight:.semibold,design:.serif))
                            Text("Second Look Chess").font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("englishBrand")
                            Text("每天看懂一个为什么").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { chooseLesson = true } label: { Label("换题",systemImage:"square.grid.2x2").font(.subheadline.weight(.medium)).padding(12).background(.white,in:Capsule()) }.accessibilityIdentifier("chooseLesson")
                    }
                    HStack { Text("\(String(format:"%02d",lessonIndex + 1))  /  \(lesson.title)").font(.subheadline.weight(.semibold)); Spacer(); Text("\(positionIndex + 1) / 3").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    VStack(alignment:.leading,spacing:12) {
                        HStack { Label("白先",systemImage:"circle.fill").font(.caption.weight(.semibold)); Spacer(); Text(answer == nil ? position.label : "逐步回放 · \(frameIndex) / \(frames.count - 1)").font(.caption).foregroundStyle(.secondary) }
                        if !frames.isEmpty {
                            BoardView(frame:frames[frameIndex],highlight:answer == nil ? [] : position.changed)
                        }
                        Text(answer == nil ? "试想 \(position.notation) 之后的局面" : position.cues[min(frameIndex,position.cues.count - 1)])
                            .font(.subheadline).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).accessibilityIdentifier("frameCue")
                    }.padding(14).background(.white,in:RoundedRectangle(cornerRadius:24))

                    if let engineError { Text(engineError).foregroundStyle(.red) }
                    else if answer == nil {
                        VStack(alignment:.leading,spacing:14) {
                            Text("\(position.notation) 后，是将死吗？").font(.title3.weight(.semibold)).accessibilityIdentifier("question")
                            Text("先在心里走一步，再检查黑方的应将。").font(.subheadline).foregroundStyle(.secondary)
                            adaptiveActions {
                                answerButton("是，将死",value:true,id:"answerMate")
                                answerButton("还能应将",value:false,id:"answerNotMate")
                            }
                        }
                    } else {
                        VStack(alignment:.leading,spacing:16) {
                            HStack(alignment:.top,spacing:10) {
                                Image(systemName:correct ? "checkmark.circle.fill" : "arrow.counterclockwise.circle.fill").foregroundStyle(correct ? Palette.sage : Palette.coral).font(.title2)
                                VStack(alignment:.leading,spacing:4) {
                                    Text(correct ? "判断正确" : "还有一个细节").font(.headline).accessibilityIdentifier("answerResult")
                                    Text(correct ? (notebook.contains(position.id) ? "本次已答对，记录仍保留在错题本。" : "接下来，把原因也看清楚。") : "已记入错题本，下次再试一次。").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack {
                                Button { playing = false; frameIndex = max(0,frameIndex - 1) } label: { Image(systemName:"backward.end.fill").frame(width:44,height:44) }.disabled(frameIndex == 0).accessibilityLabel("上一步").accessibilityIdentifier("previousFrame")
                                Spacer()
                                Button { if playing { playing = false } else { if frameIndex == frames.count - 1 { frameIndex = 0 }; playing = true } } label: { Label(playing ? "暂停" : "播放",systemImage:playing ? "pause.fill" : "play.fill").frame(minWidth:80,minHeight:44) }.accessibilityIdentifier("playReplay")
                                Spacer()
                                Button { playing = false; frameIndex = min(frames.count - 1,frameIndex + 1) } label: { Image(systemName:"forward.end.fill").frame(width:44,height:44) }.disabled(frameIndex == frames.count - 1).accessibilityLabel("下一步").accessibilityIdentifier("nextFrame")
                            }.background(Palette.paper,in:RoundedRectangle(cornerRadius:14))
                            Text(position.explanation).font(.body).lineSpacing(5).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("explanation")
                            Text(lesson.principle).font(.subheadline).foregroundStyle(Palette.sage).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Palette.sage.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
                            Button { playing = false; positionIndex = (positionIndex + 1) % lesson.positions.count; session = UUID() } label: { HStack { Text(positionIndex == 2 ? "回到起始题" : "换个局面验证").multilineTextAlignment(.leading); Spacer(); Image(systemName:"arrow.right") }.font(.headline).padding(16).foregroundStyle(.white).background(Palette.ink,in:RoundedRectangle(cornerRadius:16)) }.accessibilityIdentifier("nextPosition")
                            adaptiveActions {
                                Button { notebook.save(position.id) } label: { Label(notebook.contains(position.id) ? "已在错题本" : "留到错题本",systemImage:notebook.contains(position.id) ? "bookmark.fill" : "bookmark") }.disabled(notebook.contains(position.id)).accessibilityIdentifier("savePosition")
                                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                                Button("重做本题") { session = UUID() }.accessibilityIdentifier("retryPosition")
                            }.font(.subheadline).frame(minHeight:44)
                        }.padding(18).background(.white,in:RoundedRectangle(cornerRadius:22))
                    }
                    Label("原创练习 · 完全离线",systemImage:"wifi.slash").font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity)
                }.padding(.horizontal,20).padding(.top,14).padding(.bottom,24).frame(maxWidth:560)
            }.background(Palette.paper).foregroundStyle(Palette.ink).toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$chooseLesson) {
                NavigationStack { List(Array(Lesson.all.enumerated()),id:\.element.id) { index,item in
                    Button { lessonIndex = index; positionIndex = 0; session = UUID(); chooseLesson = false } label: { VStack(alignment:.leading,spacing:8) { Text(item.title).font(.headline); Text(item.subtitle).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical,10) }.accessibilityIdentifier("lesson-\(item.id)")
                }.navigationTitle("选择一个线索").toolbar { Button("完成") { chooseLesson = false } } }.presentationDetents([.medium,.large])
            }
            .task { do { let engine = try ChessEngine(); frames = try engine.frames(fen:position.fen,moves:position.line) } catch { engineError = "这道题暂时无法载入：\(error.localizedDescription)" } }
            .task(id:playing) {
                guard playing else { return }
                while playing && frameIndex < frames.count - 1 {
                    do { try await Task.sleep(for:.seconds(1.8)) } catch { return }
                    guard !Task.isCancelled && playing else { return }
                    if reduceMotion { frameIndex += 1 } else { withAnimation(.easeInOut(duration:0.25)) { frameIndex += 1 } }
                }
                playing = false
            }
            .onChange(of:scenePhase) { _,phase in if phase != .active { playing = false } }
            .onDisappear { playing = false }
        }
    }
    private func adaptiveActions<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)) : AnyLayout(HStackLayout(spacing:10))
        return layout { content() }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func answerButton(_ label: String,value: Bool,id: String) -> some View {
        Button { answer = value; notebook.record(position.id,correct:value == position.isMate); frameIndex = 0 } label: {
            Text(label).font(.headline).frame(maxWidth:.infinity,minHeight:54).foregroundStyle(value ? .white : Palette.ink).background(value ? Palette.coral : .white,in:RoundedRectangle(cornerRadius:16))
        }.accessibilityIdentifier(id).disabled(frames.isEmpty)
    }
}

struct BoardView: View {
    let frame: ChessFrame
    let highlight: [String]
    var body: some View {
        VStack(spacing:3) {
            GeometryReader { geometry in
                let cell = geometry.size.width / 8
                VStack(spacing:0) {
                    ForEach((1...8).reversed(),id:\.self) { rank in
                        HStack(spacing:0) {
                            ForEach(0..<8,id:\.self) { file in
                                let square = "\(Array("abcdefgh")[file])\(rank)"
                                let piece = frame.pieces.first { $0.square == square }
                                let moved = square == frame.to || square == frame.from
                                ZStack(alignment:.topLeading) {
                                    Rectangle().fill((file + rank) % 2 == 0 ? Color(red:0.82,green:0.86,blue:0.81) : Color(red:0.96,green:0.94,blue:0.88))
                                    if moved { Rectangle().fill(Color.yellow.opacity(0.35)) }
                                    if highlight.contains(square) { Rectangle().strokeBorder(Palette.coral.opacity(0.75),lineWidth:2) }
                                    if file == 0 { Text("\(rank)").font(.system(size:9,weight:.semibold)).foregroundStyle(Palette.ink.opacity(0.6)).padding(2) }
                                    if let piece {
                                        Text(piece.symbol).font(.system(size:cell * 0.80)).foregroundStyle(piece.color == "w" ? Color.white : Palette.ink)
                                            .shadow(color:Palette.ink.opacity(piece.color == "w" ? 0.8 : 0),radius:0.6,x:0,y:1)
                                            .shadow(color:Palette.ink.opacity(piece.color == "w" ? 0.8 : 0),radius:0.6,x:0,y:-1)
                                            .frame(width:cell,height:cell)
                                    }
                                }.frame(width:cell,height:cell).accessibilityElement(children:.ignore).accessibilityLabel("\(square)，\(piece?.name ?? "空格")")
                            }
                        }
                    }
                }.clipShape(RoundedRectangle(cornerRadius:8))
            }.aspectRatio(1,contentMode:.fit)
            HStack(spacing:0) { ForEach(Array("abcdefgh"),id:\.self) { file in Text(String(file)).font(.system(size:10,weight:.medium)).foregroundStyle(.secondary).frame(maxWidth:.infinity) } }.accessibilityHidden(true)
        }.accessibilityIdentifier("chessBoard")
    }
}

struct NotebookView: View {
    @EnvironmentObject var notebook: Notebook
    let retry: (String) -> Void
    var body: some View {
        NavigationStack {
            Group {
                if notebook.entries.isEmpty {
                    ContentUnavailableView { Label("把没想通的，留下来",systemImage:"bookmark") } description: { Text("答错的局面会自动记在这里。\n也可以在讲解后主动收藏。") } actions: { Text("只保存在这台设备，无需登录。").font(.caption).foregroundStyle(.secondary) }
                } else {
                    List {
                        Section { Text("\(notebook.entries.filter { !$0.mastered }.count) 道待巩固 · \(notebook.entries.filter(\.mastered).count) 道最近答对").font(.subheadline).foregroundStyle(.secondary) }
                        ForEach(notebook.entries) { entry in
                            if let lesson = Lesson.all.first(where:{$0.positions.contains(where:{$0.id == entry.id})}), let position = lesson.positions.first(where:{$0.id == entry.id}) {
                                VStack(alignment:.leading,spacing:12) {
                                    HStack { Text(lesson.title).font(.headline); Spacer(); if entry.mastered { Image(systemName:"checkmark.circle.fill").foregroundStyle(Palette.sage).accessibilityLabel("最近答对") } }
                                    Text("\(position.label) · \(position.notation) 后的判断").font(.subheadline).foregroundStyle(.secondary)
                                    Text(entry.mistakes == 0 ? "主动收藏" : "答错 \(entry.mistakes) 次 · 练习 \(entry.attempts) 次").font(.caption).foregroundStyle(.secondary)
                                    TextField("给自己留一句提醒",text:Binding(get:{notebook.entries.first(where:{$0.id == entry.id})?.note ?? ""},set:{notebook.setNote(entry.id,text:$0)}),axis:.vertical).font(.subheadline).accessibilityIdentifier("note-\(entry.id)")
                                    Button { retry(entry.id) } label: { Label("再练一次",systemImage:"arrow.counterclockwise").font(.subheadline.weight(.semibold)).frame(minHeight:38) }.accessibilityIdentifier("review-\(entry.id)")
                                }.padding(.vertical,8).swipeActions { Button("移除",role:.destructive) { notebook.remove(entry.id) } }
                            }
                        }
                        Section { Text("数据仅保存在本机。卸载 App 会删除记录；本版不提供云同步。").font(.caption).foregroundStyle(.secondary) }
                    }.scrollContentBackground(.hidden)
                }
            }.background(Palette.paper).navigationTitle("错题本")
        }
    }
}
struct AboutView: View {
    @State private var showLicense = false
    @State private var licenseText = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment:.leading,spacing:12) {
                        Text("弈外").font(.title2.weight(.semibold))
                        Text("Second Look Chess").font(.headline).accessibilityIdentifier("englishBrand")
                        Text("不急着多走一步。\n先把这一步的道理看清。").font(.body).lineSpacing(5)
                        Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") · 原生 iPhone 版").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical,14)
                }
                Section("本版能做什么") {
                    Label("离线人机、完整棋谱与 PGN 导出",systemImage:"person.fill")
                    Label("整局复盘与离线 AI Coach",systemImage:"sparkles")
                    Label("3 组原创练习，9 个局面",systemImage:"checkerboard.rectangle")
                    Label("准确应将验证与逐步回放",systemImage:"play.rectangle")
                    Label("本地错题本与复习笔记",systemImage:"bookmark")
                }
                Section("只在你的设备上") {
                    Text("练习、棋规和记录均离线运行，无账号、无广告、无分析追踪。不会申请通知权限。")
                    Text("支持 FEN 局面与 PGN 棋谱导入、离线分析及 PGN 导出。导入保存在本机；在线对战和跨设备同步尚未加入。")
                }.font(.subheadline)
                Section("隐私与支持") {
                    NavigationLink("隐私政策") { PrivacyPolicyView() }.accessibilityIdentifier("privacyPolicy")
                    Link("支持与问题反馈",destination:URL(string:"https://github.com/Ericnotme/yiwai-ios/issues")!)
                    Text("隐私政策可离线阅读。在线反馈会打开 GitHub，请勿在公开问题中提供私人资料。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("内容与许可") {
                    Text("局面与讲解改编自弈外 / Knight Room 的原创练习。棋规使用 chess.js 1.4.0；对弈电脑为 Seed 0.2，未评级；复盘使用 Stockfish.js 19 lite。教练依据棋规和引擎讲解，不是大模型。原生页面参考 Lichess 的棋盘与操作布局，保留弈外设计；未复制其代码或图标。")
                    Button("查看 chess.js BSD-2-Clause 许可") { openLicense("chess-LICENSE") }
                    Button("查看 Stockfish GPL-3.0 许可") { openLicense("stockfish19-LICENSE",directory:"Stockfish") }
                    if let url = Bundle.main.url(forResource:"stockfish19-source",withExtension:"tar.gz",subdirectory:"Stockfish") {
                        ShareLink("导出 Stockfish 对应源码与构建脚本",item:url)
                    }
                }.font(.subheadline)
            }.scrollContentBackground(.hidden).background(Palette.paper).navigationTitle("关于弈外")
                .sheet(isPresented:$showLicense) { NavigationStack { ScrollView { Text(licenseText).font(.caption.monospaced()).padding() }.navigationTitle("第三方许可").toolbar { Button("完成") { showLicense = false } } } }
        }
    }
    private func openLicense(_ name: String,directory: String? = nil) {
        licenseText = Bundle.main.url(forResource:name,withExtension:"txt",subdirectory:directory).flatMap { try? String(contentsOf:$0,encoding:.utf8) } ?? "许可文件不可读"
        showLicense = true
    }
}

struct PrivacyPolicyView: View {
    private var policy: String {
        Bundle.main.url(forResource:"PrivacyPolicy",withExtension:"txt")
            .flatMap { try? String(contentsOf:$0,encoding:.utf8) } ?? "隐私政策文件暂时不可读，请通过下方在线入口查看。"
    }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                Text(policy).font(.body).textSelection(.enabled).accessibilityIdentifier("privacyPolicyContent")
                Link("查看在线隐私政策",destination:URL(string:"https://github.com/Ericnotme/yiwai-ios/blob/main/PRIVACY.md")!)
            }.padding()
        }.background(Palette.paper).navigationTitle("隐私政策").navigationBarTitleDisplayMode(.inline)
    }
}
