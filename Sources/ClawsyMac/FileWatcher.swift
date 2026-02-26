import Foundation
import CoreServices

class FileWatcher {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "ai.clawsy.filewatcher")
    private let url: URL
    var callback: ((String) -> Void)? // Now returns the changed path

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
                
                for path in paths {
                    // Ignore .DS_Store and .clawsy changes to avoid infinite loops
                    if path.hasSuffix(".DS_Store") || path.hasSuffix(".clawsy") { continue }
                    watcher.callback?(path)
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
