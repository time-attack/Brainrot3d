import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 4) {
                Image(systemName: "play.rectangle.on.rectangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.pink)
                Text("Reels").font(.largeTitle.bold())
                Text("Log in with Instagram to start scrolling.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .padding(.bottom, 8)

            TextField("Username or email", text: $username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)

            Button {
                Task { await model.login(username: username.trimmingCharacters(in: .whitespaces), password: password) }
            } label: {
                if model.busy { ProgressView() } else { Text("Log in").bold() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || username.isEmpty || password.isEmpty)

            if let err = model.loginError {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .textFieldStyle(.roundedBorder)
        .frame(width: 360)
        .padding(28)
        .glassBackgroundEffect()
    }
}

struct TwoFactorView: View {
    @Environment(AppModel.self) private var model
    let info: TwoFactorInfo
    @State private var method: String
    @State private var code = ""
    @State private var sendLabel = "Send code"

    init(info: TwoFactorInfo) {
        self.info = info
        _method = State(initialValue: info.methods.first?.id ?? "3")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Two-factor").font(.largeTitle.bold())
            Text("This account needs a verification code.")
                .font(.callout).foregroundStyle(.secondary)

            Picker("Method", selection: $method) {
                ForEach(info.methods) { m in Text(m.label).tag(m.id) }
            }
            .pickerStyle(.menu)

            if method != "3" {
                Button(sendLabel) {
                    Task {
                        sendLabel = "Sending…"
                        await model.sendCode(info: info, method: method)
                        sendLabel = "Code sent ✓"
                    }
                }
                .buttonStyle(.bordered)
            }

            TextField("6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)

            Button {
                Task { await model.submitCode(code, info: info, method: method) }
            } label: {
                if model.busy { ProgressView() } else { Text("Verify & enter").bold() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.busy || code.isEmpty)

            if let err = model.loginError {
                Text(err).font(.footnote).foregroundStyle(.red)
            }
        }
        .frame(width: 360)
        .padding(28)
        .glassBackgroundEffect()
    }
}
