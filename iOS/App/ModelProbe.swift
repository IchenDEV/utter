#if DEBUG
import Foundation
import UtterMobile

/// `--polish-probe <model id>` downloads that rewrite model, selects it and runs real rewrites, writing
/// Documents/polish-probe.json after every step so a run can be followed from outside the app. It needs a real
/// device: MLX cannot start in the Simulator.
@MainActor
enum ModelProbe {
    private static var report: [String: Any] = [:]

    static func runIfRequested(_ controller: MobileController) async {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--polish-probe"), index + 1 < arguments.count else { return }
        let id = arguments[index + 1]
        record("model", id)
        await controller.prepareLibrary()
        guard await download(id, controller) else { return }
        await controller.selectModel(id)
        record("selected", controller.polishModel == id)
        let load = await controller.probeLoadPolishModel()
        record("load_seconds", load.seconds); record("load_error", load.error ?? "none")
        guard load.error == nil else { return }
        let samples: [(String, String)] = [
            ("zh", "那个我我想说就是明天下午三点开会然后呢嗯请把那个文档发给我"),
            ("en", "um so i think we should uh meet tomorrow at three pm and and send me the the document"),
            ("zh", "今天天气不错我们去公园玩吧"),
        ]
        var results: [[String: Any]] = []
        for (language, text) in samples {
            let result = await controller.probePolish(text, language: language)
            results.append(["input": text, "output": result.output ?? "<nil: kept original>", "seconds": result.seconds])
            record("samples", results)
        }
        record("done", true)
    }

    private static func download(_ id: String, _ controller: MobileController) async -> Bool {
        if let model = controller.models.first(where: { $0.id == id }), case .blocked(let reason) = model.fit {
            record("error", "blocked on this device: " + reason); return false
        }
        if controller.models.first(where: { $0.id == id })?.downloaded != true {
            await controller.downloadModel(id)
            let deadline = Date().addingTimeInterval(30 * 60)
            while Date() < deadline {
                guard let model = controller.models.first(where: { $0.id == id }) else { record("error", "model not in catalog"); return false }
                record("state", String(describing: model.state)); record("progress", model.progress)
                if model.downloaded { break }
                if model.error != nil { record("error", model.error ?? ""); return false }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        let done = controller.models.first(where: { $0.id == id })?.downloaded == true
        record("downloaded", done)
        return done
    }

    private static func record(_ key: String, _ value: Any) {
        report[key] = value
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: directory.appendingPathComponent("polish-probe.json"))
    }
}
#endif
