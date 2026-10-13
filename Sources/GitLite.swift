import Foundation

struct Record: Codable, Equatable { let path: String; let size: UInt64; let modified: TimeInterval }
struct Index: Codable { var files: [Record] }
struct Commit: Codable { let id: String; let message: String; let date: TimeInterval; let files: [Record] }

final class Repo {
    let root: URL
    let meta: URL
    let fm = FileManager.default
    init(_ root: URL) { self.root = root.standardizedFileURL; self.meta = self.root.appendingPathComponent(".gitlite") }
    var indexURL: URL { meta.appendingPathComponent("index.json") }
    var commitsURL: URL { meta.appendingPathComponent("commits") }
    func require() throws { if !fm.fileExists(atPath: meta.path) { throw NSError(domain: "GitLite", code: 1, userInfo: [NSLocalizedDescriptionKey: "Not a GitLite repository"]) } }
    func write<T: Encodable>(_ value: T, _ url: URL) throws { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; try e.encode(value).write(to: url, options: .atomic) }
    func read<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T { try JSONDecoder().decode(type, from: Data(contentsOf: url)) }
    func initRepo() throws { try fm.createDirectory(at: commitsURL, withIntermediateDirectories: true); if !fm.fileExists(atPath: indexURL.path) { try write(Index(files: []), indexURL) }; print("Initialized GitLite repository: \(meta.path)") }
    func collect(_ url: URL, _ out: inout [String: Record]) throws {
        var dir = ObjCBool(false); guard fm.fileExists(atPath: url.path, isDirectory: &dir) else { return }
        if dir.boolValue { if url.lastPathComponent == ".gitlite" { return }; for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) { try collect(child, &out) }; return }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"; let path = String(url.path.dropFirst(prefix.count)); let a = try fm.attributesOfItem(atPath: url.path); let size = (a[.size] as? NSNumber)?.uint64Value ?? 0; let date = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0; out[path] = Record(path: path, size: size, modified: date)
    }
    func add() throws { try require(); var files: [String: Record] = [:]; try collect(root, &files); try write(Index(files: files.values.sorted { $0.path < $1.path }), indexURL); print("Added \(files.count) file(s)") }
    func status() throws { try require(); let index = try read(Index.self, indexURL); var now: [String: Record] = [:]; try collect(root, &now); var count = 0; for r in index.files { if now[r.path] == nil { print(" D \(r.path)"); count += 1 } else if now[r.path]! != r { print(" M \(r.path)"); count += 1 } }; for r in now.values.sorted(by: { $0.path < $1.path }) where !index.files.contains(where: { $0.path == r.path }) { print("?? \(r.path)"); count += 1 }; if count == 0 { print("clean") } }
    func commit(_ message: String) throws { try require(); let index = try read(Index.self, indexURL); let id = String(format: "%016llx", UInt64(Date().timeIntervalSince1970 * 1000000)); let c = Commit(id: id, message: message, date: Date().timeIntervalSince1970, files: index.files); try write(c, commitsURL.appendingPathComponent(id + ".json")); print("[\(id)] \(message)") }
    func log() throws { try require(); let list = try fm.contentsOfDirectory(at: commitsURL, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }; if list.isEmpty { print("No commits") }; for u in list { let c = try read(Commit.self, u); print("\(c.id)  \(c.message)") } }
}

let argv = Array(CommandLine.arguments.dropFirst()); guard let cmd = argv.first else { print("GitLite: init, add, status, commit -m MESSAGE, log"); exit(0) }; let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath); var rest = Array(argv.dropFirst()); var root = cwd; if let p = rest.first, !p.hasPrefix("-") { root = URL(fileURLWithPath: p, relativeTo: cwd).standardizedFileURL; rest.removeFirst() }; let repo = Repo(root)
do {
    switch cmd { case "init": try repo.initRepo(); case "add": try repo.add(); case "status": try repo.status(); case "log": try repo.log(); case "commit": guard rest.count >= 2, rest[0] == "-m" else { throw NSError(domain: "GitLite", code: 2, userInfo: [NSLocalizedDescriptionKey: "Usage: commit [path] -m message"]) }; try repo.commit(rest.dropFirst().joined(separator: " ")); default: print("GitLite: init, add, status, commit -m MESSAGE, log") }
} catch { fputs("gitlite: \(error.localizedDescription)\n", stderr); exit(1) }
