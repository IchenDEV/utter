import UtterPresentationContracts
import SwiftUI

/// One scrolling grouped form that hosts the sections of every member page.
struct SettingsGroupPage: View {
    let members: [PresentationContribution]
    let context: PresentationContext

    var body: some View {
        Form {
            ForEach(members, id: \.id) { member in
                member.view(context)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .settingsPageSurface()
    }
}
