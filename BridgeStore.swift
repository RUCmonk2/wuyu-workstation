import AppKit
import Foundation

enum Client: String, CaseIterable, Identifiable, Codable, Sendable {
    case codex, antigravity, gemini, claude

    var id: String { rawValue }

    var label: String {
        switch self {
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .gemini: "Gemini"
        case .claude: "Claude"
        }
    }

    var shortLabel: String {
        switch self {
        case .codex: "Codex"
        case .antigravity: "AGY"
        case .gemini: "Gemini"
        case .claude: "Claude"
        }
    }

    var roleHint: String {
        switch self {
        case .codex: "GPT Pro 主力实现 / 代码审查"
        case .antigravity: "Gemini 4 + 内置 Claude / 编排"
        case .gemini: "Ultra 多模态初读 / 独立视角"
        case .claude: "独立 Claude 桌面端"
        }
    }

    var bundleID: String {
        switch self {
        case .codex: "com.openai.codex"
        case .antigravity: "com.google.antigravity"
        case .gemini: "com.google.GeminiMacOS"
        case .claude: "com.anthropic.claudefordesktop"
        }
    }

    var customAppPathKey: String {
        "workstation.customAppPath.\(rawValue)"
    }

    var supportsLocalMCP: Bool {
        self == .codex || self == .antigravity
    }

    @MainActor
    func resolvedAppURL(defaults: UserDefaults = .standard) -> URL? {
        if let custom = defaults.string(forKey: customAppPathKey), !custom.isEmpty {
            let url = URL(fileURLWithPath: custom)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
        return candidateAppURLs().first
    }

    @MainActor
    func resolvedBundleID(defaults: UserDefaults = .standard) -> String {
        if let url = resolvedAppURL(defaults: defaults),
           let bundle = Bundle(url: url),
           let id = bundle.bundleIdentifier {
            return id
        }
        return bundleID
    }

    @MainActor
    func candidateAppURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths: [String]
        switch self {
        case .codex:
            paths = [
                "/Applications/ChatGPT.app",
                "\(home)/Applications/Codex Aurora.app",
                "/Applications/Codex.app",
                "/Applications/ChatGPT Classic.app",
            ]
        case .antigravity:
            paths = [
                "/Applications/Antigravity.app",
                "/Applications/Antigravity IDE.app",
            ]
        case .gemini:
            paths = ["/Applications/Gemini.app"]
        case .claude:
            paths = ["/Applications/Claude.app"]
        }
        var results: [URL] = []
        if let byID = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            results.append(byID)
        }
        for path in paths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            if !results.contains(where: { $0.standardizedFileURL.path == url.standardizedFileURL.path }) {
                results.append(url)
            }
        }
        return results
    }
}

enum PacketStatus: String, CaseIterable, Identifiable, Codable, Sendable {
    case open
    case inProgress = "in_progress"
    case replied
    case done
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .open: "待处理"
        case .inProgress: "进行中"
        case .replied: "已回执"
        case .done: "已完成"
        case .archived: "已归档"
        }
    }

    var isActive: Bool {
        switch self {
        case .open, .inProgress, .replied: true
        case .done, .archived: false
        }
    }
}

struct WorkflowStep: Codable, Identifiable, Hashable, Sendable {
    let index: Int
    let client: Client
    let role: String
    let instruction: String
    var completedPacketID: UUID?

    var id: Int { index }
}

enum WorkflowTemplate: String, CaseIterable, Identifiable, Sendable {
    case implementReviewFix = "implement_review_fix"
    case codeDiffReview = "code_diff_review"
    case multimodalToCode = "multimodal_to_code"
    case dualRedBlue = "dual_red_blue"
    case redTeamAudit = "red_team_audit"
    case custom = "custom"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .implementReviewFix: "实现 → 红队审查 → 修复"
        case .codeDiffReview: "代码 Diff 精准评审"
        case .multimodalToCode: "资料初读 → 拆解 → 编码"
        case .dualRedBlue: "红蓝军双核独立对比"
        case .redTeamAudit: "独立红队审查（盲审）"
        case .custom: "自由交接"
        }
    }

    var subtitle: String {
        switch self {
        case .implementReviewFix: "Codex 主力实现，Antigravity（Gemini 4 / Claude）挑刺，再回 Codex 收敛"
        case .codeDiffReview: "自动抓取当前仓库 Git Diff，请 Antigravity 逐行找边界与隐患"
        case .multimodalToCode: "Gemini Ultra 读长文/PDF/图，Antigravity 整理方案，Codex 落地实现"
        case .dualRedBlue: "同一需求分别让 Codex 与 Antigravity 独立出方案，再合并最优解"
        case .redTeamAudit: "先给原题与约束、不给结论，防止顺从偏见"
        case .custom: "自定义发送方、接收方与正文"
        }
    }

    var defaultFrom: Client { .codex }

    var defaultTo: Client {
        switch self {
        case .multimodalToCode: .gemini
        default: .antigravity
        }
    }

    func makeSteps() -> [WorkflowStep] {
        switch self {
        case .implementReviewFix:
            return [
                WorkflowStep(index: 0, client: .codex, role: "主力实现", instruction: "完成方案设计与核心实现，记录变更文件、验证结果与未决风险。"),
                WorkflowStep(index: 1, client: .antigravity, role: "Gemini 4 / Claude 独立审查", instruction: "独立审查代码与假设，找出有证据的漏洞、边界问题与最小修正建议。"),
                WorkflowStep(index: 2, client: .codex, role: "核查并收敛修复", instruction: "逐条核查审查意见，落实有效修复、复跑验证并标记完成。"),
            ]
        case .codeDiffReview:
            return [
                WorkflowStep(index: 0, client: .antigravity, role: "Diff 深度评审", instruction: "仅基于实际 Diff 和原文件审查逻辑缺陷、并发/安全隐患及遗漏测试，给出文件行号证据。"),
                WorkflowStep(index: 1, client: .codex, role: "定向修复与回归测试", instruction: "根据已证实的问题完成修复并补充验证。"),
            ]
        case .multimodalToCode:
            return [
                WorkflowStep(index: 0, client: .gemini, role: "Ultra 多模态初读", instruction: "通读原始材料/PDF/图片，提炼核心要求、约束、关键公式或数据，并标注页码/位置来源。"),
                WorkflowStep(index: 1, client: .antigravity, role: "架构拆解与验收标准", instruction: "结合本地项目结构，把初读结论转为可执行的开发拆解与验证清单。"),
                WorkflowStep(index: 2, client: .codex, role: "编码落地与交付", instruction: "按拆解清单实现代码并完成本地实测验收。"),
            ]
        case .dualRedBlue:
            return [
                WorkflowStep(index: 0, client: .antigravity, role: "蓝军独立方案", instruction: "先不依赖 Codex 已有思路，基于原题与约束独立提出方案并列出取舍理由。"),
                WorkflowStep(index: 1, client: .codex, role: "红军对照与最终决策", instruction: "对比两套方案的证据、复杂度与风险，吸收优点并执行最优解。"),
            ]
        case .redTeamAudit:
            return [
                WorkflowStep(index: 0, client: .antigravity, role: "独立盲审", instruction: "基于原始材料与约束独立判断，指出有证据的问题、反例和替代解释；不刻意附和或抬杠。"),
                WorkflowStep(index: 1, client: .codex, role: "证据复核", instruction: "回查源码或运行最小复现，采纳已证实项并保留未决项。"),
            ]
        case .custom:
            return []
        }
    }

    var bodySkeleton: String {
        switch self {
        case .implementReviewFix:
            return """
            【目标与交付物】
            - 

            【约束与验收标准】
            - 

            【本轮需要重点核查的问题】
            1. 
            2. 

            【返回格式要求】
            - 结论与证据（标明文件、行号或命令输出）
            - 有证据的问题、风险与最小修正建议
            - 状态标注：提议 / 已验证 / 未证实
            """
        case .codeDiffReview:
            return """
            【变更背景与目标】
            - 

            【重点审查维度】
            1. 正确性与边界条件
            2. 性能、并发与异常处理
            3. 是否有更简洁稳妥的实现

            【返回格式要求】
            - 按严重度列出问题：位置（文件:行号）、影响、复现/证据、最小修复建议
            - 明确指出无需修改的误报或已确认安全的点
            """
        case .multimodalToCode:
            return """
            请作为独立资料分析员通读所附原始材料，不要臆测未提供的内容。

            【本轮目标】
            - 

            【需要提取的重点】
            1. 核心要求、边界条件与硬约束
            2. 关键参数、公式、接口或数据结构
            3. 容易遗漏的陷阱与未明确项

            【返回格式要求】
            1. 结论及证据：标明原文页码、时间戳或章节位置
            2. 疑点、歧义与材料缺口
            3. 状态标注：已证实 / 推断 / 材料不足
            """
        case .dualRedBlue:
            return """
            【原始需求与背景】
            - 

            【硬性约束】
            - 

            【要求】
            请完全独立提出你认为最高效、可落地的架构/实现方案，说明：
            1. 核心设计思路与关键权衡
            2. 为什么优于常见替代方案
            3. 主要风险点与最小验证路径
            """
        case .redTeamAudit:
            return """
            请根据原始材料独立判断，无需刻意赞同或反对。

            【本轮角色】独立方案审查 / 红队挑刺
            【目标与交付物】
            - 
            【约束和验收标准】
            - 
            【本轮需要解决的具体问题】
            1. 
            【返回格式】
            1. 结论及证据（标明文件位置、页码或实测结果）
            2. 有证据的问题、遗漏、反例或替代解释 + 最小修正建议
            3. 状态：提议 / 已验证 / 未证实
            4. 材料不足与未决项
            """
        case .custom:
            return ""
        }
    }
}

struct Packet: Codable, Identifiable, Sendable {
    let id: UUID
    let createdAt: Date
    let from: Client
    let to: Client
    let subject: String
    let body: String
    let replyTo: UUID?

    var threadId: UUID?
    var status: PacketStatus?
    var workspacePath: String?
    var attachedFiles: [String]?
    var gitDiffSummary: String?
    var templateId: String?
    var workflowSteps: [WorkflowStep]?
    var currentStepIndex: Int?

    var effectiveThreadId: UUID { threadId ?? id }
    var effectiveStatus: PacketStatus { status ?? .open }
}

struct ConversationThread: Identifiable, Encodable, Sendable {
    let id: UUID
    let root: Packet
    let messages: [Packet]
    let latest: Packet
    let status: PacketStatus
    let participants: [Client]
    let waitingFor: Client?
    let workspacePath: String?
    let attachedFiles: [String]
    let gitDiffSummary: String?
    let workflowSteps: [WorkflowStep]
    let currentStepIndex: Int?

    var subject: String { root.subject }
    var updatedAt: Date { latest.createdAt }
    var isActive: Bool { status.isActive }

    var currentStage: WorkflowStep? {
        guard !workflowSteps.isEmpty else { return nil }
        if let idx = currentStepIndex, workflowSteps.indices.contains(idx) {
            return workflowSteps[idx]
        }
        return workflowSteps.first { $0.completedPacketID == nil }
    }

    var completedStepCount: Int {
        workflowSteps.count { $0.completedPacketID != nil }
    }
}

struct BridgeError: LocalizedError, Sendable {
    let reason: String
    init(_ reason: String) { self.reason = reason }
    var errorDescription: String? { reason }
}

struct BridgeStore: Sendable {
    static let maxBodyBytes = 512 * 1024
    private static let maxRecordBytes = 4 * maxBodyBytes
    let directory: URL

    func list(to recipient: Client? = nil) throws -> [Packet] {
        try prepareDirectory()
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: []
        )
        return try urls
            .filter { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension == "json" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .map { try readRecord($0) }
            .filter { recipient == nil || $0.to == recipient }
            .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
    }

    func threads(
        client: Client? = nil,
        includeArchived: Bool = false,
        statusFilter: PacketStatus? = nil,
        query: String = ""
    ) throws -> [ConversationThread] {
        let all = try list()
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

        func resolveRootID(for packet: Packet) -> UUID {
            if let tid = packet.threadId { return tid }
            var cursor = packet
            var seen: Set<UUID> = [cursor.id]
            while let parentID = cursor.replyTo, let parent = byID[parentID], !seen.contains(parent.id) {
                seen.insert(parent.id)
                cursor = parent
                if let tid = cursor.threadId { return tid }
            }
            return cursor.id
        }

        var groups: [UUID: [Packet]] = [:]
        for packet in all {
            groups[resolveRootID(for: packet), default: []].append(packet)
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        var built: [ConversationThread] = groups.compactMap { rootID, packets in
            let chronological = packets.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            guard let first = chronological.first, let latest = chronological.last else { return nil }
            let root = byID[rootID] ?? first

            var participants: [Client] = []
            for p in chronological {
                if !participants.contains(p.from) { participants.append(p.from) }
                if !participants.contains(p.to) { participants.append(p.to) }
            }

            let effectiveStatus = root.status ?? (chronological.count > 1 ? .replied : .open)
            let steps = root.workflowSteps ?? []
            let stepIndex = root.currentStepIndex
            let waitingFor: Client?
            if !effectiveStatus.isActive {
                waitingFor = nil
            } else if !steps.isEmpty {
                if let idx = stepIndex, steps.indices.contains(idx), steps[idx].completedPacketID == nil {
                    waitingFor = steps[idx].client
                } else {
                    waitingFor = steps.first(where: { $0.completedPacketID == nil })?.client ?? latest.to
                }
            } else {
                waitingFor = latest.to
            }

            let mergedWorkspace = chronological.reversed().compactMap { nonEmpty($0.workspacePath) }.first
            var mergedFiles: [String] = []
            for p in chronological {
                for f in p.attachedFiles ?? [] where !f.isEmpty && !mergedFiles.contains(f) {
                    mergedFiles.append(f)
                }
            }
            let latestDiff = chronological.reversed().compactMap { nonEmpty($0.gitDiffSummary) }.first

            return ConversationThread(
                id: root.id,
                root: root,
                messages: chronological,
                latest: latest,
                status: effectiveStatus,
                participants: participants,
                waitingFor: waitingFor,
                workspacePath: mergedWorkspace,
                attachedFiles: mergedFiles,
                gitDiffSummary: latestDiff,
                workflowSteps: steps,
                currentStepIndex: stepIndex
            )
        }

        if let client {
            built = built.filter { $0.waitingFor == client || $0.latest.to == client || $0.participants.contains(client) }
        }
        if let statusFilter {
            built = built.filter { $0.status == statusFilter }
        } else if !includeArchived {
            built = built.filter { $0.status != .archived }
        }
        if !needle.isEmpty {
            built = built.filter { thread in
                thread.subject.lowercased().contains(needle)
                    || (thread.workspacePath?.lowercased().contains(needle) ?? false)
                    || thread.attachedFiles.contains(where: { $0.lowercased().contains(needle) })
                    || thread.messages.contains { $0.body.lowercased().contains(needle) }
            }
        }

        return built.sorted {
            if $0.isActive != $1.isActive { return $0.isActive && !$1.isActive }
            return ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString)
        }
    }

    func read(_ id: UUID) throws -> Packet {
        try prepareDirectory()
        return try readRecord(id)
    }

    func readThread(_ anyID: UUID) throws -> ConversationThread {
        let target = try read(anyID)
        let allThreads = try threads(includeArchived: true)
        if let found = allThreads.first(where: { $0.id == target.effectiveThreadId || $0.messages.contains(where: { $0.id == anyID }) }) {
            return found
        }
        throw BridgeError("找不到线程 \(anyID.uuidString)。")
    }

    func currentPending(for client: Client? = nil) throws -> ConversationThread? {
        let active = try threads(includeArchived: false).filter { $0.isActive }
        if let client {
            if let exact = active.first(where: { $0.waitingFor == client }) { return exact }
            if let latestTo = active.first(where: { $0.latest.to == client }) { return latestTo }
        }
        return active.first
    }

    func send(
        from: Client,
        to: Client,
        subject: String,
        body: String,
        workspacePath: String? = nil,
        attachedFiles: [String]? = nil,
        gitDiffSummary: String? = nil,
        templateId: String? = nil,
        workflowSteps: [WorkflowStep]? = nil
    ) throws -> Packet {
        let id = UUID()
        let cleanedSteps: [WorkflowStep]? = {
            guard var steps = workflowSteps, !steps.isEmpty else { return nil }
            if steps[0].client == from, steps.count > 1 {
                steps[0].completedPacketID = id
            }
            return steps
        }()
        let initialStepIndex: Int? = {
            guard let steps = cleanedSteps, !steps.isEmpty else { return nil }
            return steps.firstIndex(where: { $0.completedPacketID == nil }) ?? 0
        }()
        return try save(
            id: id,
            from: from,
            to: to,
            subject: subject,
            body: body,
            replyTo: nil,
            threadId: id,
            status: .open,
            workspacePath: normalizePath(workspacePath),
            attachedFiles: normalizePaths(attachedFiles),
            gitDiffSummary: nonEmpty(gitDiffSummary),
            templateId: nonEmpty(templateId),
            workflowSteps: cleanedSteps,
            currentStepIndex: initialStepIndex
        )
    }

    func reply(
        to id: UUID,
        from: Client,
        body: String,
        nextTo: Client? = nil,
        markDone: Bool = false,
        workspacePath: String? = nil,
        attachedFiles: [String]? = nil
    ) throws -> Packet {
        let thread = try readThread(id)
        let original = try read(id)
        var root = thread.root

        let targetRecipient: Client
        var updatedSteps = root.workflowSteps ?? []
        var nextStepIndex = root.currentStepIndex

        if let explicitNext = nextTo {
            targetRecipient = explicitNext
        } else if !updatedSteps.isEmpty {
            if let matchingIdx = updatedSteps.firstIndex(where: { $0.completedPacketID == nil && $0.client == from }) {
                let pendingAfter = updatedSteps.indices.first { $0 > matchingIdx && updatedSteps[$0].completedPacketID == nil }
                if let nextIdx = pendingAfter {
                    targetRecipient = updatedSteps[nextIdx].client
                    nextStepIndex = nextIdx
                } else {
                    targetRecipient = original.from == from ? root.from : original.from
                    nextStepIndex = nil
                }
            } else {
                targetRecipient = original.from == from ? original.to : original.from
            }
        } else {
            guard from == original.to else {
                throw BridgeError("只有该交接的接收方（\(original.to.label)）可写入回执；如需转交他人，请指定 nextTo。")
            }
            targetRecipient = original.from
        }

        let effectiveTarget = targetRecipient == from ? (root.from == from ? root.to : root.from) : targetRecipient
        let replyPacket = try save(
            id: UUID(),
            from: from,
            to: effectiveTarget,
            subject: root.subject,
            body: body,
            replyTo: original.id,
            threadId: root.id,
            status: nil,
            workspacePath: normalizePath(workspacePath),
            attachedFiles: normalizePaths(attachedFiles),
            gitDiffSummary: nil,
            templateId: nil,
            workflowSteps: nil,
            currentStepIndex: nil
        )

        if !updatedSteps.isEmpty {
            if let idx = updatedSteps.firstIndex(where: { $0.completedPacketID == nil && $0.client == from }) {
                updatedSteps[idx].completedPacketID = replyPacket.id
                nextStepIndex = updatedSteps.firstIndex(where: { $0.completedPacketID == nil })
            }
            root.workflowSteps = updatedSteps
            root.currentStepIndex = nextStepIndex
        }
        let allStepsComplete = !updatedSteps.isEmpty && updatedSteps.allSatisfy { $0.completedPacketID != nil }
        root.status = (markDone || allStepsComplete) ? .done : .replied
        try writePacket(root, overwrite: true)

        return replyPacket
    }

    func updateStatus(threadOrPacketId id: UUID, status: PacketStatus) throws -> Packet {
        let thread = try readThread(id)
        var root = thread.root
        root.status = status
        try writePacket(root, overwrite: true)
        return root
    }

    func deleteThread(_ threadID: UUID) throws {
        let thread = try readThread(threadID)
        for packet in thread.messages {
            let url = packetURL(packet.id)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func readRecord(_ id: UUID) throws -> Packet {
        let url = packetURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw BridgeError("找不到交接 \(id.uuidString)。")
        }
        let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else {
            throw BridgeError("交接记录必须是普通文件。")
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: Self.maxRecordBytes + 1) ?? Data()
        guard data.count <= Self.maxRecordBytes else { throw BridgeError("交接记录过大。") }
        let packet: Packet
        do {
            packet = try Self.decoder().decode(Packet.self, from: data)
        } catch {
            throw BridgeError("无法读取交接 \(id.uuidString)。记录格式无效。")
        }
        guard packet.id == id else { throw BridgeError("交接记录的编号与文件名不一致。") }
        return packet
    }

    private func save(
        id: UUID,
        from: Client,
        to: Client,
        subject: String,
        body: String,
        replyTo: UUID?,
        threadId: UUID?,
        status: PacketStatus?,
        workspacePath: String?,
        attachedFiles: [String]?,
        gitDiffSummary: String?,
        templateId: String?,
        workflowSteps: [WorkflowStep]?,
        currentStepIndex: Int?
    ) throws -> Packet {
        let title = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard from != to else { throw BridgeError("请选择不同的发送方和接收方。") }
        guard !title.isEmpty, title.count <= 160, title.utf8.count <= 1024,
              title.rangeOfCharacter(from: .newlines.union(.controlCharacters)) == nil else {
            throw BridgeError("标题须为一行，长度为 1–160 个字符。")
        }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BridgeError("正文不能为空。")
        }
        guard body.utf8.count <= Self.maxBodyBytes else { throw BridgeError("正文最多 512 KiB（UTF-8）。") }

        let packet = Packet(
            id: id,
            createdAt: Date(),
            from: from,
            to: to,
            subject: title,
            body: body,
            replyTo: replyTo,
            threadId: threadId,
            status: status,
            workspacePath: workspacePath,
            attachedFiles: attachedFiles,
            gitDiffSummary: gitDiffSummary,
            templateId: templateId,
            workflowSteps: workflowSteps,
            currentStepIndex: currentStepIndex
        )
        try writePacket(packet, overwrite: false)
        return packet
    }

    private func writePacket(_ packet: Packet, overwrite: Bool) throws {
        try prepareDirectory()
        let data = try Self.encoder().encode(packet)
        let temporary = directory.appendingPathComponent(".\(packet.id.uuidString).\(UUID().uuidString.prefix(6)).tmp")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw BridgeError("无法写入本地收件箱。")
        }
        defer { try? FileManager.default.removeItem(at: temporary) }
        let destination = packetURL(packet.id)
        if overwrite, FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    func prepareDirectory() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard attributes.isDirectory == true, attributes.isSymbolicLink != true else {
            throw BridgeError("收件箱必须是普通目录。")
        }
        let mode = try manager.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        if let mode, mode.intValue & 0o077 != 0 {
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        }
    }

    private func packetURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizePath(_ value: String?) -> String? {
        guard let raw = nonEmpty(value) else { return nil }
        return (raw as NSString).expandingTildeInPath
    }

    private func normalizePaths(_ values: [String]?) -> [String]? {
        guard let values else { return nil }
        let cleaned = values.compactMap { normalizePath($0) }
        return cleaned.isEmpty ? nil : cleaned
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

@MainActor
final class MailboxWatcher {
    private let directory: URL
    private let onChange: @MainActor () -> Void
    private var fileDescriptor: CInt = -1
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?

    init(directory: URL, onChange: @escaping @MainActor () -> Void) {
        self.directory = directory
        self.onChange = onChange
    }

    func start() {
        stop()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        src.setCancelHandler { close(fd) }
        source = src
        src.resume()
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        if let src = source {
            src.cancel()
            source = nil
            fileDescriptor = -1
        } else if fileDescriptor >= 0 {
            close(fileDescriptor)
            fileDescriptor = -1
        }
    }

    private func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
