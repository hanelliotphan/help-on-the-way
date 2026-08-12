import SwiftUI

struct ProfileView: View {
    @Environment(AppSession.self) private var session

    private var completed: [Job] {
        session.jobs.filter { $0.status == .completed }
    }

    private var totalSpent: Decimal {
        completed.reduce(Decimal.zero) { $0 + $1.amountDue }
    }

    private var hoursOfHelp: Double {
        completed.reduce(0.0) { $0 + Double($1.billedMinutes ?? $1.quote.minutes) / 60 }
    }

    private var savedHelpers: [Helper] {
        session.backend.roster.filter { session.profile.favoriteHelperIDs.contains($0.id) }
    }

    var body: some View {
        List {
            Section {
                // The header is the natural place to tap to edit yourself, so it
                // is a link now rather than a static block.
                NavigationLink {
                    PersonalDetailsView()
                } label: {
                    HStack(spacing: 14) {
                        Avatar(initials: session.profile.initials, hue: 0.6, size: 58)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.profile.name.isEmpty ? "Add your name" : session.profile.name)
                                .font(.headline)
                            Text(session.profile.phone.isEmpty ? session.profile.email : session.profile.phone)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("Member since \(session.profile.joined.formatted(.dateTime.month(.abbreviated).year()))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                }

                HStack(spacing: 0) {
                    StatBlock(value: "\(completed.count)", caption: "Jobs done", symbol: "checkmark.seal.fill")
                    Divider().frame(height: 38)
                    StatBlock(value: String(format: "%.1f", hoursOfHelp), caption: "Hours of help", symbol: "clock.fill")
                    Divider().frame(height: 38)
                    StatBlock(value: totalSpent.shortCurrency, caption: "Spent", symbol: "creditcard.fill")
                }
                .padding(.vertical, 6)
            }

            if session.profile.creditBalance > 0 {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "gift.fill")
                            .foregroundStyle(Palette.success)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(session.profile.creditBalance.currency) in credit")
                                .font(.subheadline.weight(.semibold))
                            Text("Applied automatically on your next job.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !savedHelpers.isEmpty {
                Section("Saved helpers") {
                    ForEach(savedHelpers) { helper in
                        NavigationLink {
                            HelperProfileView(helper: helper)
                        } label: {
                            HStack(spacing: 11) {
                                Avatar(helper: helper, size: 38)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(helper.displayName)
                                        .font(.subheadline.weight(.medium))
                                    Text("\(Format.rating(helper.rating))★ · \(Format.rate(helper.hourlyRate))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Account") {
                // Also listed explicitly: tapping a header for settings isn't
                // obvious, and this is the row people go looking for.
                NavigationLink {
                    PersonalDetailsView()
                } label: {
                    Label("Personal details", systemImage: "person.text.rectangle")
                }

                NavigationLink {
                    AddressesView()
                } label: {
                    Label {
                        HStack {
                            Text("Addresses")
                            Spacer()
                            Text("\(session.addresses.count)")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                    }
                }

                NavigationLink {
                    PaymentMethodsView()
                } label: {
                    Label {
                        HStack {
                            Text("Payment")
                            Spacer()
                            Text(session.defaultPaymentMethod?.label ?? "None")
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "creditcard")
                    }
                }

                NavigationLink {
                    PromoListView()
                } label: {
                    Label("Promo codes", systemImage: "tag")
                }
            }

            Section("Support") {
                Button {
                    session.toast = "Support chat is out of scope for the demo."
                } label: {
                    Label("Get help with a job", systemImage: "lifepreserver")
                }
                Button {
                    session.toast = "Safety centre is out of scope for the demo."
                } label: {
                    Label("Safety centre", systemImage: "shield.lefthalf.filled")
                }
            }

            Section {
                NavigationLink {
                    DemoToolsView()
                } label: {
                    Label("Demo tools", systemImage: "hammer.circle")
                }
            } footer: {
                Text("Help on the Way runs entirely on-device against a mock dispatcher. No card is ever collected and no data leaves the phone.")
            }
        }
        .navigationTitle("Account")
    }
}

// MARK: - Addresses

struct AddressesView: View {
    @Environment(AppSession.self) private var session

    @State private var editing: SavedAddress?
    @State private var adding = false

    var body: some View {
        List {
            ForEach(session.addresses) { address in
                Button {
                    editing = address
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: address.symbol)
                            .foregroundStyle(Palette.accent)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(address.label)
                                .font(.subheadline.weight(.semibold))
                            Text(address.oneLine)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !address.accessNotes.isEmpty {
                                Text(address.accessNotes)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        session.removeAddress(address.id)
                    }
                }
            }
        }
        .navigationTitle("Addresses")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { address in
            AddressEditorView(address: address) { session.upsert($0) }
        }
        .sheet(isPresented: $adding) {
            AddressEditorView(address: nil) { session.upsert($0) }
        }
    }
}

// MARK: - Payment

struct PaymentMethodsView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        List {
            Section {
                ForEach(session.paymentMethods) { method in
                    Button {
                        session.makeDefault(paymentMethod: method.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: method.symbol)
                                .foregroundStyle(Palette.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(method.label)
                                    .font(.subheadline.weight(.medium))
                                Text(method.expiry == "—" ? "Wallet" : "Expires \(method.expiry)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if method.isDefault {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                Text("These are fixtures. The app has no field that accepts a real card number — adding one is deliberately out of scope.")
            }
        }
        .navigationTitle("Payment")
    }
}

// MARK: - Promos

struct PromoListView: View {
    var body: some View {
        List {
            Section {
                ForEach(Promo.catalog, id: \.code) { promo in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(promo.code)
                            .font(.subheadline.weight(.bold))
                            .monospaced()
                        Text(promo.blurb)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Codes that work")
            } footer: {
                Text("Enter one on the review step of any request.")
            }
        }
        .navigationTitle("Promo codes")
    }
}

// MARK: - Demo tools

struct DemoToolsView: View {
    @Environment(AppSession.self) private var session
    @State private var confirmingReset = false

    private var nextScheduled: Job? { session.upcomingJobs.first }
    private var runningJob: Job? { session.liveJobs.first { $0.dispatch != nil } }

    var body: some View {
        List {
            Section {
                Picker("Clock speed", selection: Binding(
                    get: { session.timeScale },
                    set: { session.timeScale = $0 }
                )) {
                    Text("Fast (1 min ≈ 1s)").tag(1.0)
                    Text("Demo (1 min ≈ 2s)").tag(2.0)
                    Text("Slow (1 min ≈ 6s)").tag(6.0)
                    Text("Real time").tag(60.0)
                }
            } header: {
                Text("Simulation")
            } footer: {
                Text("How much wall-clock time one simulated minute takes. Applies to jobs dispatched from now on.")
            }

            Section {
                Toggle("No helpers available", isOn: Binding(
                    get: { session.backend.simulateNoHelpers },
                    set: { session.backend.simulateNoHelpers = $0 }
                ))
            } footer: {
                Text("Forces the next instant request to come back unmatched, so the recovery path can be checked.")
            }

            Section("Jump the timeline") {
                Button {
                    if let job = nextScheduled { session.fastForward(jobID: job.id) }
                } label: {
                    Label(
                        nextScheduled.map { "Start \"\($0.title)\" now" } ?? "No scheduled job",
                        systemImage: "forward.fill"
                    )
                }
                .disabled(nextScheduled == nil)

                Button {
                    if let job = runningJob { session.finishNow(jobID: job.id) }
                } label: {
                    Label(
                        runningJob.map { "Finish \"\($0.title)\" now" } ?? "No running job",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .disabled(runningJob == nil)
            }

            Section {
                Button(role: .destructive) {
                    confirmingReset = true
                } label: {
                    Label("Reset all demo data", systemImage: "arrow.counterclockwise")
                }
            } footer: {
                Text("Restores the seeded helpers, addresses and job history, and deletes any photos you attached.")
            }
        }
        .navigationTitle("Demo tools")
        .confirmationDialog("Reset everything?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { session.resetDemo() }
            Button("Keep it", role: .cancel) {}
        }
    }
}
