//
//  NotchSideContent.swift
//  ClaudeIsland
//
//  Left and right menu bar content that flanks the hardware notch.
//  Left side: colored status dots + aggregate summary.
//  Right side: tool detail for the highest-priority active session.
//  Both sides use safe area widths with margin to avoid overlapping
//  app menus (left) and system status icons (right).
//

import SwiftUI

// MARK: - Status Colors (shared)

private func statusColor(for phase: SessionPhase) -> Color {
    switch phase {
    case .processing, .compacting:
        return Color(red: 0.89, green: 0.45, blue: 0.27)  // Claude orange
    case .waitingForApproval:
        return Color(red: 0.85, green: 0.47, blue: 0.34)  // Amber
    case .waitingForInput:
        return Color(red: 0.34, green: 0.81, blue: 0.38)  // Green
    case .idle:
        return .white.opacity(0.3)
    case .ended:
        return .white.opacity(0.15)
    }
}

// MARK: - Left Side (status dots + summary)

struct NotchLeftContent: View {
    let sessions: [SessionState]
    let maxWidth: CGFloat  // safe area width (auxiliaryTopLeftArea * 0.7)

    var body: some View {
        if sessions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 8) {
                // Status dots
                HStack(spacing: 4) {
                    ForEach(sortedSessions, id: \.stableId) { session in
                        Circle()
                            .fill(statusColor(for: session.phase))
                            .frame(width: 7, height: 7)
                    }
                }
                .fixedSize()

                // Summary text
                if let summary = summaryText {
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.trailing, 8)
            .frame(width: maxWidth, alignment: .trailing)
        }
    }

    /// Sessions sorted: attention-needing first, then by creation order
    private var sortedSessions: [SessionState] {
        sessions.sorted { a, b in
            let aPriority = phasePriority(a.phase)
            let bPriority = phasePriority(b.phase)
            if aPriority != bPriority { return aPriority < bPriority }
            return a.createdAt < b.createdAt
        }
    }

    /// Lower number = higher display priority
    private func phasePriority(_ phase: SessionPhase) -> Int {
        switch phase {
        case .waitingForApproval: return 0
        case .processing, .compacting: return 1
        case .waitingForInput: return 2
        case .idle: return 3
        case .ended: return 4
        }
    }

    private var summaryText: String? {
        let pending = sessions.filter { $0.phase.isWaitingForApproval }.count
        let active = sessions.filter { $0.phase == .processing || $0.phase == .compacting }.count
        let ready = sessions.filter { $0.phase == .waitingForInput }.count
        let total = sessions.count

        var parts: [String] = []
        if pending > 0 { parts.append("\(pending) pending") }
        if active > 0 { parts.append("\(active) active") }
        if ready > 0 { parts.append("\(ready) ready") }

        if parts.isEmpty {
            return "\(total) sessions"
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Right Side (tool activity detail)

struct NotchRightContent: View {
    let sessions: [SessionState]
    let maxWidth: CGFloat  // safe area width (auxiliaryTopRightArea * 0.7)

    /// Claude orange
    private let claudeOrange = Color(red: 0.89, green: 0.45, blue: 0.27)

    var body: some View {
        if let text = activityText {
            HStack(spacing: 6) {
                if let icon = activityIcon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(activityColor.opacity(0.6))
                        .fixedSize()
                }
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(activityColor.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.leading, 8)
            .frame(width: maxWidth, alignment: .leading)
        }
    }

    private var activityColor: Color {
        if sessions.contains(where: { $0.phase.isWaitingForApproval }) {
            return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
        if sessions.contains(where: { $0.phase == .processing || $0.phase == .compacting }) {
            return claudeOrange
        }
        return Color(red: 0.34, green: 0.81, blue: 0.38)
    }

    private var activityIcon: String? {
        if sessions.contains(where: { $0.phase.isWaitingForApproval }) {
            return "exclamationmark.triangle.fill"
        }
        if sessions.contains(where: { $0.phase == .processing || $0.phase == .compacting }) {
            return nil  // Spinner is already in the notch pill
        }
        if sessions.contains(where: { $0.phase == .waitingForInput }) {
            return "checkmark.circle.fill"
        }
        return nil
    }

    private var activityText: String? {
        // 1. Pending permission: show tool waiting for approval
        if let pending = sessions.first(where: { $0.phase.isWaitingForApproval }) {
            return pendingContext(for: pending)
        }

        // 2. Processing: show active tool context with project prefix
        if let active = sessions.first(where: { $0.phase == .processing || $0.phase == .compacting }) {
            let prefix = projectPrefix(for: active)
            if let context = toolContext(for: active) {
                return "\(prefix)\(context)"
            }
            // No tool running yet (Claude is thinking/generating)
            return "\(prefix)thinking..."
        }

        // 3. Waiting for input: show what just finished
        if let waiting = sessions.first(where: { $0.phase == .waitingForInput }) {
            let prefix = projectPrefix(for: waiting)
            if let context = lastToolSummary(for: waiting) {
                return "\(prefix)\(context) ✓"
            }
            return "\(prefix)done"
        }

        // 4. All idle
        let activeSessions = sessions.filter { $0.phase != .ended }
        if !activeSessions.isEmpty {
            return "\(activeSessions.count) sessions idle"
        }

        return nil
    }

    /// Project name prefix (only when multiple sessions exist)
    private func projectPrefix(for session: SessionState) -> String {
        let activeSessions = sessions.filter { $0.phase != .ended && $0.phase != .idle }
        if activeSessions.count > 1 {
            return "\(session.bestProjectName): "
        }
        return ""
    }

    /// Format pending permission context
    private func pendingContext(for session: SessionState) -> String? {
        guard let toolName = session.pendingToolName else { return nil }
        let formatted = MCPToolFormatter.formatToolName(toolName)

        // For AskUserQuestion: extract the actual question text from raw input
        if toolName == "AskUserQuestion" {
            if let rawInput = session.activePermission?.toolInput,
               let questionsAnyCodable = rawInput["questions"],
               let questionsArray = questionsAnyCodable.value as? [[String: Any]],
               let firstQuestion = questionsArray.first,
               let questionText = firstQuestion["question"] as? String {
                return "Asking: \(questionText)"
            }
            return "Asking a question"
        }

        if let input = session.pendingToolInput {
            let enriched = enrichMessage(input, toolName: toolName)
            // Skip if the enriched text is just "..." or repeats the tool name
            if enriched != "..." && !enriched.isEmpty {
                return "\(formatted) \(enriched)"
            }
        }
        return formatted
    }

    /// Extract the best tool context string from a session (for active processing)
    private func toolContext(for session: SessionState) -> String? {
        // Task subagent
        if session.subagentState.hasActiveSubagent,
           let taskId = session.subagentState.taskStack.last,
           let task = session.subagentState.activeTasks[taskId],
           let desc = task.description {
            return "Agent: \(desc)"
        }

        // Live tool from tracker (actively running right now)
        if let currentTool = session.toolTracker.inProgress.values
            .sorted(by: { $0.startTime > $1.startTime }).first {
            let formatted = MCPToolFormatter.formatToolName(currentTool.name)

            // The tracker only has the tool name, not its input.
            // Use lastMessage if it was set by the same tool type (heuristic).
            if let msg = session.lastMessage, let lastTool = session.lastToolName {
                // If the last completed tool is the same type, reuse its message
                // Otherwise just show the tool name (message is from a different tool)
                let lastFormatted = MCPToolFormatter.formatToolName(lastTool)
                if lastFormatted == formatted {
                    return "\(formatted) \(enrichMessage(msg, toolName: currentTool.name))"
                }
            }
            return formatted
        }

        // Last completed tool + its context
        return lastToolSummary(for: session)
    }

    /// Format the last completed tool as a summary
    private func lastToolSummary(for session: SessionState) -> String? {
        guard let toolName = session.lastToolName else { return nil }
        let formatted = MCPToolFormatter.formatToolName(toolName)
        if let msg = session.lastMessage {
            return "\(formatted) \(enrichMessage(msg, toolName: toolName))"
        }
        return formatted
    }

    /// Enrich a tool message for better display
    /// Strips parameter name prefixes, extracts domains from URLs, etc.
    private func enrichMessage(_ message: String, toolName: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip common parameter name prefixes (from formattedInput key: value format)
        // The input often contains "command: ...\ndescription: ..." or "file_path: ...\nold_string: ..."
        // Take only the most meaningful line
        let lines = trimmed.components(separatedBy: "\n").filter { !$0.isEmpty }
        let cleaned: String
        if lines.count > 1 {
            // Multiple lines: pick the best one based on tool type
            cleaned = pickBestLine(lines: lines, toolName: toolName)
        } else {
            cleaned = stripParamPrefix(trimmed)
        }

        // Extract domain from URLs
        if cleaned.hasPrefix("http://") || cleaned.hasPrefix("https://") {
            if let url = URL(string: cleaned), let host = url.host {
                let path = url.path
                if path.count > 1 {
                    return "\(host)\(String(path.prefix(30)))"
                }
                return host
            }
        }

        return cleaned
    }

    /// Strip "key: " prefix from a parameter line
    private func stripParamPrefix(_ line: String) -> String {
        let prefixes = ["command: ", "description: ", "file_path: ", "pattern: ",
                        "query: ", "url: ", "prompt: ", "old_string: ", "new_string: ",
                        "content: ", "body: ", "path: "]
        for prefix in prefixes {
            if line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count))
            }
        }
        return line
    }

    /// Pick the most informative line from multi-line tool input
    private func pickBestLine(lines: [String], toolName: String) -> String {
        // For Bash: prefer the command line over description
        if toolName == "Bash" || toolName == "BashOutput" {
            if let cmdLine = lines.first(where: { $0.hasPrefix("command: ") }) {
                return String(cmdLine.dropFirst(9))
            }
        }

        // For Read/Edit/Write: prefer the file path
        if toolName == "Read" || toolName == "Edit" || toolName == "Write" {
            if let pathLine = lines.first(where: { $0.hasPrefix("file_path: ") }) {
                let path = String(pathLine.dropFirst(11))
                return (path as NSString).lastPathComponent
            }
        }

        // For Grep/Glob: prefer the pattern
        if toolName == "Grep" || toolName == "Glob" {
            if let patternLine = lines.first(where: { $0.hasPrefix("pattern: ") }) {
                return String(patternLine.dropFirst(9))
            }
        }

        // Default: take the shortest non-empty line (likely the most concise)
        return stripParamPrefix(lines.min(by: { $0.count < $1.count }) ?? lines[0])
    }
}
