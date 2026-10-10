import Foundation

package struct EspressoMLXFallbackError: LocalizedError {
    package let espressoFailure: String
    package let mlxFailure: String

    package init(espressoFailure: String, mlxFailure: String) {
        self.espressoFailure = espressoFailure
        self.mlxFailure = mlxFailure
    }

    package var errorDescription: String? {
        L("error.espresso_mlx_fallback_unavailable")
    }

    package var details: String {
        "ANE-LM: \(espressoFailure); MLX: \(mlxFailure)"
    }
}
