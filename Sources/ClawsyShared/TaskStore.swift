import Foundation
import Combine
import ClawsyShared

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
    
    public init() {
        self.sharedContainerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ai.openclaw.clawsy")
        loadFromSharedContainer()
    }
    
    public func updateTask(agentName: String, title: String, progress: Double, statusText: String) {
        DispatchQueue.main.async {
            if let index = self.tasks.firstIndex(where: { $0.agentName == agentName }) {
                self.tasks[index].title = title
                self.tasks[index].progress = progress
                self.tasks[index].statusText = statusText
                self.tasks[index].timestamp = Date()
            } else {
                let newTask = ClawsyTask(agentName: agentName, title: title, progress: progress, statusText: statusText)
                self.tasks.append(newTask)
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
            self.tasks = try JSONDecoder().decode([ClawsyTask].self)
        } catch {
            print("Failed to load tasks: \(error)")
        }
    }
}
