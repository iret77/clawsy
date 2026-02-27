import Foundation
import Combine

public struct ClawsyTask: Identifiable, Codable {
    public let id: UUID
    public let agentName: String
    public var title: String
    public var progress: Double
    public var statusText: String
    public var timestamp: Date
    
    public init(id: UUID = UUID(), agentName: String, title: String, progress: Double, statusText: String, timestamp: Date = Date()) {
        self.id = id
        self.agentName = agentName
        self.title = title
        self.progress = progress
        self.statusText = statusText
        self.timestamp = timestamp
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
    
    /// Load tasks from a `.agent_status.json` file in the shared folder.
    /// If `updatedAt` is older than 60 seconds, clears tasks instead.
    public func loadFromFile(_ url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        
        struct StatusFile: Decodable {
            let updatedAt: String
            let tasks: [TaskEntry]
            
            struct TaskEntry: Decodable {
                let id: String
                let agentName: String
                let title: String
                let progress: Double
                let statusText: String
            }
        }
        
        guard let status = try? JSONDecoder().decode(StatusFile.self, from: data) else { return }
        
        // Parse updatedAt as ISO8601
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let updatedDate = formatter.date(from: status.updatedAt) ?? ISO8601DateFormatter().date(from: status.updatedAt) else { return }
        
        DispatchQueue.main.async {
            // If stale (>60s), clear tasks
            if Date().timeIntervalSince(updatedDate) > 60 {
                self.tasks.removeAll()
                self.saveToSharedContainer()
                return
            }
            
            // Replace tasks with file contents
            self.tasks = status.tasks.map { entry in
                ClawsyTask(
                    id: UUID(uuidString: entry.id) ?? UUID(),
                    agentName: entry.agentName,
                    title: entry.title,
                    progress: entry.progress,
                    statusText: entry.statusText,
                    timestamp: updatedDate
                )
            }
            self.saveToSharedContainer()
        }
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
