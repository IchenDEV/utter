import Foundation
import UtterContracts

enum AppResources {
    static var bundle: Bundle { ResourceBundle.owned("OpenType_UtterPresentation", fallback: Bundle.module) }
}
