import CFNetwork
import Foundation

enum CodexSandboxMode: String, CaseIterable, Identifiable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .readOnly: "只读审查"
        case .workspaceWrite: "允许改代码"
        }
    }
}

@MainActor
final class CodexRunner: ObservableObject {
    @Published var runningThreadID: UUID?
    @Published var liveStatusText: String = ""
    @Published var liveLogLines: [String] = []
    @Published var elapsedSeconds: Int = 0

    private var activeProcess: Process?
    private var timerTask: Task<Void, Never>?

    var isRunning: Bool { runningThreadID != nil }

    func cancel() {
        activeProcess?.terminate()
        activeProcess = nil
        timerTask?.cancel()
        timerTask = nil
        runningThreadID = nil
        liveStatusText = "已手动停止 Codex 运行。"
    }

    func run(
        thread: ConversationThread,
        sandbox: CodexSandboxMode,
        store: BridgeStore,
        onComplete: @escaping @MainActor (Result<Packet, Error>) -> Void
    ) {
        guard !isRunning else {
            onComplete(.failure(BridgeError("已有正在运行中的 Codex 任务，请先等待完成或停止。")))
            return
        }

        guard let codexBin = resolveCodexBinary() else {
            onComplete(.failure(BridgeError("未在本机找到 codex CLI，请确认 codex 已安装。")))
            return
        }

        runningThreadID = thread.id
        liveStatusText = "正在启动 Codex（\(sandbox.label)）…"
        liveLogLines = ["→ 使用模型引擎：\(codexBin)", "→ 沙箱模式：\(sandbox.label)"]
        elapsedSeconds = 0

        _ = try? store.updateStatus(threadOrPacketId: thread.id, status: .inProgress)

        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isRunning else { break }
                self.elapsedSeconds += 1
            }
        }

        let prompt = buildPrompt(for: thread, sandbox: sandbox)
        let workingDir = thread.workspacePath ?? FileManager.default.homeDirectoryForCurrentUser.path
        let outFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("wuyu-codex-\(UUID().uuidString).md")

        let effort = UserDefaults.standard.string(forKey: "workstation.codexReasoningEffort") ?? "medium"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: codexBin)
        process.arguments = [
            "exec",
            "--json",
            "--skip-git-repo-check",
            "-c", "model_reasoning_effort=\"\(effort)\"",
            "-s", sandbox.rawValue,
            "-C", workingDir,
            "-o", outFile.path,
            "-",
        ]

        var env = ProcessInfo.processInfo.environment
        let extraPaths = [
            URL(fileURLWithPath: codexBin).deletingLastPathComponent().path,
            "/Users/\(NSUserName())/.nvm/versions/node/v24.14.0/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + (existingPath.isEmpty ? [] : [existingPath])).joined(separator: ":")

        // Apply custom proxy override from Settings, or inherit macOS system proxy if configured
        let customProxy = (UserDefaults.standard.string(forKey: "workstation.codexProxyURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !customProxy.isEmpty {
            env["HTTP_PROXY"] = customProxy
            env["HTTPS_PROXY"] = customProxy
            env["ALL_PROXY"] = customProxy
        } else {
            Self.injectSystemProxyIfEnabled(into: &env)
        }
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.activeProcess = process

        Task.detached { [weak self] in
            var lastAgentMessage = ""
            var stderrBuffer = ""

            do {
                try process.run()
            } catch {
                await MainActor.run {
                    self?.finishCleanup()
                    onComplete(.failure(BridgeError("启动 Codex 失败：\(error.localizedDescription)")))
                }
                return
            }

            if let data = prompt.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            try? stdinPipe.fileHandleForWriting.close()

            let stderrTask = Task.detached { () -> String in
                let data = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            }

            let handle = stdoutPipe.fileHandleForReading
            var lineBuffer = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                lineBuffer.append(chunk)
                while let nlIndex = lineBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                    let lineData = lineBuffer[..<nlIndex]
                    lineBuffer.removeSubrange(...nlIndex)
                    if let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !line.isEmpty {
                        if let parsed = Self.parseCodexEvent(line) {
                            if let msg = parsed.agentText, !msg.isEmpty {
                                lastAgentMessage = msg
                            }
                            await MainActor.run {
                                guard let self else { return }
                                if let status = parsed.statusLine {
                                    self.liveStatusText = status
                                    self.appendLog(status)
                                }
                            }
                        }
                    }
                }
            }

            process.waitUntilExit()
            stderrBuffer = await stderrTask.value
            let exitCode = process.terminationStatus

            let outputFromFile = (try? String(contentsOf: outFile, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try? FileManager.default.removeItem(at: outFile)

            let finalBody = !outputFromFile.isEmpty ? outputFromFile : lastAgentMessage.trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                guard let self else { return }
                let wasCancelled = self.runningThreadID == nil
                self.finishCleanup()
                if wasCancelled {
                    _ = try? store.updateStatus(threadOrPacketId: thread.id, status: .open)
                    return
                }
                if exitCode != 0 && finalBody.isEmpty {
                    _ = try? store.updateStatus(threadOrPacketId: thread.id, status: .open)
                    let errPreview = String(stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
                    onComplete(.failure(BridgeError("Codex 执行退出（code \(exitCode)）：\(errPreview.isEmpty ? "请检查本地 codex 登录状态" : errPreview)")))
                    return
                }
                let bodyToSave = finalBody.isEmpty ? "Codex 已执行完毕（未输出正文，退出码 \(exitCode)）。" : finalBody
                do {
                    let saved = try store.reply(to: thread.latest.id, from: .codex, body: bodyToSave)
                    onComplete(.success(saved))
                } catch {
                    onComplete(.failure(error))
                }
            }
        }
    }

    private func finishCleanup() {
        activeProcess = nil
        timerTask?.cancel()
        timerTask = nil
        runningThreadID = nil
    }

    private func appendLog(_ line: String) {
        if liveLogLines.last != line {
            liveLogLines.append(line)
            if liveLogLines.count > 12 {
                liveLogLines.removeFirst(liveLogLines.count - 12)
            }
        }
    }

    private func resolveCodexBinary() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var candidates: [String] = [
            // Prefer ChatGPT.app's latest bundled official Codex CLI first (supports gpt-6.2-sol / astra)
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "\(home)/.nvm/versions/node/v24.14.0/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
        ]
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmDir) {
            for v in versions.sorted().reversed() {
                candidates.append("\(nvmDir)/\(v)/bin/codex")
            }
        }
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private nonisolated static func injectSystemProxyIfEnabled(into env: inout [String: String]) {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return }
        if (settings[kCFNetworkProxiesHTTPEnable as String] as? Int) == 1,
           let host = settings[kCFNetworkProxiesHTTPProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPPort as String] as? Int {
            env["HTTP_PROXY"] = "http://\(host):\(port)"
        }
        if (settings[kCFNetworkProxiesHTTPSEnable as String] as? Int) == 1,
           let host = settings[kCFNetworkProxiesHTTPSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesHTTPSPort as String] as? Int {
            env["HTTPS_PROXY"] = "http://\(host):\(port)"
        }
        if (settings[kCFNetworkProxiesSOCKSEnable as String] as? Int) == 1,
           let host = settings[kCFNetworkProxiesSOCKSProxy as String] as? String,
           let port = settings[kCFNetworkProxiesSOCKSPort as String] as? Int {
            env["ALL_PROXY"] = "socks5://\(host):\(port)"
        }
    }

    private func buildPrompt(for thread: ConversationThread, sandbox: CodexSandboxMode) -> String {
        var lines: [String] = []
        lines.append("你正在「无语工作站」的自动协同流水线中作为 Codex 执行本阶段任务。")
        lines.append("当前沙箱权限：\(sandbox.label)（\(sandbox.rawValue)）。请直接基于本地真实文件完成工作，用清晰简洁的中文 Markdown 输出结果，标明修改/核查的文件位置与实测命令结果。")
        lines.append("\n# 任务标题：\(thread.subject)")
        if let ws = thread.workspacePath {
            lines.append("- 项目目录：`\(ws)`")
        }
        if !thread.attachedFiles.isEmpty {
            lines.append("- 关键文件：" + thread.attachedFiles.map { "`\($0)`" }.joined(separator: "、"))
        }
        if let stage = thread.currentStage {
            lines.append("- 当前阶段（第 \(stage.index + 1) 步）：\(stage.role) —— \(stage.instruction)")
        }
        if let diff = thread.gitDiffSummary {
            lines.append("\n## 初始 Git 变更上下文\n\(diff)")
        }
        lines.append("\n## 历史协作记录")
        for (idx, msg) in thread.messages.enumerated() {
            lines.append("\n### 第 \(idx + 1) 轮 · \(msg.from.label) → \(msg.to.label)\n\(msg.body)")
        }
        lines.append("\n请完成本阶段任务，直接给出结构化的最终回执正文。")
        return lines.joined(separator: "\n")
    }

    private nonisolated static func parseCodexEvent(_ line: String) -> (statusLine: String?, agentText: String?)? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "thread.started":
            return ("Codex 会话已建立，正在读取任务上下文…", nil)
        case "turn.started":
            return ("Codex 正在思考与分析代码…", nil)
        case "item.started":
            if let item = json["item"] as? [String: Any], let itemType = item["type"] as? String {
                if itemType == "command_execution", let cmd = item["command"] as? String {
                    let compact = cmd.replacingOccurrences(of: "\n", with: " ").prefix(72)
                    return ("执行命令：\(compact)", nil)
                }
                if itemType == "file_change" {
                    return ("正在修改本地文件…", nil)
                }
            }
            return nil
        case "item.completed":
            if let item = json["item"] as? [String: Any], let itemType = item["type"] as? String {
                if itemType == "agent_message", let text = item["text"] as? String {
                    return ("Codex 已产出阶段回复，正在写入工作站…", text)
                }
                if itemType == "command_execution", let cmd = item["command"] as? String {
                    let exitCode = item["exit_code"] as? Int ?? 0
                    let compact = cmd.replacingOccurrences(of: "\n", with: " ").prefix(60)
                    return ("命令完成（exit \(exitCode)）：\(compact)", nil)
                }
                if itemType == "file_change" {
                    return ("文件修改已完成", nil)
                }
            }
            return nil
        case "turn.completed":
            return ("本轮 Codex 执行完成", nil)
        case "error", "turn.failed":
            let msg = (json["message"] as? String) ?? ((json["error"] as? [String: Any])?["message"] as? String) ?? "执行出错"
            return ("错误：\(msg)", nil)
        default:
            return nil
        }
    }
}
