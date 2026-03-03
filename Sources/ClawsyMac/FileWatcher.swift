import Foundation
import CoreServices

class FileWatcher {
    /// Event types derived from FSEvents flags
    enum EventType: String {
        case fileAdded = "file_added"
        case fileChanged = "file_changed"
    }

    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "ai.clawsy.filewatcher")
    private let url: URL
    /// Callback receives (changedPath, eventType)
    var callback: ((String) -> Void)?
    var typedCallback: ((String, EventType) -> Void)?

    init(url: URL) {
        self.url = url
    }

    func start() {
        stop()
        
        let path = url.path as NSString
        let pathsToWatch = [path] as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let clientCallBackInfo = clientCallBackInfo else { return }
                let watcher = Unmanaged<FileWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
                
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                let flagsPtr = eventFlags
                
                for i in 0..<numEvents {
                    let path = paths[i]
                    // Ignore .DS_Store and .clawsy changes to avoid infinite loops
                    if path.hasSuffix(".DS_Store") || path.hasSuffix(".clawsy") { continue }
                    
                    // Determine event type from FSEvents flags
                    let eventFlag = flagsPtr[i]
                    let isCreated = (eventFlag & UInt32(kFSEventStreamEventFlagItemCreated)) != 0
                    let eventType: EventType = isCreated ? .fileAdded : .fileChanged
                    
                    watcher.callback?(path)
                    watcher.typedCallback?(path, eventType)
                }
            },
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // Latency
            flags
        )
        
        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }

    deinit {
        stop()
    }
}
