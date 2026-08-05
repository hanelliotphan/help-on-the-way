import SwiftUI

struct MessagesView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        ScrollView {
            if session.threads.isEmpty {
                EmptyBlock(
                    symbol: "bubble.left.and.bubble.right",
                    title: "No conversations",
                    message: "Once a helper takes a job you can message them here — gate codes, parking, running late."
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(session.threads) { job in
                        NavigationLink { ChatView(jobID: job.id) } label: {
                            Card(padding: 14) {
                                HStack(spacing: 12) {
                                    if let helper = job.helper {
                                        Avatar(helper: helper, size: 46)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(job.helper?.displayName ?? "Helper")
                                                .font(.subheadline.weight(.semibold))
                                            if job.status.isLive {
                                                Chip(text: job.status.title, tint: Palette.tint(for: job.status))
                                            }
                                        }
                                        Text(job.messages.last?.body ?? job.title)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 6)
                                    VStack(alignment: .trailing, spacing: 6) {
                                        Text(Format.ago(job.messages.last?.at ?? job.createdAt, now: session.now))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if job.unreadFromHelper > 0 {
                                            Text("\(job.unreadFromHelper)")
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Palette.danger, in: Capsule())
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .background(Palette.canvas)
        .navigationTitle("Messages")
    }
}

struct ChatView: View {
    @Environment(AppSession.self) private var session
    let jobID: UUID

    @State private var text = ""
    @FocusState private var composerFocused: Bool

    private var job: Job? { session.job(jobID) }

    private let quickReplies = [
        "What's your ETA?",
        "Buzzer is 3B",
        "Park in the driveway",
        "Thanks!",
    ]

    var body: some View {
        VStack(spacing: 0) {
            if let job {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 9) {
                            contextHeader(job)
                            ForEach(job.messages) { message in
                                bubble(message, job: job)
                                    .id(message.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .onChange(of: job.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                }

                composer(job)
            } else {
                EmptyBlock(symbol: "questionmark.circle", title: "Not found", message: "This conversation is gone.")
            }
        }
        .background(Palette.canvas)
        .navigationTitle(job?.helper?.displayName ?? "Messages")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contextHeader(_ job: Job) -> some View {
        VStack(spacing: 7) {
            if let helper = job.helper {
                Avatar(helper: helper, size: 54)
                Text(helper.headline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Chip(text: job.title, symbol: job.category.symbol, tint: Palette.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func bubble(_ message: Message, job: Job) -> some View {
        HStack {
            if message.isSystem {
                Text(message.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Palette.card, in: Capsule())
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            } else {
                if message.fromCustomer { Spacer(minLength: 44) }
                VStack(alignment: message.fromCustomer ? .trailing : .leading, spacing: 3) {
                    Text(message.body)
                        .font(.subheadline)
                        .foregroundStyle(message.fromCustomer ? .white : .primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(
                            message.fromCustomer ? Palette.accent : Palette.card,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                    Text(Format.time(message.at))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !message.fromCustomer { Spacer(minLength: 44) }
            }
        }
    }

    private func composer(_ job: Job) -> some View {
        VStack(spacing: 9) {
            if job.messages.count < 8 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(quickReplies, id: \.self) { reply in
                            Button {
                                session.send(reply, jobID: jobID)
                            } label: {
                                Text(reply)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(Palette.accent)
                                    .background(Palette.accentSoft, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 9) {
                TextField("Message \(job.helper?.firstName ?? "")", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    session.send(text, jobID: jobID)
                    text = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(
                            text.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray.opacity(0.45) : Palette.accent,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
