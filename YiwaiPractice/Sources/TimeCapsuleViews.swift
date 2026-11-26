import SwiftUI
import UniformTypeIdentifiers

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
    @State private var document: CapsuleDocument?
    @State private var exporting = false
    @State private var preparing = false
    @State private var message: String?
    @State private var error: String?
    @State private var jobID = UUID()
    @State private var confirmStudyEnd = false
    private static let queue = DispatchQueue(label:"yiwai.capsule-export",qos:.userInitiated)
    var body: some View {
        Form {
            Section {
                Text("把棋局和当时的想法留在一起").font(.headline)
                Text("先在「棋谱」手动导入单盘 PGN，再打开这盘棋添加个人备注。无需连接棋站账号。")
                Text("本机共有 \(game.records.count) 盘棋谱、\(notebook.entries.count) 条错题本记录。").accessibilityIdentifier("capsuleCounts")
            }
            Section("完整导出包含") {
                Text("全部棋谱、起始局面、主线 PGN、个人备注与已保存的复盘分析。")
                Text("新导入 PGN 的原始文本，包括注释和变例；错题本记录、备注及对应内置题目。")
                Text("棋谱执棋方确认、规则扫描与重复证据；决策回炉的原局面、用户理由及来源、标签修订、题目版本、提示与首次作答、到期时间及本主题复习进度。")
                Text("个人棋谱实验的原文、棋规事实、引擎证据、合法分支、首答、事后回忆及匹配练习/延后复测。")
                Text("条件对照的版本化题目、合法 PGN 证明、引擎记录、题序与种子、首答、排除理由、反馈后重试及补记。完整导出含答案，进行中的对照需先结束。")
                if game.records.contains(where:{$0.source == "pgn" && $0.originalPGN == nil}) {
                    Text("部分棋谱由旧版导入，只有已保存的主线；旧版未保留的注释或变例无法恢复。").foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    if !decisions.demonstration && (conditionStudy.activeRun != nil || personal.data.cases.contains(where:{$0.active != nil})) { confirmStudyEnd = true } else { prepare() }
                } label: {
                    Label(preparing ? "正在准备…" : "导出本地时间胶囊",systemImage:"square.and.arrow.down")
                        .frame(minHeight:44)
                }.disabled(preparing).accessibilityIdentifier("exportCapsule")
                if preparing { ProgressView() }
                if let message { Text(message).accessibilityIdentifier("capsuleResult") }
                if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("capsuleError") }
            } footer: {
                Text("生成可阅读的 JSON 文件。若只存本机，请在文件选择器选择「我的 iPhone」。文件包含棋谱与备注，请自行保管；不会自动同步。当前版本尚无整包恢复入口，也不承诺永久保存。")
            }
        }.navigationTitle("时间胶囊").navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"Yiwai-Time-Capsule-\(Date().formatted(.iso8601.year().month().day().dateSeparator(.dash)))") { result in
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
    private func prepare() {
        message = nil; error = nil
        do {
            let games = try game.capsuleRecords(), entries = try notebook.capsuleEntries()
            let decisionData = try decisions.exportArchive()
            let conditionData = decisions.demonstration ? nil : try conditionStudy.exportArchive()
            let personalData = decisions.demonstration ? nil : try personal.exportArchive()
            let version = (Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown")
                + " (" + (Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "unknown") + ") local capsule prototype"
            let id = UUID(); jobID = id; preparing = true
            Self.queue.async {
                let result = Result { try TimeCapsule.build(games:games,notebook:entries,appVersion:version,decisions:decisionData,conditionStudy:conditionData,personalEvidence:personalData).encoded() }
                DispatchQueue.main.async {
                    guard jobID == id else { return }
                    preparing = false
                    switch result {
                    case .success(let data): document = CapsuleDocument(data:data); exporting = true
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
            Form {
                Section {
                    TextEditor(text:$text).frame(minHeight:210).focused($focused)
                        .accessibilityLabel("这盘棋的个人备注").accessibilityIdentifier("personalNoteInput")
                    Text("\(text.count) / 10,000 字").font(.caption).foregroundStyle(text.count > 10000 ? .red : .secondary)
                    if let error { Text(error).foregroundStyle(.red).accessibilityIdentifier("personalNoteError") }
                } footer: { Text("记下当时的想法、疑问或背景。只保存在本机，包含在时间胶囊导出中。点保存后生效。") }
            }.navigationTitle("个人备注").navigationBarTitleDisplayMode(.inline)
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
