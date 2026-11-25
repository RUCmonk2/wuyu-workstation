import Foundation

struct MCPServer: Sendable {
    let store: BridgeStore

    func run() {
        while let rawLine = readLine(strippingNewline: true) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.lowercased().hasPrefix("content-length:") { continue }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let response = handleRequest(object) {
                writeJSONLine(response)
            }
        }
    }

    private func handleRequest(_ req: [String: Any]) -> [String: Any]? {
        let id = req["id"]
        guard let method = req["method"] as? String else {
            guard let id else { return nil }
            return errorResponse(id: id, code: -32600, message: "Invalid JSON-RPC request")
        }
        if id == nil { return nil }
        let params = req["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            let requestedVersion = params["protocolVersion"] as? String ?? "2024-11-05"
            return okResponse(id: id!, result: [
                "protocolVersion": requestedVersion,
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "wuyu-workstation", "version": "2.1.0"],
            ])
        case "ping":
            return okResponse(id: id!, result: [:])
        case "tools/list":
            return okResponse(id: id!, result: ["tools": toolDefinitions()])
        case "tools/call":
            guard let name = params["name"] as? String else {
                return errorResponse(id: id!, code: -32602, message: "Missing tool name")
            }
            let args = params["arguments"] as? [String: Any] ?? [:]
            return okResponse(id: id!, result: callTool(name: name, arguments: args))
        case "resources/list":
            return okResponse(id: id!, result: ["resources": []])
        case "prompts/list":
            return okResponse(id: id!, result: ["prompts": []])
        default:
            return errorResponse(id: id!, code: -32601, message: "Method not found: \(method)")
        }
    }

    private func toolDefinitions() -> [[String: Any]] {
        let clientEnum = Client.allCases.map(\.rawValue)
        let statusEnum = PacketStatus.allCases.map(\.rawValue)
        let templateEnum = WorkflowTemplate.allCases.map(\.rawValue)

        return [
            [
                "name": "wuyu_get_current",
                "description": "获取无语工作站当前最需要处理的活跃协作线程/工作流（无需记住交接 ID）。返回完整多轮历史、工作目录、关联文件、Git Diff 及当前阶段要求。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "client": ["type": "string", "enum": clientEnum, "description": "可选：按当前客户端过滤（codex / antigravity / gemini / claude）。"],
                    ],
                ],
            ],
            [
                "name": "wuyu_list_threads",
                "description": "列出无语工作站的协作线程摘要列表，支持按客户端、状态或关键词搜索。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "client": ["type": "string", "enum": clientEnum],
                        "status": ["type": "string", "enum": statusEnum],
                        "include_archived": ["type": "boolean"],
                        "query": ["type": "string"],
                        "limit": ["type": "integer"],
                    ],
                ],
            ],
            [
                "name": "wuyu_read_thread",
                "description": "按线程 ID 或任意交接/回执 ID 读取无语工作站中该任务的完整多轮对话历史与上下文。",
                "inputSchema": [
                    "type": "object",
                    "properties": ["id": ["type": "string"]],
                    "required": ["id"],
                ],
            ],
            [
                "name": "wuyu_create_workflow",
                "description": "在无语工作站创建一条新的多模型协作工作流或单次交接，支持附带工作区路径、关键文件路径、自动抓取 Git Diff 摘要以及预设多阶段流水线。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "from": ["type": "string", "enum": clientEnum],
                        "to": ["type": "string", "enum": clientEnum],
                        "subject": ["type": "string"],
                        "body": ["type": "string"],
                        "template": ["type": "string", "enum": templateEnum],
                        "workspace_path": ["type": "string"],
                        "attached_files": ["type": "array", "items": ["type": "string"]],
                        "capture_git_diff": ["type": "boolean"],
                    ],
                    "required": ["from", "to", "subject", "body"],
                ],
            ],
            [
                "name": "wuyu_submit_reply",
                "description": "向无语工作站提交阶段回执或协作产出。如省略 id，将自动回复当前待处理的活跃线程；如有预设工作流阶段，会自动流转给下一阶段负责端。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "from": ["type": "string", "enum": clientEnum],
                        "body": ["type": "string"],
                        "next_to": ["type": "string", "enum": clientEnum],
                        "mark_done": ["type": "boolean"],
                        "workspace_path": ["type": "string"],
                        "attached_files": ["type": "array", "items": ["type": "string"]],
                    ],
                    "required": ["from", "body"],
                ],
            ],
            [
                "name": "wuyu_update_status",
                "description": "更新无语工作站线程状态（open / in_progress / replied / done / archived）。",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "status": ["type": "string", "enum": statusEnum],
                    ],
                    "required": ["id", "status"],
                ],
            ],
        ]
    }

    private func callTool(name: String, arguments args: [String: Any]) -> [String: Any] {
        do {
            let output: String
            switch name {
            case "wuyu_get_current":
                let client = try optionalClient(args["client"])
                guard let thread = try store.currentPending(for: client) else {
                    return toolText("当前没有待处理的活跃协作线程。", isError: false)
                }
                output = formatThreadForAgent(thread)
            case "wuyu_list_threads":
                let client = try optionalClient(args["client"])
                let status = try optionalStatus(args["status"])
                let includeArchived = args["include_archived"] as? Bool ?? false
                let query = args["query"] as? String ?? ""
                let limit = max(1, min(args["limit"] as? Int ?? 20, 100))
                let list = Array(try store.threads(client: client, includeArchived: includeArchived, statusFilter: status, query: query).prefix(limit))
                output = try jsonString(list.map(threadSummaryDict))
            case "wuyu_read_thread":
                output = formatThreadForAgent(try store.readThread(try requiredUUID(args["id"], field: "id")))
            case "wuyu_create_workflow":
                let from = try requiredClient(args["from"], field: "from")
                let to = try requiredClient(args["to"], field: "to")
                guard let subject = args["subject"] as? String else { throw BridgeError("缺少 subject 字段。") }
                guard let body = args["body"] as? String else { throw BridgeError("缺少 body 字段。") }
                let template = (args["template"] as? String).flatMap(WorkflowTemplate.init(rawValue:)) ?? .custom
                let workspace = args["workspace_path"] as? String
                var files = args["attached_files"] as? [String] ?? []
                var diffSummary: String?
                if (args["capture_git_diff"] as? Bool ?? false), let ws = workspace, let snapshot = GitContextHelper.captureSnapshot(at: ws) {
                    diffSummary = GitContextHelper.formatSnapshotMarkdown(snapshot)
                    for f in snapshot.changedFiles where !files.contains(f) { files.append(f) }
                }
                let steps = template.makeSteps()
                let saved = try store.send(
                    from: from, to: to, subject: subject, body: body,
                    workspacePath: workspace, attachedFiles: files.isEmpty ? nil : files,
                    gitDiffSummary: diffSummary,
                    templateId: template == .custom ? nil : template.rawValue,
                    workflowSteps: steps.isEmpty ? nil : steps
                )
                let thread = try store.readThread(saved.id)
                output = try jsonString([
                    "status": "created",
                    "threadId": thread.id.uuidString,
                    "packetId": saved.id.uuidString,
                    "waitingFor": thread.waitingFor?.rawValue ?? saved.to.rawValue,
                    "subject": saved.subject,
                ])
            case "wuyu_submit_reply":
                let from = try requiredClient(args["from"], field: "from")
                guard let body = args["body"] as? String else { throw BridgeError("缺少 body 字段。") }
                let targetID: UUID
                if let rawID = args["id"] as? String, !rawID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    targetID = try requiredUUID(rawID, field: "id")
                } else if let pending = try store.currentPending(for: from) {
                    targetID = pending.latest.id
                } else {
                    throw BridgeError("未提供 id，且当前没有等待 \(from.label) 处理的活跃线程。")
                }
                let reply = try store.reply(
                    to: targetID,
                    from: from,
                    body: body,
                    nextTo: try optionalClient(args["next_to"]),
                    markDone: args["mark_done"] as? Bool ?? false,
                    workspacePath: args["workspace_path"] as? String,
                    attachedFiles: args["attached_files"] as? [String]
                )
                let thread = try store.readThread(reply.id)
                output = try jsonString([
                    "status": "replied",
                    "threadId": thread.id.uuidString,
                    "replyId": reply.id.uuidString,
                    "threadStatus": thread.status.rawValue,
                    "waitingFor": thread.waitingFor?.rawValue ?? "",
                ])
            case "wuyu_update_status":
                let id = try requiredUUID(args["id"], field: "id")
                guard let statusRaw = args["status"] as? String, let status = PacketStatus(rawValue: statusRaw) else {
                    throw BridgeError("status 须为 open / in_progress / replied / done / archived。")
                }
                let updated = try store.updateStatus(threadOrPacketId: id, status: status)
                output = try jsonString(["threadId": updated.id.uuidString, "status": updated.effectiveStatus.rawValue, "subject": updated.subject])
            default:
                return toolText("未知工具：\(name)", isError: true)
            }
            return toolText(output, isError: false)
        } catch {
            return toolText("无语工作站错误：\(error.localizedDescription)", isError: true)
        }
    }

    private func formatThreadForAgent(_ thread: ConversationThread) -> String {
        var lines: [String] = [
            "# 协作线程：\(thread.subject)",
            "- 线程 ID：`\(thread.id.uuidString)`",
            "- 最新消息 ID：`\(thread.latest.id.uuidString)`",
            "- 当前状态：\(thread.status.label)（`\(thread.status.rawValue)`）",
        ]
        if let waiting = thread.waitingFor { lines.append("- 当前等待处理方：**\(waiting.label)**（`\(waiting.rawValue)`）") }
        if let ws = thread.workspacePath { lines.append("- 工作区目录：`\(ws)`") }
        if !thread.attachedFiles.isEmpty {
            lines.append("- 关联文件：\n" + thread.attachedFiles.map { "  - `\($0)`" }.joined(separator: "\n"))
        }
        if !thread.workflowSteps.isEmpty {
            lines.append("\n## 工作流阶段")
            for step in thread.workflowSteps {
                let mark = step.completedPacketID != nil ? "[✓]" : (thread.currentStepIndex == step.index ? "[→ 当前]" : "[ ]")
                lines.append("\(step.index + 1). \(mark) **\(step.client.label)**（\(step.role)）：\(step.instruction)")
            }
        }
        if let diff = thread.gitDiffSummary { lines.append("\n## Git 变更上下文\n\(diff)") }
        lines.append("\n## 对话记录（共 \(thread.messages.count) 轮）")
        let fmt = ISO8601DateFormatter()
        for (idx, msg) in thread.messages.enumerated() {
            lines.append("\n### 第 \(idx + 1) 轮 · \(msg.from.label) → \(msg.to.label)（\(fmt.string(from: msg.createdAt)) · ID: `\(msg.id.uuidString)`）")
            lines.append(msg.body)
        }
        return lines.joined(separator: "\n")
    }

    private func threadSummaryDict(_ thread: ConversationThread) -> [String: Any] {
        var dict: [String: Any] = [
            "threadId": thread.id.uuidString,
            "latestPacketId": thread.latest.id.uuidString,
            "subject": thread.subject,
            "status": thread.status.rawValue,
            "statusLabel": thread.status.label,
            "waitingFor": thread.waitingFor?.rawValue ?? "",
            "messageCount": thread.messages.count,
            "participants": thread.participants.map(\.rawValue),
            "updatedAtMs": Int64(thread.updatedAt.timeIntervalSince1970 * 1000),
        ]
        if let ws = thread.workspacePath { dict["workspacePath"] = ws }
        if !thread.workflowSteps.isEmpty { dict["workflowProgress"] = "\(thread.completedStepCount)/\(thread.workflowSteps.count)" }
        return dict
    }

    private func requiredClient(_ value: Any?, field: String) throws -> Client {
        guard let str = value as? String, let client = Client(rawValue: str) else {
            throw BridgeError("\(field) 须为 codex、antigravity、gemini 或 claude。")
        }
        return client
    }

    private func optionalClient(_ value: Any?) throws -> Client? {
        guard let value, !(value is NSNull) else { return nil }
        guard let str = value as? String else { throw BridgeError("client 参数须为字符串。") }
        if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let client = Client(rawValue: str) else { throw BridgeError("client 须为 codex、antigravity、gemini 或 claude。") }
        return client
    }

    private func optionalStatus(_ value: Any?) throws -> PacketStatus? {
        guard let value, !(value is NSNull) else { return nil }
        guard let str = value as? String else { throw BridgeError("status 参数须为字符串。") }
        if str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        guard let status = PacketStatus(rawValue: str) else { throw BridgeError("status 无效。") }
        return status
    }

    private func requiredUUID(_ value: Any?, field: String) throws -> UUID {
        guard let str = value as? String, let id = UUID(uuidString: str) else {
            throw BridgeError("\(field) 须为有效的 UUID。")
        }
        return id
    }

    private func toolText(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private func okResponse(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func writeJSONLine(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
        fflush(stdout)
    }
}
