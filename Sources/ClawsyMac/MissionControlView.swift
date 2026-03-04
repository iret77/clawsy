import SwiftUI
import ClawsyShared

struct MissionControlView: View {
    @ObservedObject var taskStore: TaskStore
    @ObservedObject var networkManager: NetworkManager
    @State private var hasWaited = false

    private var allPaused: Bool {
        !taskStore.tasks.isEmpty && taskStore.tasks.allSatisfy(\.isPaused)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                if taskStore.tasks.isEmpty {
                    Text(l10n: "MISSION_CONTROL_TITLE")
                        .font(.headline)
                } else {
                    Text(String(format: NSLocalizedString("MISSION_CONTROL_TITLE_COUNT", bundle: .clawsy, comment: ""), taskStore.tasks.count))
                        .font(.headline)
                }
                Spacer()
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.accentColor)
            }

            if allPaused {
                HStack(spacing: 4) {
                    Image(systemName: "pause.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text(l10n: "MISSION_CONTROL_ALL_PAUSED")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if taskStore.tasks.isEmpty {
                if hasWaited {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text(l10n: "MISSION_CONTROL_EMPTY")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(l10n: "MISSION_CONTROL_EMPTY_HINT")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(l10n: "WAITING_FOR_TASKS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if taskStore.tasks.isEmpty { hasWaited = true }
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(taskStore.tasks) { task in
                            TaskRowView(task: task, taskStore: taskStore)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            // Gateway Sessions Section
            let runningSessions = networkManager.gatewaySessions.filter { session in
                session.status == "running" &&
                !session.id.hasSuffix(":main") &&
                !session.id.contains("clawsy-service") &&
                session.label != "clawsy-service" &&
                session.label != "main"
            }
            if !runningSessions.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                HStack {
                    Text("SUB-AGENTS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(runningSessions.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                ForEach(runningSessions) { session in
                    GatewaySessionRowView(session: session)
                }
            }
        }
        .padding()
        .frame(width: 320, height: 400)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
        .onChange(of: taskStore.tasks.isEmpty) { isEmpty in
            if !isEmpty { hasWaited = false }
        }
    }
}

// MARK: - Model Badge Color (by provider prefix)

private func modelBadgeColor(for model: String?) -> Color {
    guard let m = model?.lowercased() else { return .secondary }
    if m.hasPrefix("anthropic/") || m.contains("claude") { return Color(red: 0.6, green: 0.4, blue: 0.9) }
    if m.hasPrefix("openai/") || m.contains("gpt") { return .green }
    if m.hasPrefix("google/") || m.contains("gemini") { return .blue }
    if m.hasPrefix("meta/") || m.contains("llama") { return .orange }
    return .secondary
}

// MARK: - Progress Bar Gradient

private func progressGradient(for progress: Double) -> LinearGradient {
    let endColor: Color = progress > 0.8 ? .green : .blue
    return LinearGradient(
        colors: [.blue, endColor],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - TaskRowView

struct TaskRowView: View {
    let task: ClawsyTask
    @ObservedObject var taskStore: TaskStore
    @State private var elapsed: TimeInterval = 0
    @State private var isHovering = false
    @State private var animatedProgress: Double = 0

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isComplete: Bool { task.progress >= 1.0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Row 1: Title + model badge
            HStack(spacing: 6) {
                Text(task.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer()

                if let model = task.model {
                    Text(model)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(modelBadgeColor(for: task.model).opacity(0.2))
                        .foregroundColor(modelBadgeColor(for: task.model))
                        .cornerRadius(4)
                }
            }

            // Row 2: Progress bar or checkmark
            if isComplete {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 14))
                    Text(l10n: "MISSION_CONTROL_COMPLETE")
                        .font(.caption)
                        .foregroundColor(.green)
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.1))
                                .frame(height: 6)
                            Capsule()
                                .fill(progressGradient(for: animatedProgress))
                                .frame(width: geo.size.width * CGFloat(animatedProgress), height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(task.progress * 100))%")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32, alignment: .trailing)
                }
            }

            // Row 3: Status text + hover buttons
            HStack(spacing: 4) {
                Text(task.statusText)
                    .font(.caption)
                    .italic()
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if isHovering && !isComplete {
                    Button {
                        taskStore.togglePause(for: task.id)
                    } label: {
                        Image(systemName: task.isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 10))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(task.isPaused ? "Resume" : "Pause")
                    .transition(.opacity)

                    Button {
                        taskStore.requestDetail(for: task)
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Details")
                    .transition(.opacity)
                }
            }

            // Row 4: elapsed time + agent badge
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(formatElapsed(elapsed))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)

                Spacer()

                Text(task.agentName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(3)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(isHovering ? 0.08 : 0.05))
        .cornerRadius(8)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onAppear {
            if let started = task.startedAt {
                elapsed = Date().timeIntervalSince(started)
            }
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = task.progress
            }
        }
        .onChange(of: task.progress) { newValue in
            withAnimation(.easeInOut(duration: 0.4)) {
                animatedProgress = newValue
            }
        }
        .onReceive(timer) { _ in
            guard !isComplete else { return }
            if let started = task.startedAt {
                elapsed = Date().timeIntervalSince(started)
            } else {
                elapsed += 1
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(0, interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 {
            return "0:\(String(format: "%02d", seconds))"
        }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}

// MARK: - GatewaySessionRowView

struct GatewaySessionRowView: View {
    let session: GatewaySession
    @State private var elapsed: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var displayName: String {
        if let label = session.label, !label.isEmpty { return label }
        // Extract readable name from session key (e.g. "agent:main:subagent:uuid" → "subagent")
        let parts = session.id.split(separator: ":")
        if parts.count >= 3 { return String(parts[2]) }
        return session.id
    }

    private var shortModel: String? {
        guard let m = session.model else { return nil }
        // Strip provider prefix: "anthropic/claude-sonnet-4-6" → "claude-sonnet-4-6"
        if m.contains("/") { return String(m.split(separator: "/").last ?? Substring(m)) }
        return m
    }

    var body: some View {
        HStack(spacing: 8) {
            // Running indicator dot
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let model = shortModel {
                    Text(model)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Elapsed time
            HStack(spacing: 2) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
                Text(formatElapsed(elapsed))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.green.opacity(0.06))
        .cornerRadius(6)
        .onAppear {
            if let started = session.startedAt {
                elapsed = Date().timeIntervalSince(started)
            }
        }
        .onReceive(timer) { _ in
            if let started = session.startedAt {
                elapsed = Date().timeIntervalSince(started)
            } else {
                elapsed += 1
            }
        }
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(0, interval))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes == 0 { return "0:\(String(format: "%02d", seconds))" }
        return "\(minutes):\(String(format: "%02d", seconds))"
    }
}
