import SwiftUI
#if os(tvOS)
import UIKit
#endif

@main
struct NasCabTVApp: App {
    @StateObject private var apiClient = APIClient.shared
    @StateObject private var p2pService = P2PService.shared

    #if os(tvOS)
    init() {
        UITextField.appearance().backgroundColor = .clear
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(apiClient)
                .environmentObject(p2pService)
                .preferredColorScheme(.dark)
        }
    }
}
