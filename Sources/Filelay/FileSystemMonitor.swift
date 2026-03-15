import Dispatch
import Foundation
import Darwin
import CoreServices

struct WatchTarget: Hashable {
    enum Kind: String {
        case file
        case directory
    }

    var path: String
    var kind: Kind

    var key: String {
        "\(kind.rawValue):\(path)"
    }
}

final class FileSystemMonitor {
    private var source: DispatchSourceFileSystemObject?
    private var eventStream: FSEventStreamRef?
    private let fileDescriptor: CInt

    init?(target: WatchTarget, queue: DispatchQueue, handler: @escaping () -> Void) {
        switch target.kind {
        case .file:
            let fileDescriptor = open(target.path, O_EVTONLY)
            guard fileDescriptor >= 0 else { return nil }

            self.fileDescriptor = fileDescriptor

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
                queue: queue
            )
            source.setEventHandler(handler: handler)
            source.setCancelHandler {
                close(fileDescriptor)
            }
            self.source = source
            source.resume()

        case .directory:
            self.fileDescriptor = -1
            var context = FSEventStreamContext(
                version: 0,
                info: UnsafeMutableRawPointer(Unmanaged.passRetained(DirectoryEventHandler(handler)).toOpaque()),
                retain: { pointer in
                    guard let pointer else { return nil }
                    _ = Unmanaged<DirectoryEventHandler>.fromOpaque(pointer).retain()
                    return UnsafeRawPointer(pointer)
                },
                release: { pointer in
                    guard let pointer else { return }
                    Unmanaged<DirectoryEventHandler>.fromOpaque(pointer).release()
                },
                copyDescription: nil
            )

            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
                guard let info else { return }
                let handlerBox = Unmanaged<DirectoryEventHandler>.fromOpaque(info).takeUnretainedValue()
                handlerBox.handler()
            }

            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                [target.path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.2,
                flags
            ) else {
                return nil
            }

            eventStream = stream
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func invalidate() {
        source?.cancel()
        source = nil

        if let eventStream {
            FSEventStreamStop(eventStream)
            FSEventStreamInvalidate(eventStream)
            FSEventStreamRelease(eventStream)
            self.eventStream = nil
        }
    }

    deinit {
        invalidate()
    }
}

private final class DirectoryEventHandler {
    let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }
}
