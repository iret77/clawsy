import SwiftUI
import ClawsyShared

struct MissionControlView: View {
    @ObservedObject var taskStore: TaskStore
    @State private var hasWaited = false

    private var allPaused: Bool {
        !taskStore.tasks.isEmpty && taskStore.tasks.allSatisfy(\.isPaused)
    }

    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                if taskStore.tasks.isEmpty {
                    Text("MISSION_CONTROL_TITLE", bundle: .clawsy)
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
                    Text("MISSION_CONTROL_ALL_PAUSED", bundle: .clawsy)
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
                        Text("MISSION_CONTROL_EMPTY", bundle: .clawsy)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("MISSION_CONTROL_EMPTY_HINT", bundle: .clawsy)
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("WAITING_FOR_TASKS", bundle: .clawsy)
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
                    Text("MISSION_CONTROL_COMPLETE", bundle: .clawsy)
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
