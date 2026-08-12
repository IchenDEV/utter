import Foundation

enum IntegrationXPCConstants {
    static let machServiceName = "\(ProductBrand.bundleIdentifier).xpc"
}

@objc protocol OpenTypeXPCProtocol {
    func createSession(_ requestData: Data, with reply: @escaping (Data?, Data?) -> Void)
    func startRecording(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void)
    func stopRecording(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void)
    func processAudio(
        _ sessionID: String,
        audioData: Data,
        fileExtension: String,
        with reply: @escaping (Data?, Data?) -> Void
    )
    func cancel(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void)
    func snapshotEvents(_ sessionID: String, with reply: @escaping (Data?, Data?) -> Void)
    func subscribeEvents(
        _ sessionID: String,
        endpoint: NSXPCListenerEndpoint,
        with reply: @escaping (String?, Data?) -> Void
    )
    func unsubscribeEvents(_ subscriptionID: String)
}

@objc protocol OpenTypeXPCEventSink {
    func receiveEvent(_ eventData: Data)
}
