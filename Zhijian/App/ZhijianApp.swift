import SwiftUI

@main
struct ZhijianApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { url in
                    URLSchemeHandler.handle(url)
                }
        }
    }
}
