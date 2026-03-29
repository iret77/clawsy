import Foundation
import Combine

public struct ClawsyTask: Identifiable, Codable {
    public let id: UUID
    public let agentName: String
    public var title: String
    public var progress: Double
    public var statusText: String
    public var timestamp: Date
    public var model: String?
    public var startedAt: Date?
    public var isPaused: Bool
    
    public init(id: UUID = UUID(), agentName: String, title: String, progress: Double, statusText: String, timestamp: Date = Date(), model: String? = nil, startedAt: Date? = nil, isPaused: Bool = false) {
        self.id = id
        self.agentName = agentName
        self.title = title
        self.progress = progress
        self.statusText = statusText
        self.timestamp = timestamp
        self.model = model
        self.startedAt = startedAt
        self.isPaused = isPaused
    }
}

/// Control action written to `pending_control.json` in the App Group container.
public struct PendingControl: Codable {
    public let action: String      // "pause" | "resume" | "request_detail"
    public let taskId: String
    public var title: String?
    public let timestamp: String
    
    public init(action: String, taskId: String, title: String? = nil) {
        self.action = action
        self.taskId = taskId
        self.title = title
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: Date())
    }
}

public class TaskStore: ObservableObject {
    @Published public var tasks: [ClawsyTask] = []
    private let sharedContainerURL: URL?
    private var removalTimers: [UUID: DispatchWorkItem] = [:]
    
    public init() {
        self.sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ai.openclaw.clawsy")
        loadFromSharedContainer()
    }
    
    /// Clear all tasks — called on disconnect so stale tasks don't linger.
    public func clearAll() {
        DispatchQueue.main.async {
            self.removalTimers.values.forEach { $0.cancel() }
            self.removalTimers.removeAll()
            self.tasks.removeAll()
            self.saveToSharedContainer()
        }
    }

    public func updateTask(agentName: String, title: String, progress: Double, statusText: String) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.agentName == agentName && $0.title == title && $0.progress < 1.0 }) {
                self.tasks[index].progress = progress
                self.tasks[index].statusText = statusText
                self.tasks[index].timestamp = Date()
                if progress >= 1.0 { self.scheduleRemoval(for: self.tasks[index].id) }
            } else {
                let newTask = ClawsyTask(agentName: agentName, title: title, progress: progress, statusText: statusText)
                self.tasks.append(newTask)
                if progress >= 1.0 { self.scheduleRemoval(for: newTask.id) }
            }
            self.saveToSharedContainer()
        }
    }
    
    /// Toggle pause state for a task (optimistic UI) and write control file.
    public func togglePause(for taskId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }
        tasks[index].isPaused.toggle()
        let action = tasks[index].isPaused ? "pause" : "resume"
        let control = PendingControl(action: action, taskId: taskId.uuidString)
        writeControl(control)
        saveToSharedContainer()
    }
    
    /// Request detail for a task and write control file.
    public func requestDetail(for task: ClawsyTask) {
        let control = PendingControl(action: "request_detail", taskId: task.id.uuidString, title: task.title)
        writeControl(control)
    }
    
    private func writeControl(_ control: PendingControl) {
        guard let url = sharedContainerURL?.appendingPathComponent("pending_control.json") else { return }
        if let data = try? JSONEncoder().encode(control) {
            try? data.write(to: url, options: .atomic)
        }
    }
    
    /// Schedule automatic removal of a completed task after 10 seconds
    private func scheduleRemoval(for taskId: UUID) {
        removalTimers[taskId]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.tasks.removeAll { $0.id == taskId }
                self.removalTimers.removeValue(forKey: taskId)
                self.saveToSharedContainer()
            }
        }
        removalTimers[taskId] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }
    
    private func saveToSharedContainer() {
        guard let url = sharedContainerURL?.appendingPathComponent("tasks.json") else { return }
        do {
            let data = try JSONEncoder().encode(tasks)
            try data.write(to: url)
        } catch {
            print("Failed to save tasks to shared container: \(error)")
        }
    }
    
    private func loadFromSharedContainer() {
        guard let url = sharedContainerURL?.appendingPathComponent("tasks.json"),
              let data = try? Data(contentsOf: url) else { return }
        do {
            self.tasks = try JSONDecoder().decode([ClawsyTask].self, from: data)
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }
}
