import Foundation
import Combine

struct ReviewEntry: Codable, Identifiable {
    let id: String
    var mistakes: Int
    var attempts: Int
    var lastPracticed: Date
    var mastered: Bool
    var note: String
}
@MainActor final class Notebook: ObservableObject {
    @Published private(set) var entries: [ReviewEntry] = []
    @Published var errorMessage: String?
    private let file: URL
    private var readFailed = false
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("YiwaiPractice/notebook.json")
        do {
            if FileManager.default.fileExists(atPath:self.file.path) {
                entries = try JSONDecoder().decode([ReviewEntry].self,from:Data(contentsOf:self.file))
            }
        } catch { readFailed = true; errorMessage = "错题本暂时无法读取，原文件已保留。请保留 App 数据后再排查。" }
    }
    func contains(_ id: String) -> Bool { entries.contains { $0.id == id } }
    func record(_ id: String, correct: Bool) {
        if let i = entries.firstIndex(where:{$0.id == id}) {
            entries[i].attempts += 1
            entries[i].mistakes += correct ? 0 : 1
            entries[i].lastPracticed = Date()
            entries[i].mastered = correct
        } else if !correct {
            entries.insert(ReviewEntry(id:id,mistakes:1,attempts:1,lastPracticed:Date(),mastered:false,note:""),at:0)
        }
        persist()
    }
    func save(_ id: String) {
        guard !contains(id) else { return }
        entries.insert(ReviewEntry(id:id,mistakes:0,attempts:0,lastPracticed:Date(),mastered:false,note:""),at:0)
        persist()
    }
    func setNote(_ id: String, text: String) {
        guard let i = entries.firstIndex(where:{$0.id == id}) else { return }
        entries[i].note = String(text.prefix(500)); persist()
    }
    func remove(_ id: String) { entries.removeAll { $0.id == id }; persist() }
    private func persist() {
        guard !readFailed else { return }
        do {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(entries).write(to:file,options:.atomic)
        } catch { errorMessage = "这次未能保存到设备。请检查可用空间；当前记录仍在本次会话中。" }
    }
}
