import SwiftUI

@main
struct NoSideMediaCompanionApp: App {
    @StateObject private var session = CompanionSession()
    var body: some Scene { WindowGroup { CompanionRootView().environmentObject(session) } }
}
