import Foundation
import UtterContracts

package enum DataResources {
    package static var bundle: Bundle {
        ResourceBundle.owned("OpenType_UtterData", fallback: Bundle.module)
    }
}
