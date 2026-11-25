import AppKit
import Foundation

private let usage = """
无语工作站 2.1 · 多模型桌面调度台与共享黑板

用法：bridge [--store 目录] 命令
  mcp                              以标准 stdio 模式启动本地 MCP Server
  list [接收方]                     列出交接摘要（JSON）
  threads [客户端]                  列出按任务聚合的协作线程摘要（JSON）
  thread 交接或线程ID               读取完整多轮协作线程（JSON）
  current [客户端]                  读取当前最需要处理的活跃线程（JSON）
  read 交接ID                       读取单条完整交接（JSON）
  send 发送方 接收方 '标题' 文件     保存新任务，输出摘要（JSON）
  reply 交接ID 发送方 文件           写入回执，输出摘要（JSON）
  status 线程ID 状态                更新线程状态（open/in_progress/replied/done/archived）
  delete 线程ID                     删除整个协作线程
  apps                             检查四个客户端的绑定与安装路径

客户端：codex、antigravity、gemini、claude。用 - 从标准输入读取 UTF-8 正文。
默认共享黑板：~/.wuyu-workstation/mailbox（可用 --store 覆盖）。
"""

private struct Summary: Encodable {
    let id: UUID
    let threadId: UUID
    let createdAt: Date
    let from: Client
    let to: Client
    let subject: String
    let replyTo: UUID?
    let status: PacketStatus

    init(_ packet: Packet) {
        id = packet.id
        threadId = packet.effectiveThreadId
        createdAt = packet.createdAt
        from = packet.from
        to = packet.to
        subject = packet.subject
        replyTo = packet.replyTo
        status = packet.effectiveStatus
    }
}

private struct ThreadSummary: Encodable {
    let threadId: UUID
    let latestPacketId: UUID
    let subject: String
    let status: PacketStatus
    let waitingFor: Client?
    let participants: [Client]
    let messageCount: Int
    let workspacePath: String?
    let updatedAt: Date

    init(_ thread: ConversationThread) {
        threadId = thread.id
        latestPacketId = thread.latest.id
        subject = thread.subject
        status = thread.status
        waitingFor = thread.waitingFor
        participants = thread.participants
        messageCount = thread.messages.count
        workspacePath = thread.workspacePath
        updatedAt = thread.updatedAt
    }
}

private func client(_ value: String) throws -> Client {
    guard let client = Client(rawValue: value) else {
        throw BridgeError("客户端须为 codex、antigravity、gemini 或 claude。")
    }
    return client
}

private func packetID(_ value: String) throws -> UUID {
    guard let id = UUID(uuidString: value) else { throw BridgeError("交接 ID 须为 UUID。") }
    return id
}

private func readBody(_ path: String) throws -> String {
    let handle: FileHandle
    if path == "-" {
        handle = .standardInput
    } else {
        let url = URL(fileURLWithPath: path)
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw BridgeError("正文须为普通 UTF-8 文本文件。")
        }
        handle = try FileHandle(forReadingFrom: url)
    }
    defer { if path != "-" { try? handle.close() } }
    var data = Data()
    while let chunk = try handle.read(upToCount: 16 * 1024), !chunk.isEmpty {
        data.append(chunk)
        guard data.count <= BridgeStore.maxBodyBytes else { throw BridgeError("正文最多 512 KiB（UTF-8）。") }
    }
    guard let body = String(data: data, encoding: .utf8) else { throw BridgeError("正文须为 UTF-8 文本。") }
    return body
}

private func printJSON(_ value: some Encodable) throws {
    let data = try BridgeStore.encoder().encode(value)
    print(String(decoding: data, as: UTF8.self))
}

private func defaultMailboxDirectory() -> URL {
    if let envPath = ProcessInfo.processInfo.environment["WUYU_MAILBOX_DIR"],
       !envPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: (envPath as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
    }
    if let configured = Bundle.main.object(forInfoDictionaryKey: "WuyuMailboxPath") as? String,
       !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
    }
    return FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".wuyu-workstation", isDirectory: true)
        .appendingPathComponent("mailbox", isDirectory: true)
}

@MainActor
private func runCLI(_ args: [String], store: BridgeStore) throws {
    switch (args.first, args.count) {
    case ("mcp", 1):
        MCPServer(store: store).run()
    case ("list", 1):
        try printJSON(store.list().map(Summary.init))
    case ("list", 2):
        try printJSON(store.list(to: client(args[1])).map(Summary.init))
    case ("threads", 1):
        try printJSON(store.threads().map(ThreadSummary.init))
    case ("threads", 2):
        try printJSON(store.threads(client: client(args[1])).map(ThreadSummary.init))
    case ("thread", 2):
        try printJSON(store.readThread(packetID(args[1])))
    case ("current", 1):
        if let thread = try store.currentPending(for: nil) { try printJSON(thread) } else { print("null") }
    case ("current", 2):
        if let thread = try store.currentPending(for: client(args[1])) { try printJSON(thread) } else { print("null") }
    case ("read", 2):
        try printJSON(store.read(packetID(args[1])))
    case ("send", 5):
        try printJSON(Summary(store.send(from: client(args[1]), to: client(args[2]), subject: args[3], body: readBody(args[4]))))
    case ("reply", 4):
        try printJSON(Summary(store.reply(to: packetID(args[1]), from: client(args[2]), body: readBody(args[3]))))
    case ("status", 3):
        guard let status = PacketStatus(rawValue: args[2]) else {
            throw BridgeError("状态须为 open、in_progress、replied、done 或 archived。")
        }
        try printJSON(Summary(store.updateStatus(threadOrPacketId: packetID(args[1]), status: status)))
    case ("delete", 2):
        try store.deleteThread(packetID(args[1]))
        try printJSON(["deleted": args[1]])
    case ("apps", 1):
        try printJSON(Client.allCases.map { client in
            let url = client.resolvedAppURL()
            return [
                "client": client.rawValue,
                "bundleID": client.resolvedBundleID(),
                "path": url?.path ?? "",
            ]
        })
    case ("help", 1), ("--help", 1), ("-h", 1):
        print(usage)
    default:
        throw BridgeError("命令或参数有误。运行 bridge help 查看用法。")
    }
}

do {
    var args = Array(CommandLine.arguments.dropFirst())
    if args.count == 1, args[0].hasPrefix("-psn_") { args.removeAll() }
    let directory: URL
    if args.first == "--store" {
        guard args.count >= 3 else { throw BridgeError("请在 --store 后提供目录和命令。") }
        directory = URL(fileURLWithPath: args[1], isDirectory: true).standardizedFileURL
        args.removeFirst(2)
    } else {
        directory = defaultMailboxDirectory()
    }
    let store = BridgeStore(directory: directory)
    #if BRIDGE_CLI_ONLY
    if args.isEmpty {
        print(usage)
    } else {
        try runCLI(args, store: store)
    }
    #else
    if args.isEmpty || args == ["gui"] {
        runBridgeUI(store: store)
    } else {
        try runCLI(args, store: store)
    }
    #endif
} catch {
    FileHandle.standardError.write(Data(("无语工作站：\(error.localizedDescription)\n").utf8))
    exit(EXIT_FAILURE)
}
