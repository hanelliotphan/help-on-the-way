import SwiftUI

/// The TaskRabbit half of the app: browse the actual people, compare rates and
/// reviews, pick one. Reached from the timing step of a scheduled request, or
/// from the home screen just to have a look.
struct BrowseHelpersView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State var category: HelpCategory
    /// Present when browsing as part of a request — choosing somebody writes
    /// back to the draft and pops the screen.
    var draft: RequestDraft?

    @State private var sort: Matching.Sort = .recommended
    @State private var favoritesOnly = false

    private var address: SavedAddress {
        draft?.address ?? session.homeAddress
    }

    private var matches: [HelperMatch] {
        let all = Matching.candidates(
            for: category, near: address.point, in: session.backend.roster,
            favorites: session.profile.favoriteHelperIDs, withinMiles: 30
        )
        let filtered = favoritesOnly ? all.filter(\.isFavorite) : all
        return Matching.sorted(filtered, by: sort)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                categoryPicker
                controls

                if matches.isEmpty {
                    EmptyBlock(
                        symbol: "person.slash",
                        title: "Nobody here",
                        message: favoritesOnly
                            ? "None of your saved helpers do \(category.title.lowercased())."
                            : "No \(category.title.lowercased()) helpers cover \(address.label) yet."
                    )
                } else {
                    ForEach(matches) { match in
                        Card(padding: 14, spacing: 12) {
                            NavigationLink { HelperProfileView(helper: match.helper, draft: draft) } label: {
                                HelperRow(match: match)
                            }
                            .buttonStyle(.plain)

                            if !match.helper.badges.isEmpty {
                                BadgeRow(badges: match.helper.badges, limit: 2)
                            }

                            if let review = match.helper.reviews.first {
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: "quote.opening")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(review.body)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            if draft != nil {
                                BigButton(title: "Choose \(match.helper.firstName)", symbol: "checkmark") {
                                    choose(match.helper)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.canvas)
        .navigationTitle("Helpers")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let draft { category = draft.category }
        }
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(HelpCategory.allCases) { option in
                    Button {
                        withAnimation(.snappy) { category = option }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: option.symbol)
                                .font(.caption2.weight(.bold))
                            Text(option.shortTitle)
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .foregroundStyle(category == option ? .white : Palette.accent)
                        .background(category == option ? Palette.accent : Palette.accentSoft, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    // Locked to the draft's category — swapping it mid-request
                    // would quietly change the price.
                    .disabled(draft != nil && option != draft?.category)
                    .opacity(draft != nil && option != draft?.category ? 0.3 : 1)
                }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(Matching.Sort.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.caption.weight(.bold))
                    Text(sort.title)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Palette.card, in: Capsule())
            }

            Button {
                withAnimation(.snappy) { favoritesOnly.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                        .font(.caption.weight(.bold))
                    Text("Saved")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .foregroundStyle(favoritesOnly ? .white : .primary)
                .background(favoritesOnly ? Palette.danger : Palette.card, in: Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("\(matches.count) available")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func choose(_ helper: Helper) {
        draft?.chosenHelper = helper
        session.toast = "\(helper.displayName) added to your booking."
        dismiss()
    }
}
