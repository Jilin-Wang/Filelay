import Dispatch
import Foundation
import Darwin

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
    private let fileDescriptor: CInt

    init?(target: WatchTarget, queue: DispatchQueue, handler: @escaping () -> Void) {
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
    }

    func invalidate() {
        source?.cancel()
        source = nil
    }

    deinit {
        invalidate()
    }
}
