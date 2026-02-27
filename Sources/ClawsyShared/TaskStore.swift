import Foundation
import Combine

public struct ClawsyTask: Identifiable, Codable {
    public let id: UUID
    public let agentName: String
    public var title: String
    public var progress: Double
    public var statusText: String
    public var timestamp: Date
    public var runId: String?
    
    public init(id: UUID = UUID(), agentName: String, title: String, progress: Double, statusText: String, timestamp: Date = Date(), runId: String? = nil) {
        self.id = id
        self.agentName = agentName
        self.title = title
        self.progress = progress
        self.statusText = statusText
        self.timestamp = timestamp
        self.runId = runId
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
    
    public func updateTask(agentName: String, title: String, progress: Double, statusText: String, runId: String? = nil) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.agentName == agentName && $0.title == title && $0.progress < 1.0 }) {
                self.tasks[index].progress = progress
                self.tasks[index].statusText = statusText
                self.tasks[index].timestamp = Date()
                if let rid = runId { self.tasks[index].runId = rid }
                if progress >= 1.0 {
                    self.scheduleRemoval(for: self.tasks[index].id)
                }
            } else {
                let newTask = ClawsyTask(agentName: agentName, title: title, progress: progress, statusText: statusText, runId: runId)
                self.tasks.append(newTask)
                if progress >= 1.0 {
                    self.scheduleRemoval(for: newTask.id)
                }
            }
            self.saveToSharedContainer()
        }
    }
    
    /// Mark all tasks for a given runId as complete (progress = 1.0)
    public func completeRun(_ runId: String) {
        DispatchQueue.main.async {
            for i in self.tasks.indices where self.tasks[i].runId == runId && self.tasks[i].progress < 1.0 {
                self.tasks[i].progress = 1.0
                self.tasks[i].statusText = "✓"
                self.tasks[i].timestamp = Date()
                self.scheduleRemoval(for: self.tasks[i].id)
            }
            self.saveToSharedContainer()
        }
    }
    
    /// Schedule automatic removal of a completed task after 10 seconds
    private func scheduleRemoval(for taskId: UUID) {
        // Cancel any existing timer
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
