import SwiftUI
import ClawsyShared

struct MissionControlView: View {
    @ObservedObject var taskStore: TaskStore
    
    var body: some View {
        VStack(spacing: 16) {
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
                    VStack(spacing: 20) {
                        ForEach(taskStore.tasks) { task in
                            TaskRow(task: task)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .padding()
        .frame(width: 320, height: 400)
        .background(VisualEffectView(material: .sidebar, blendingMode: .behindWindow))
    }
}

struct TaskRow: View {
    let task: ClawsyTask
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(task.agentName)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                
                Spacer()
                
                Text(task.timestamp, style: .relative)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Text(task.title)
                .font(.subheadline)
                .fontWeight(.medium)
            
            ProgressView(value: task.progress)
                .progressViewStyle(.linear)
                .tint(.accentColor)
            
            Text(task.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
    }
}
