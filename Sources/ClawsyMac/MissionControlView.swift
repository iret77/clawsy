import SwiftUI
import ClawsyShared

struct MissionControlView: View {
    @ObservedObject var taskStore: TaskStore
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("MISSION_CONTROL_TITLE", bundle: .clawsy)
                    .font(.headline)
                Spacer()
                Image(systemName: "lobster.fill")
                    .foregroundColor(.accentColor)
            }
            
            if taskStore.tasks.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("WAITING_FOR_TASKS", bundle: .clawsy)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
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
    }
}

struct TaskRowView: View {
    let task: ClawsyTask
    @ObservedObject var taskStore: TaskStore
    @State private var elapsed: TimeInterval = 0
    
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Row 1: Progress bar + percentage
            HStack(spacing: 8) {
                ProgressView(value: task.progress)
                    .progressViewStyle(.linear)
                    .tint(task.isPaused ? .yellow : .accentColor)
                
                Text("\(Int(task.progress * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            
            // Row 2: Title
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
            
            // Row 3: Status text + buttons
            HStack {
                Text(task.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Button {
                    taskStore.togglePause(for: task.id)
                } label: {
                    Image(systemName: task.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(task.isPaused ? "Resume" : "Pause")
                
                Button {
                    taskStore.requestDetail(for: task)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Details")
            }
            
            // Row 4: model + elapsed time
            HStack {
                if let model = task.model {
                    Text(model)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if task.model != nil {
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
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
        .frame(maxHeight: 70)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .onAppear {
            if let started = task.startedAt {
                elapsed = Date().timeIntervalSince(started)
            }
        }
        .onReceive(timer) { _ in
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
