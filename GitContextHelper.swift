import Foundation

struct GitSnapshot: Sendable {
    let branch: String
    let statusShort: String
    let diffStat: String
    let diffExcerpt: String
    let changedFiles: [String]
}

enum GitContextHelper {
    private static let maxDiffChars = 18_000
    private static let maxSingleFileBytes = 32 * 1024
    private static let maxBundleBytes = 96 * 1024

    static func captureSnapshot(at workspacePath: String) -> GitSnapshot? {
        let dir = (workspacePath as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        guard let inside = runGit(["rev-parse", "--is-inside-work-tree"], cwd: dir),
              inside.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return nil
        }

        let branch = runGit(["rev-parse", "--abbrev-ref", "HEAD"], cwd: dir)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "HEAD"
        let statusRaw = runGit(["status", "--short"], cwd: dir)?
            .trimmingCharacters(in: .newlines) ?? ""
        let diffStat = runGit(["diff", "--stat", "HEAD"], cwd: dir)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? runGit(["diff", "--stat"], cwd: dir)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        let rawDiff = runGit(["diff", "HEAD"], cwd: dir)
            ?? runGit(["diff"], cwd: dir)
            ?? ""

        let diffExcerpt = rawDiff.count > maxDiffChars
            ? String(rawDiff.prefix(maxDiffChars)) + "\n... [Diff 已截断，共 \(rawDiff.count) 字符]"
            : rawDiff

        var files: [String] = []
        for line in statusRaw.split(separator: "\n") {
            let text = String(line)
            guard text.count > 3 else { continue }
            var rel = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            if let arrow = rel.range(of: " -> ") {
                rel = String(rel[arrow.upperBound...])
            }
            if rel.hasPrefix("\"") && rel.hasSuffix("\"") && rel.count >= 2 {
                rel = String(rel.dropFirst().dropLast())
            }
            if rel.isEmpty || rel.contains("__pycache__") || rel.hasSuffix(".DS_Store") || rel.hasSuffix("/") {
                continue
            }
            let full = URL(fileURLWithPath: dir).appendingPathComponent(rel).path
            var isSubDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: full, isDirectory: &isSubDir), !isSubDir.boolValue {
                files.append(full)
            }
        }

        return GitSnapshot(
            branch: branch,
            statusShort: statusRaw,
            diffStat: diffStat,
            diffExcerpt: diffExcerpt,
            changedFiles: files
        )
    }

    static func formatSnapshotMarkdown(_ snapshot: GitSnapshot) -> String {
        var sections: [String] = []
        sections.append("分支：`\(snapshot.branch)`")
        if !snapshot.statusShort.isEmpty {
            sections.append("变更文件：\n```\n\(snapshot.statusShort)\n```")
        } else {
            sections.append("工作区当前干净（无未提交改动）。")
        }
        if !snapshot.diffStat.isEmpty {
            sections.append("Diff 统计：\n```\n\(snapshot.diffStat)\n```")
        }
        if !snapshot.diffExcerpt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Diff 摘录：\n```diff\n\(snapshot.diffExcerpt)\n```")
        }
        return sections.joined(separator: "\n\n")
    }

    static func packGeminiContext(packet: Packet, thread: ConversationThread?) -> (text: String, skippedFiles: [String]) {
        var parts: [String] = ["# \(packet.subject)", packet.body]
        if let ws = thread?.workspacePath ?? packet.workspacePath, !ws.isEmpty {
            parts.append("\n---\n【参考项目目录】`\(ws)`")
        }
        if let diff = thread?.gitDiffSummary ?? packet.gitDiffSummary, !diff.isEmpty {
            parts.append("\n【Git 变更上下文】\n\(diff)")
        }

        let files = thread?.attachedFiles ?? packet.attachedFiles ?? []
        var skipped: [String] = []
        var totalBytes = parts.joined(separator: "\n").utf8.count

        for path in files {
            let url = URL(fileURLWithPath: path)
            let name = url.lastPathComponent
            if isLikelySecretFile(name) {
                skipped.append("\(name)（疑似凭据文件，已跳过）")
                continue
            }
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                skipped.append("\(name)（无法读取）")
                continue
            }
            if data.count > maxSingleFileBytes || totalBytes + data.count > maxBundleBytes {
                skipped.append("\(name)（体积较大，请直接拖入 Gemini 附件栏）")
                continue
            }
            guard let text = String(data: data, encoding: .utf8),
                  !text.unicodeScalars.contains(where: { $0.value < 32 && $0 != "\n" && $0 != "\r" && $0 != "\t" }) else {
                skipped.append("\(name)（二进制/媒体文件，请直接拖入 Gemini 附件栏）")
                continue
            }
            let ext = url.pathExtension.lowercased()
            let block = "\n### 附件：\(name)\n```\(ext)\n\(text)\n```"
            parts.append(block)
            totalBytes += block.utf8.count
        }

        if !skipped.isEmpty {
            parts.append("\n【未内联文件（如需分析请在 Gemini 中作为附件上传）】\n" + skipped.map { "- \($0)" }.joined(separator: "\n"))
        }

        return (parts.joined(separator: "\n\n"), skipped)
    }

    private static func isLikelySecretFile(_ filename: String) -> Bool {
        let lower = filename.lowercased()
        if lower.hasPrefix(".env") { return true }
        let keywords = ["secret", "credential", "token", "apikey", "api_key", "private", "id_rsa", "id_ed25519", ".pem", ".p12", ".key"]
        return keywords.contains { lower.contains($0) }
    }

    private static func runGit(_ arguments: [String], cwd: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
