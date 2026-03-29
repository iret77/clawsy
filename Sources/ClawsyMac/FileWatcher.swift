import Foundation
import CoreServices

class FileWatcher {
    /// Event types derived from FSEvents flags
    enum EventType: String {
        case fileAdded = "file_added"
        case fileChanged = "file_changed"
    }

    /// Weak-reference wrapper passed to FSEvents context — prevents dangling pointer
    /// if the FileWatcher is deallocated while a callback is in-flight.
    private class StreamContext {
        weak var watcher: FileWatcher?
        init(_ watcher: FileWatcher) { self.watcher = watcher }
    }

    private var stream: FSEventStreamRef?
    private var streamContext: StreamContext?
    private let queue = DispatchQueue(label: "ai.clawsy.filewatcher")
    private let url: URL
    /// Callback receives (changedPath, eventType)
    var typedCallback: ((String, EventType) -> Void)?

    init(url: URL) {
        self.url = url
    }

    func start() {
        stop()

        let path = url.path as NSString
        let pathsToWatch = [path] as CFArray

        let ctx = StreamContext(self)
        streamContext = ctx

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(ctx).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
                guard let clientCallBackInfo = clientCallBackInfo else { return }
                let ctx = Unmanaged<StreamContext>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
                guard let watcher = ctx.watcher else { return }

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
