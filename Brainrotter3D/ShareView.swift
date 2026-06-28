import SwiftUI

struct ShareView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let reel: Reel

    @State private var recipients: [Recipient] = []
    @State private var selected: Set<String> = []
    @State private var query = ""
    @State private var message = ""
    @State private var loading = true
    @State private var sending = false
    @State private var result: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    Section {
                        TextField("Add a message…", text: $message)
                    }
                    Section("Send to") {
                        if loading && recipients.isEmpty {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        }
                        ForEach(recipients) { r in
                            Button { toggle(r.id) } label: { recipientRow(r) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                .searchable(text: $query, prompt: "Search people")
                .onChange(of: query) { _, q in Task { await load(q) } }

                if let result {
                    Text(result).font(.callout).foregroundStyle(result.contains("Sent") ? .green : .red)
                        .padding(.bottom, 6)
                }
            }
            .navigationTitle("Share reel")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if sending { ProgressView() } else { Text("Send (\(selected.count))").bold() }
                    }
                    .disabled(sending || selected.isEmpty)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 560)
        .task { await load("") }
    }

    private func recipientRow(_ r: Recipient) -> some View {
        HStack(spacing: 11) {
            AsyncImage(url: r.picURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                .frame(width: 38, height: 38).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(r.kind == .user ? "@\(r.name)" : r.name).font(.subheadline.bold())
                    if r.verified { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue) }
                }
                Text(r.kind == .thread ? "Group chat" : r.fullName)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: selected.contains(r.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected.contains(r.id) ? .blue : .secondary)
        }
        .padding(.vertical, 2)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func load(_ q: String) async {
        loading = true
        recipients = await model.loadRecipients(q)
        loading = false
    }

    private func send() async {
        sending = true
        let chosen = recipients.filter { selected.contains($0.id) }
        let threadIDs = chosen.filter { $0.kind == .thread }.map(\.id)
        let userIDs = chosen.filter { $0.kind == .user }.map(\.id)
        let ok = await model.share(reel, threadIDs: threadIDs, userIDs: userIDs, text: message)
        sending = false
        result = ok ? "Sent to \(chosen.count)" : "Failed to send"
        if ok { try? await Task.sleep(nanoseconds: 700_000_000); dismiss() }
    }
}

struct LikersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let reel: Reel
    @State private var users: [IGUser] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            List {
                if loading && users.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                ForEach(users) { u in
                    HStack(spacing: 11) {
                        AsyncImage(url: u.picURL) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
                            .frame(width: 38, height: 38).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text("@\(u.username)").font(.subheadline.bold())
                                if u.verified { Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue) }
                            }
                            if !u.fullName.isEmpty {
                                Text(u.fullName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Liked by")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .frame(minWidth: 420, minHeight: 520)
        .task { users = await model.loadLikers(reel); loading = false }
    }
}
