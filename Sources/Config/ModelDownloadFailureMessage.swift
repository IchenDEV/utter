import Foundation

enum ModelDownloadFailureMessage {
    static func userFacing(_ error: Error) -> String {
        let errors = errorChain(from: error)

        if errors.contains(where: { isTimeout($0) }) {
            return L("model.download_failed_timeout")
        }
        if errors.contains(where: { isNetworkFailure($0) }) {
            return L("model.download_failed_network")
        }
        if errors.contains(where: { $0.domain == NSCocoaErrorDomain && $0.code == NSFileWriteOutOfSpaceError }) {
            return L("model.download_failed_disk_space")
        }
        if errors.contains(where: { isFilePermissionFailure($0) }) {
            return L("model.download_failed_permission")
        }
        return L("model.download_failed_retry")
    }

    private static func errorChain(from error: Error) -> [NSError] {
        var result: [NSError] = []
        var current: NSError? = error as NSError
        var seen = Set<ObjectIdentifier>()

        while let item = current {
            let identity = ObjectIdentifier(item)
            guard seen.insert(identity).inserted else { break }
            result.append(item)
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return result
    }

    private static func isTimeout(_ error: NSError) -> Bool {
        error.domain == NSURLErrorDomain && error.code == URLError.timedOut.rawValue
    }

    private static func isNetworkFailure(_ error: NSError) -> Bool {
        error.domain == NSURLErrorDomain || error.domain.hasPrefix("Network.")
    }

    private static func isFilePermissionFailure(_ error: NSError) -> Bool {
        guard error.domain == NSCocoaErrorDomain else { return false }
        return [
            NSFileReadNoPermissionError,
            NSFileWriteNoPermissionError,
            NSFileWriteVolumeReadOnlyError,
        ].contains(error.code)
    }
}
