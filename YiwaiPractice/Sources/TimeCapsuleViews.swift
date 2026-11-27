import SwiftUI
import UniformTypeIdentifiers

enum CapsuleExportName {
    static func make(date: Date, id: UUID) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.calendar = Calendar(identifier:.gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT:0)
        formatter.dateFormat = "yyyy-MM-dd'T'HHmmss'Z'"
        return "Yiwai-Time-Capsule-\(formatter.string(from:date))-\(id.uuidString)"
    }
}

struct CapsuleDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents:data) }
}

struct TimeCapsuleView: View {
    @EnvironmentObject private var game: GameController
    @EnvironmentObject private var notebook: Notebook
    @EnvironmentObject private var decisions: DecisionStore
    @EnvironmentObject private var conditionStudy: ConditionStudyStore
    @EnvironmentObject private var personal: PersonalStore
    @EnvironmentObject private var fortressProgress: FortressProgressStore
    @State private var document: CapsuleDocument?
    @State private var exportFilename = "Yiwai-Time-Capsule"
    @State private var exporting = false
    @State private var preparing = false
    @State private var message: String?
    @State private var error: String?
    @State private var jobID = UUID()
    @State private var confirmStudyEnd = false
    private static let queue = DispatchQueue(label:"yiwai.capsule-export",qos:.userInitiated)
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                VStack(alignment:.leading,spacing:12) {
                    Label("留一份自己的记录",systemImage:"archivebox")
                        .font(.caption.weight(.semibold)).foregroundStyle(Palette.sage)
                    Text("把棋局和想法，\n一起留下。")
                        .font(.system(.largeTitle,design:.serif).weight(.regular))
                    Text("本机共有 \(game.records.count) 盘棋谱、\(notebook.entries.count) 条错题本记录。")
                        .font(.subheadline).foregroundStyle(Palette.muted).accessibilityIdentifier("capsuleCounts")
                }
                VStack(alignment:.leading,spacing:16) {
                    Button {
                        if !decisions.demonstration && (conditionStudy.activeRun != nil || personal.data.cases.contains(where:{$0.active != nil})) { confirmStudyEnd = true } else { prepare() }
                    } label: {
                        Label(preparing ? "正在准备…" : "导出本地时间胶囊",systemImage:"square.and.arrow.down")
                            .frame(maxWidth:.infinity,minHeight:44)
                    }.buttonStyle(YiwaiActionStyle()).disabled(preparing).accessibilityIdentifier("exportCapsule")
                    if preparing { ProgressView("正在整理本机记录…").font(.subheadline) }
                    if let message { Text(message).font(.subheadline).foregroundStyle(Palette.sage).accessibilityIdentifier("capsuleResult") }
                    if let error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("capsuleError") }
                    VStack(alignment:.leading,spacing:10) {
                        Text("只存本机时，请在系统文件选择器中选「我的 iPhone」或「我的 iPad」。")
                        Text("文件包含棋谱与备注，请自行保管；不会自动同步，也不承诺永久保存。")
                        Text("导出的是可阅读的 JSON 文件，当前尚无整包恢复入口。")
                    }.font(.subheadline).foregroundStyle(Palette.muted)
                }.yiwaiSurface()
                Label {
                    Text("完整导出包含答案。如果有进行中的对照或个人练习，会先请你确认是否结束；也可以取消，继续练习。")
                        .fixedSize(horizontal:false,vertical:true)
                } icon: {
                    Image(systemName:"info.circle").foregroundStyle(Palette.sage)
                }.font(.subheadline).foregroundStyle(Palette.muted)
                DisclosureGroup {
                    VStack(alignment:.leading,spacing:18) {
                        capsuleDetail("棋谱与备注", "全部棋谱、起始局面、主线 PGN、个人备注与已保存的复盘分析。")
                        capsuleDetail("原文与错题", "新导入 PGN 的原始文本，包括注释和变例；错题本记录、备注及对应内置题目。")
                        capsuleDetail("理由与复习", "棋谱执棋方确认、规则扫描与重复证据；决策回炉的原局面、用户理由及来源、标签修订、题目版本、提示与首次作答、到期时间及本主题复习进度。")
                        capsuleDetail("个人棋谱实验", "原文、棋规事实、引擎证据、合法分支、首答、事后回忆及匹配练习与延后复测。")
                        capsuleDetail("不败空间课程", "四章课程的完整题目定义、首答、最近作答及次数；重做不会覆盖首答。示例空间导出不包含个人课程记录。")
                        capsuleDetail("条件对照", "版本化题目、合法 PGN 证明、引擎记录、题序与种子、首答、排除理由、反馈后重试及补记。")
                    }.padding(.top,16)
                } label: {
                    Text("完整导出包含什么").font(.headline).foregroundStyle(Palette.ink)
                }.yiwaiSurface()
                if game.records.contains(where:{$0.source == "pgn" && $0.originalPGN == nil}) {
                    Text("部分棋谱由旧版导入，只有已保存的主线；旧版未保留的注释或变例无法恢复。")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
            }.padding(20).frame(maxWidth:640).frame(maxWidth:.infinity,alignment:.center)
        }.background(Palette.paper).foregroundStyle(Palette.ink)
        .navigationTitle("时间胶囊").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:exportFilename) { result in
            switch result {
            case .success: message = "时间胶囊已导出到你选择的位置。"; error = nil
            case .failure(let failure): message = nil; error = "导出未完成：\(failure.localizedDescription)"
            }
            document = nil
        }
        .alert("完整导出会暴露对照答案",isPresented:$confirmStudyEnd) {
            Button("继续保留未完成练习",role:.cancel) {}
            Button("结束对照并导出") {
                Task {
                    await conditionStudy.prepare()
                    do { if let active=conditionStudy.activeRun { try conditionStudy.finish(active.id,expose:decisions.recordExposure) };for item in personal.data.cases where item.active != nil {try personal.finish(item.id,expose:decisions.recordExposure)};prepare() }
                    catch { self.error=error.localizedDescription }
                }
            }
        } message: { Text("未提交保持缺失。结束后，这组相关题不再计入首次独立比较；可取消返回练习。") }
        .onDisappear { jobID = UUID() }
    }
    private func capsuleDetail(_ title: String, _ detail: String) -> some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(detail).font(.subheadline).foregroundStyle(Palette.muted)
                .fixedSize(horizontal:false,vertical:true)
        }
    }
    private func prepare() {
        message = nil; error = nil
        do {
            let games = try game.capsuleRecords(), entries = try notebook.capsuleEntries()
            let decisionData = try decisions.exportArchive()
            let conditionData = decisions.demonstration ? nil : try conditionStudy.exportArchive()
            let personalData = decisions.demonstration ? nil : try personal.exportArchive()
            let fortressData = decisions.demonstration ? nil : try fortressProgress.exportArchive()
            let fortressLessons = try FortressCourseCatalog.load()
            let version = (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown")
                + " (" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown") + ")"
            let id = UUID(); jobID = id; preparing = true
            let filename = CapsuleExportName.make(date:Date(),id:id)
            Self.queue.async {
                let result = Result { try TimeCapsule.build(games:games,notebook:entries,appVersion:version,decisions:decisionData,conditionStudy:conditionData,personalEvidence:personalData,fortressProgress:fortressData,fortressLessons:fortressLessons).encoded() }
                DispatchQueue.main.async {
                    guard jobID == id else { return }
                    preparing = false
                    switch result {
                    case .success(let data): exportFilename = filename; document = CapsuleDocument(data:data); exporting = true
                    case .failure(let failure): error = "无法完整导出：\(failure.localizedDescription)"
                    }
                }
            }
        } catch { self.error = error.localizedDescription }
    }
}

struct GameNoteView: View {
    let recordID: UUID
    @EnvironmentObject private var game: GameController
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var error: String?
    @FocusState private var focused: Bool
    init(recordID: UUID, note: String) { self.recordID = recordID; _text = State(initialValue:note) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    VStack(alignment:.leading,spacing:8) {
                        Text("留一点当时的想法").font(.system(.title2,design:.serif).weight(.semibold))
                        Text("候选着、没想明白的地方，或这盘棋的一个小细节。")
                            .font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    VStack(alignment:.leading,spacing:12) {
                        TextEditor(text:$text).frame(minHeight:210).focused($focused)
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("这盘棋的个人备注").accessibilityIdentifier("personalNoteInput")
                        Text("\(text.count) / 10,000 字").font(.caption.monospacedDigit())
                            .foregroundStyle(text.count > 10000 ? Color.red : Palette.muted)
                        if let error { Text(error).font(.subheadline).foregroundStyle(.red).accessibilityIdentifier("personalNoteError") }
                    }.yiwaiSurface()
                    Text("点「保存」后生效。备注只保存在本机，也会包含在时间胶囊导出中。")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }.padding(20).frame(maxWidth:640).frame(maxWidth:.infinity)
            }.background(Palette.paper).foregroundStyle(Palette.ink)
            .navigationTitle("个人备注").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement:.confirmationAction) {
                    Button("保存") {
                        do { try game.savePersonalNote(recordID,text:text); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(text.count > 10000).accessibilityIdentifier("savePersonalNote").keyboardShortcut("s",modifiers:.command)
                }
                ToolbarItemGroup(placement:.keyboard) { Spacer(); Button("收起键盘") { focused = false } }
            }
        }
    }
}
