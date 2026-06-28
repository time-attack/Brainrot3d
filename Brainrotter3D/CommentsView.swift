import SwiftUI

struct CommentsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let reel: Reel

    @State private var comments: [IGComment] = []
    @State private var nextMaxID: String?
    @State private var hasMore = false
    @State private var loading = true
    @State private var count: Int?
    @State private var replies: [String: [IGComment]] = [:]      // commentID -> loaded replies
    @State private var expanded: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if !reel.caption.isEmpty {
                    Section {
                        captionRow
                    }
                }
                Section(count.map { "\($0) comments" } ?? "Comments") {
                    if loading && comments.isEmpty {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else if comments.isEmpty {
                        Text("No comments yet.").foregroundStyle(.secondary)
                    }
                    ForEach($comments) { $c in
                        commentRow($c, indented: false)
                        if expanded.contains(c.pk), let kids = replies[c.pk] {
                            ForEach(kids) { k in
                                commentRow(.constant(k), indented: true)
                            }
                        }
                    }
                    if hasMore {
                        Button("Load more comments") { Task { await load() } }
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Comments")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 460, minHeight: 560)
        .task { await load(reset: true) }
    }

    private var captionRow: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(reel.profilePic, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(reel.username)").font(.subheadline.bold())
                Text(reel.caption).font(.callout)
            }
        }
        .padding(.vertical, 2)
    }

    private func commentRow(_ c: Binding<IGComment>, indented: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(c.wrappedValue.profilePic, size: indented ? 26 : 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("@\(c.wrappedValue.username)").font(.subheadline.bold())
                    if c.wrappedValue.verified {
                        Image(systemName: "checkmark.seal.fill").font(.caption2).foregroundStyle(.blue)
                    }
                    if let t = c.wrappedValue.createdAt {
                        Text(relative(t)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if let gif = c.wrappedValue.gifURL {
                    AsyncImage(url: gif) { $0.resizable().scaledToFit() } placeholder: { Color.gray.opacity(0.2) }
                        .frame(maxHeight: 120).clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Text(c.wrappedValue.text).font(.callout)
                }
                if c.wrappedValue.replyCount > 0 && !indented {
                    Button(expanded.contains(c.wrappedValue.pk)
                           ? "Hide replies"
                           : "View \(c.wrappedValue.replyCount) replies") {
                        Task { await toggleReplies(c.wrappedValue) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(spacing: 2) {
                Button {
                    Task { await like(c) }
                } label: {
                    Image(systemName: c.wrappedValue.hasLiked ? "heart.fill" : "heart")
                        .foregroundStyle(c.wrappedValue.hasLiked ? .red : .secondary)
                }
                .buttonStyle(.borderless)
                if c.wrappedValue.likeCount > 0 {
                    Text("\(c.wrappedValue.likeCount)").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, indented ? 28 : 0)
        .padding(.vertical, 2)
    }

    private func avatar(_ url: URL?, size: CGFloat) -> some View {
        AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.gray.opacity(0.3) }
            .frame(width: size, height: size).clipShape(Circle())
    }

    // MARK: actions

    private func load(reset: Bool = false) async {
        loading = true
        let page = await model.loadComments(reel, maxID: reset ? nil : nextMaxID)
        if reset { comments = page.comments } else { comments += page.comments }
        nextMaxID = page.nextMaxID
        hasMore = page.hasMore && page.nextMaxID != nil
        count = page.count
        loading = false
        if let count { model.setCommentCount(reel, count) }
    }

    private func toggleReplies(_ c: IGComment) async {
        if expanded.contains(c.pk) { expanded.remove(c.pk); return }
        if replies[c.pk] == nil { replies[c.pk] = await model.loadReplies(reel, commentID: c.pk) }
        expanded.insert(c.pk)
    }

    private func like(_ c: Binding<IGComment>) async {
        let on = !c.wrappedValue.hasLiked
        c.wrappedValue.hasLiked = on
        c.wrappedValue.likeCount = max(0, c.wrappedValue.likeCount + (on ? 1 : -1))
        _ = await model.toggleCommentLike(c.wrappedValue.pk, on: on)
    }

    private func relative(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        return d.formatted(.relative(presentation: .numeric))
    }
}
