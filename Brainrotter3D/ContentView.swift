import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                ProgressView().controlSize(.large)
            case .login:
                LoginView()
            case .twoFactor(let info):
                TwoFactorView(info: info)
            case .feed:
                ReelsFeedView()
            }
        }
        .environment(model)
        .task { await model.start() }
    }
}
