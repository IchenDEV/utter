import XCTest
import UtterContracts
@testable import UtterUpdates

final class UpdateBusySignalsTests: XCTestCase {
    private func entry(_ status: CatalogModelStatus) -> CatalogModelEntry {
        var entry = CatalogModelEntry(id: "model", displayName: "model", hint: "", family: nil)
        entry.status = status
        return entry
    }

    func testModelWorkInAnyCatalogHoldsTheRelaunch() {
        for status in [CatalogModelStatus.downloading, .compiling, .loading] {
            let busy = [entry(status)]
            XCTAssertTrue(UpdateBusySignals.isModelBusy(ModelCatalogSnapshot(whisper: busy, text: [], speech: [])), "\(status)")
            XCTAssertTrue(UpdateBusySignals.isModelBusy(ModelCatalogSnapshot(whisper: [], text: busy, speech: [])), "\(status)")
            XCTAssertTrue(UpdateBusySignals.isModelBusy(ModelCatalogSnapshot(whisper: [], text: [], speech: busy)), "\(status)")
        }
    }

    func testSettledStatesDoNotHoldTheRelaunch() {
        let snapshot = ModelCatalogSnapshot(
            whisper: [entry(.ready), entry(.downloaded)],
            text: [entry(.notDownloaded), entry(.unavailable("x"))],
            speech: [entry(.error("x"))])
        XCTAssertFalse(UpdateBusySignals.isModelBusy(snapshot))
        XCTAssertFalse(UpdateBusySignals.isModelBusy(ModelCatalogSnapshot(whisper: [], text: [], speech: [])))
    }
}
