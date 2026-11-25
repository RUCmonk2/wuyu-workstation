import AppKit
import SwiftUI

enum Composer: Identifiable {
    case workflow(WorkflowTemplate)
    case reply(ConversationThread)

    var id: String {
        switch self {
        case .workflow(let tpl): "workflow-\(tpl.rawValue)"
        case .reply(let thread): "reply-\(thread.id.uuidString)"
        }
    }
}

struct ComposePayload {
    let from: Client
    let to: Client
    let subject: String
    let body: String
    let workspacePath: String?
    let attachedFiles: [String]
    let gitDiffSummary: String?
    let template: WorkflowTemplate
    let nextTo: Client?
    let markDone: Bool
    let launchSplitAfterSave: Bool
}

struct ComposeView: View {
    private enum Field: Hashable { case subject, body }

    @Environment(\.workstationPalette) private var colors
    @Environment(\.dismiss) private var dismiss
    @FocusState private var field: Field?

    @State private var template: WorkflowTemplate
    @State private var from: Client
    @State private var to: Client
    @State private var nextRecipient: Client?
    @State private var markDone = false
    @State private var subject = ""
    @State private var text = ""
    @State private var workspacePath = ""
    @State private var attachedFiles: [String] = []
    @State private var gitDiffSummary: String?
    @State private var gitStatusNote: String?
    @State private var isCapturingGit = false
    @State private var launchSplitAfterSave = true
    @State private var errorMessage: String?

    let draft: Composer
    let onSave: (ComposePayload) throws -> Void

    init(draft: Composer, onSave: @escaping (ComposePayload) throws -> Void) {
        self.draft = draft
        self.onSave = onSave
        switch draft {
        case .workflow(let tpl):
            _template = State(initialValue: tpl)
            _from = State(initialValue: tpl.defaultFrom)
            _to = State(initialValue: tpl.defaultTo)
            _text = State(initialValue: tpl.bodySkeleton)
        case .reply(let thread):
            _template = State(initialValue: .custom)
            let responder = thread.waitingFor ?? thread.latest.to
            let target = thread.root.from == responder ? thread.latest.from : thread.root.from
            _from = State(initialValue: responder)
            _to = State(initialValue: target == responder ? .codex : target)
            _workspacePath = State(initialValue: thread.workspacePath ?? "")
            _launchSplitAfterSave = State(initialValue: false)
        }
    }

    private var replyThread: ConversationThread? {
        if case .reply(let thread) = draft { return thread }
        return nil
    }

    private var title: String { replyThread == nil ? "新建协作 / 启动 Workflow" : "写入阶段回执" }
    private var bodyLabel: String { replyThread == nil ? "任务正文（Markdown）" : "回执内容（Markdown）" }
    private var trimmedSubject: String { subject.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var validationMessage: String? {
        if replyThread == nil && from == to { return "请选择不同的发起方和接收方。" }
        if replyThread == nil && (trimmedSubject.count > 160 || trimmedSubject.utf8.count > 1024) { return "标题最多 160 个字符。" }
        if text.utf8.count > BridgeStore.maxBodyBytes { return "正文最多 512 KiB（UTF-8）。" }
        return nil
    }

    private var canSave: Bool {
        validationMessage == nil
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (replyThread != nil || !trimmedSubject.isEmpty)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(colors.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let thread = replyThread {
                        replyContext(thread)
                    } else {
                        templateStrip
                        routeFields
                        subjectField
                    }
                    contextSection
                    bodyField
                    if let message = errorMessage ?? validationMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .workstationFont(11.5)
                            .foregroundStyle(colors.danger)
                    }
                }
                .padding(22)
            }

            Rectangle().fill(colors.line).frame(height: 1)
            footer
        }
        .foregroundStyle(colors.ink)
        .background(colors.canvas)
        .frame(width: 680, height: replyThread == nil ? 650 : 540)
        .onAppear { field = replyThread == nil ? .subject : .body }
        .onChange(of: subject) { errorMessage = nil }
        .onChange(of: text) { errorMessage = nil }
        .onChange(of: from) { errorMessage = nil }
        .onChange(of: to) { errorMessage = nil }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: replyThread == nil ? "bolt.horizontal.circle" : "arrowshape.turn.up.left")
                .workstationFont(16, weight: .semibold)
                .foregroundStyle(colors.accent)
                .frame(width: 34, height: 34)
                .background(colors.accentWash, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).workstationTitle(21)
                Text(replyThread == nil ? "支持多阶段流水线、项目目录引用与一键抓取 Git Diff" : "提交回执后将自动推进工作流阶段")
                    .workstationFont(11)
                    .foregroundStyle(colors.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private var templateStrip: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("协作 Workflow 模板")
                .workstationFont(11.5, weight: .semibold)
                .foregroundStyle(colors.muted)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(WorkflowTemplate.allCases) { item in
                    let active = template == item
                    Button { applyTemplate(item) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .workstationFont(11.5, weight: .semibold)
                                .foregroundStyle(active ? colors.accent : colors.ink)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .workstationFont(10)
                                .foregroundStyle(colors.muted)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(active ? colors.accentWash : colors.surface, in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(active ? colors.accent : colors.line, lineWidth: active ? 1.3 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            let steps = template.makeSteps()
            if !steps.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .workstationFont(11)
                        .foregroundStyle(colors.accent)
                    ForEach(steps) { step in
                        if step.index > 0 {
                            Image(systemName: "chevron.right").workstationFont(9).foregroundStyle(colors.quiet)
                        }
                        Text("\(step.index + 1). \(step.client.shortLabel) \(step.role)")
                            .workstationFont(10.5, weight: .medium)
                            .foregroundStyle(colors.clientColor(step.client))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(colors.clientWash(step.client), in: RoundedRectangle(cornerRadius: 5))
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
    }

    private var routeFields: some View {
        HStack(alignment: .center, spacing: 14) {
            clientField("发起方", selection: $from)
            Image(systemName: "arrow.right")
                .workstationFont(12, weight: .semibold)
                .foregroundStyle(colors.accent)
                .padding(.top, 14)
            clientField("首轮接收方", selection: $to)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(colors.line).allowsHitTesting(false) }
    }

    private func clientField(_ label: String, selection: Binding<Client>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).workstationFont(11, weight: .semibold).foregroundStyle(colors.muted)
            Picker(label, selection: selection) {
                ForEach(Client.allCases) { client in Text("\(client.label) · \(client.roleHint)").tag(client) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func replyContext(_ thread: ConversationThread) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(thread.subject).workstationFont(14, weight: .semibold).lineLimit(2)
                Spacer()
                if let stage = thread.currentStage {
                    Text("阶段 \(stage.index + 1)：\(stage.role)")
                        .workstationFont(10.5, weight: .semibold)
                        .foregroundStyle(colors.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(colors.accentWash, in: Capsule())
                }
            }
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    Text("回执方").workstationFont(11, weight: .medium).foregroundStyle(colors.muted)
                    Picker("回执方", selection: $from) {
                        ForEach(Client.allCases) { c in Text(c.label).tag(c) }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                HStack(spacing: 6) {
                    Text("下一棒").workstationFont(11, weight: .medium).foregroundStyle(colors.muted)
                    Picker("下一棒", selection: $nextRecipient) {
                        Text("按工作流自动流转").tag(Client?.none)
                        ForEach(Client.allCases) { c in Text(c.label).tag(Client?.some(c)) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Spacer()
                Toggle("标为已完成", isOn: $markDone).toggleStyle(.checkbox).workstationFont(11.5)
            }
        }
        .padding(12)
        .background(colors.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(colors.line).allowsHitTesting(false) }
    }

    private var subjectField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("任务标题").workstationFont(11.5, weight: .semibold)
            TextField("例如：重构登录鉴权并请 Gemini 4 做并发边界审查", text: $subject)
                .textFieldStyle(.plain)
                .workstationFont(13)
                .focused($field, equals: .subject)
                .padding(.horizontal, 11)
                .frame(height: 35)
                .background(colors.field, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(field == .subject ? colors.accent : colors.line)
                        .allowsHitTesting(false)
                }
                .onSubmit { field = .body }
        }
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("项目与文件上下文（可选）").workstationFont(11.5, weight: .semibold).foregroundStyle(colors.muted)
                Spacer()
                Button(action: pickWorkspaceFolder) { Label("选项目目录", systemImage: "folder") }
                    .buttonStyle(WorkstationButtonStyle(.quiet, compact: true))
                Button(action: pickAttachedFiles) { Label("附加文件", systemImage: "paperclip") }
                    .buttonStyle(WorkstationButtonStyle(.quiet, compact: true))
                if !workspacePath.isEmpty {
                    Button(action: captureGitDiff) { Label(isCapturingGit ? "抓取中…" : "抓 Git Diff", systemImage: "arrow.triangle.branch") }
                        .buttonStyle(WorkstationButtonStyle(.secondary, compact: true))
                        .disabled(isCapturingGit)
                }
            }

            if !workspacePath.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").workstationFont(11).foregroundStyle(colors.accent)
                    Text(workspacePath).workstationFont(11).foregroundStyle(colors.ink).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let note = gitStatusNote {
                        Text(note).workstationFont(10.5, weight: .medium).foregroundStyle(colors.success)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(colors.successWash, in: Capsule())
                    }
                    Button { workspacePath = ""; gitDiffSummary = nil; gitStatusNote = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(colors.quiet)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(colors.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(colors.line) }
            }

            if !attachedFiles.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(attachedFiles, id: \.self) { path in
                            HStack(spacing: 5) {
                                Image(systemName: "doc.text").workstationFont(10).foregroundStyle(colors.accent)
                                Text(URL(fileURLWithPath: path).lastPathComponent).workstationFont(11).lineLimit(1)
                                Button { attachedFiles.removeAll { $0 == path } } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(colors.quiet)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(colors.accentWash, in: Capsule())
                            .help(path)
                        }
                    }
                }
            }
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bodyLabel).workstationFont(11.5, weight: .semibold)
                Spacer()
                Text("\(text.utf8.count / 1024) / \(BridgeStore.maxBodyBytes / 1024) KiB")
                    .workstationFont(10.5).monospacedDigit().foregroundStyle(colors.quiet)
                Button(action: pasteText) { Label("粘贴剪贴板", systemImage: "clipboard") }
                    .buttonStyle(WorkstationButtonStyle(.quiet, compact: true))
            }
            TextEditor(text: $text)
                .workstationFont(13.5)
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .focused($field, equals: .body)
                .padding(8)
                .frame(minHeight: 190, maxHeight: 240)
                .background(colors.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(field == .body ? colors.accent : colors.line)
                        .allowsHitTesting(false)
                }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if replyThread == nil {
                Toggle("保存后立刻启动双拼并复制接力指令", isOn: $launchSplitAfterSave)
                    .toggleStyle(.checkbox)
                    .workstationFont(11.5)
                    .foregroundStyle(colors.muted)
            }
            Spacer()
            Button("取消") { dismiss() }
                .buttonStyle(WorkstationButtonStyle(.secondary))
                .keyboardShortcut(.cancelAction)
            Button(replyThread == nil ? "启动并保存" : "提交回执", action: saveDraft)
                .buttonStyle(WorkstationButtonStyle(.primary))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canSave)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }

    private func applyTemplate(_ newTemplate: WorkflowTemplate) {
        let oldSkeleton = template.bodySkeleton
        template = newTemplate
        from = newTemplate.defaultFrom
        to = newTemplate.defaultTo
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text == oldSkeleton {
            text = newTemplate.bodySkeleton
        }
    }

    private func pickWorkspaceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择项目目录"
        if panel.runModal() == .OK, let url = panel.url {
            workspacePath = url.path
            gitDiffSummary = nil
            gitStatusNote = nil
        }
    }

    private func pickAttachedFiles() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.prompt = "添加文件引用"
        if !workspacePath.isEmpty { panel.directoryURL = URL(fileURLWithPath: workspacePath) }
        if panel.runModal() == .OK {
            for url in panel.urls where !attachedFiles.contains(url.path) { attachedFiles.append(url.path) }
        }
    }

    private func captureGitDiff() {
        let ws = workspacePath
        guard !ws.isEmpty else { return }
        isCapturingGit = true
        Task.detached {
            let snapshot = GitContextHelper.captureSnapshot(at: ws)
            await MainActor.run {
                isCapturingGit = false
                if let snapshot {
                    gitDiffSummary = GitContextHelper.formatSnapshotMarkdown(snapshot)
                    gitStatusNote = "分支 \(snapshot.branch) · \(snapshot.changedFiles.count) 个变更文件"
                    for f in snapshot.changedFiles where !attachedFiles.contains(f) { attachedFiles.append(f) }
                } else {
                    errorMessage = "所选目录不是 Git 仓库，无法抓取 Diff。"
                }
            }
        }
    }

    private func saveDraft() {
        let payload = ComposePayload(
            from: from, to: to, subject: replyThread?.subject ?? subject, body: text,
            workspacePath: workspacePath.isEmpty ? nil : workspacePath,
            attachedFiles: attachedFiles, gitDiffSummary: gitDiffSummary,
            template: template, nextTo: nextRecipient, markDone: markDone,
            launchSplitAfterSave: launchSplitAfterSave
        )
        do { try onSave(payload) } catch { errorMessage = error.localizedDescription }
    }

    private func pasteText() {
        guard let pasted = NSPasteboard.general.string(forType: .string), !pasted.isEmpty else {
            errorMessage = "剪贴板没有可粘贴的文本。"
            return
        }
        let separator = text.isEmpty || text.hasSuffix("\n") ? "" : "\n"
        guard text.utf8.count + separator.utf8.count + pasted.utf8.count <= BridgeStore.maxBodyBytes else {
            errorMessage = "粘贴后正文将超过 512 KiB（UTF-8）。"
            return
        }
        text += separator + pasted
        errorMessage = nil
        field = .body
    }
}
