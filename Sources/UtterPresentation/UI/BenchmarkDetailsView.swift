import SwiftUI
import UtterContracts

struct BenchmarkDetailsView: View {
    let result: ModelBenchmarkResult
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
            GridRow {
                Text(L("benchmark.workload"))
                Text(L("benchmark.samples"))
                Text("p50")
                Text("p95")
            }.foregroundStyle(.secondary)
            ForEach(Array(result.groups.enumerated()), id: \.offset) { _, group in
                GridRow {
                    Text(L("benchmark." + group.length) + " · " + L(group.cold ? "benchmark.cold" : "benchmark.warm"))
                    Text(String(group.count))
                    Text(String(format: "%.2f s", group.p50Seconds))
                    Text(String(format: "%.2f s", group.p95Seconds))
                }
            }
        }.font(.caption2).monospacedDigit().padding(.leading, 18)
    }
}
