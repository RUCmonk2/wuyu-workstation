import AppKit
import SwiftUI

private enum MarkdownBlock: Identifiable {
    case heading(id: Int, level: Int, text: String)
    case code(id: Int, language: String, content: String)
    case quote(id: Int, text: String)
    case bullet(id: Int, text: String)
    case numbered(id: Int, marker: String, text: String)
    case divider(id: Int)
    case paragraph(id: Int, text: String)

    var id: Int {
        switch self {
        case .heading(let id, _, _),
             .code(let id, _, _),
             .quote(let id, _),
             .bullet(let id, _),
             .numbered(let id, _, _),
             .divider(let id),
             .paragraph(let id, _):
            return id
        }
    }
}

struct MarkdownContentView: View {
    let text: String
    let showRaw: Bool

    @Environment(\.workstationPalette) private var palette
    @Environment(\.workstationTextScale) private var textScale

    var body: some View {
        if showRaw {
            Text(text)
                .font(.system(size: 13 * textScale, design: .monospaced))
                .foregroundStyle(palette.ink)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(parseBlocks(text)) { block in
                    blockView(block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(_, let level, let content):
            inlineMarkdown(content)
                .workstationFont(level == 1 ? 18 : (level == 2 ? 15.5 : 14), weight: .semibold)
                .foregroundStyle(palette.ink)
                .padding(.top, level == 1 ? 6 : 3)
                .textSelection(.enabled)

        case .code(_, let language, let content):
            CodeBlockCard(language: language, code: content)

        case .quote(_, let content):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(palette.accent.opacity(0.65))
                    .frame(width: 3)
                inlineMarkdown(content)
                    .workstationFont(13)
                    .foregroundStyle(palette.muted)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 2)

        case .bullet(_, let content):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•")
                    .workstationFont(13, weight: .bold)
                    .foregroundStyle(palette.accent)
                inlineMarkdown(content)
                    .workstationFont(13.5)
                    .foregroundStyle(palette.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            .padding(.leading, 4)

        case .numbered(_, let marker, let content):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(marker)
                    .workstationFont(12.5, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(palette.accent)
                    .frame(minWidth: 18, alignment: .trailing)
                inlineMarkdown(content)
                    .workstationFont(13.5)
                    .foregroundStyle(palette.ink)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }

        case .divider:
            Rectangle()
                .fill(palette.line)
                .frame(height: 1)
                .padding(.vertical, 4)

        case .paragraph(_, let content):
            inlineMarkdown(content)
                .workstationFont(13.5)
                .foregroundStyle(palette.ink)
                .lineSpacing(5)
                .textSelection(.enabled)
        }
    }

    private func inlineMarkdown(_ raw: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(raw)
    }

    private func parseBlocks(_ source: String) -> [MarkdownBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var nextID = 0
        var i = 0
        func allocID() -> Int { defer { nextID += 1 }; return nextID }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { i += 1; continue }

            if trimmed.hasPrefix("```") {
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") { i += 1; break }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.code(id: allocID(), language: lang, content: codeLines.joined(separator: "\n")))
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.divider(id: allocID()))
                i += 1
                continue
            }

            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }
                let level = min(hashes.count, 3)
                let rest = trimmed.dropFirst(hashes.count)
                if rest.first == " " || rest.isEmpty {
                    let content = rest.trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty {
                        blocks.append(.heading(id: allocID(), level: level, text: content))
                        i += 1
                        continue
                    }
                }
            }

            if trimmed.hasPrefix("> ") || trimmed == ">" {
                var quoteLines: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.hasPrefix("> ") { quoteLines.append(String(t.dropFirst(2))); i += 1 }
                    else if t == ">" { quoteLines.append(""); i += 1 }
                    else { break }
                }
                blocks.append(.quote(id: allocID(), text: quoteLines.joined(separator: "\n")))
                continue
            }

            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                blocks.append(.bullet(id: allocID(), text: String(trimmed.dropFirst(2))))
                i += 1
                continue
            }

            if let dotIdx = trimmed.firstIndex(of: "."), dotIdx > trimmed.startIndex {
                let prefix = trimmed[..<dotIdx]
                let afterDot = trimmed.index(after: dotIdx)
                if prefix.allSatisfy(\.isNumber), afterDot < trimmed.endIndex, trimmed[afterDot] == " " {
                    blocks.append(.numbered(id: allocID(), marker: String(prefix) + ".", text: String(trimmed[trimmed.index(after: afterDot)...])))
                    i += 1
                    continue
                }
            }

            var paragraphLines: [String] = [line]
            i += 1
            while i < lines.count {
                let peek = lines[i].trimmingCharacters(in: .whitespaces)
                if peek.isEmpty || peek.hasPrefix("```") || peek.hasPrefix("# ") || peek.hasPrefix("## ")
                    || peek.hasPrefix("### ") || peek.hasPrefix("- ") || peek.hasPrefix("* ")
                    || peek.hasPrefix("> ") || peek == "---" { break }
                paragraphLines.append(lines[i])
                i += 1
            }
            blocks.append(.paragraph(id: allocID(), text: paragraphLines.joined(separator: "\n")))
        }
        return blocks
    }
}

private struct CodeBlockCard: View {
    let language: String
    let code: String

    @Environment(\.workstationPalette) private var palette
    @Environment(\.workstationTextScale) private var textScale
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language.isEmpty ? "TEXT" : language.uppercased())
                    .font(.system(size: 10 * textScale, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.quiet)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                } label: {
                    Label(copied ? "已复制" : "复制代码", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5 * textScale, weight: .medium))
                        .foregroundStyle(copied ? palette.success : palette.muted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(palette.sidebar.opacity(0.72))

            Rectangle().fill(palette.line).frame(height: 1)

            ScrollView(.horizontal, showsIndicators: true) {
                Text(code)
                    .font(.system(size: 12 * textScale, design: .monospaced))
                    .foregroundStyle(palette.ink)
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(palette.codeSurface, in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(palette.line)
                .allowsHitTesting(false)
        }
    }
}
