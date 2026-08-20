import MapKit
import PhotosUI
import SwiftUI

// MARK: - 1. Category

struct CategoryStep: View {
    @Environment(AppSession.self) private var session
    @Bindable var draft: RequestDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick the closest match. You can spell out the details next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: Array(repeating: GridItem(spacing: 11), count: 2), spacing: 11) {
                ForEach(HelpCategory.allCases) { category in
                    Button {
                        withAnimation(.snappy) { draft.select(category: category, now: session.now) }
                    } label: {
                        tile(category)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func tile(_ category: HelpCategory) -> some View {
        let selected = draft.category == category
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: category.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(selected ? .white : Palette.accent)
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            Text(category.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(selected ? .white : .primary)
                .multilineTextAlignment(.leading)
            Text(category.tagline)
                .font(.caption2)
                .foregroundStyle(selected ? .white.opacity(0.85) : .secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Text(category.rateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? .white : Palette.accent)
                if category.trustTier == .enhanced {
                    Chip(text: "Vetted", symbol: "checkmark.shield.fill", tint: selected ? .white : Palette.success)
                } else if !category.supportsInstant {
                    Chip(text: "Scheduled only", tint: selected ? .white : Palette.planned)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            selected ? Palette.accent : Palette.card,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

// MARK: - 2. Details

struct DetailsStep: View {
    @Environment(AppSession.self) private var session
    @Bindable var draft: RequestDraft

    @State private var picked: [PhotosPickerItem] = []
    @State private var isLoadingPhotos = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Job title")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(draft.category.defaultJobTitle, text: $draft.title)
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("What should your helper know?")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if draft.notes.isEmpty {
                                Text(placeholder)
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            durationCard
            rateCard
            photosCard

            if let note = draft.category.vettingNote {
                Card(spacing: 9) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(Palette.success)
                        Text("Extra checks for this work")
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let assurance = Vetting.assurance(for: draft.category) {
                        Text(assurance)
                            .font(.caption)
                            .foregroundStyle(Palette.success)
                    }
                }
            }

            Card(spacing: 9) {
                Text("Usually included")
                    .font(.subheadline.weight(.semibold))
                ForEach(draft.category.checklist, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Palette.success)
                        Text(item)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var placeholder: String {
        switch draft.category {
        case .cleaning: "Two bed, one bath. Oven and inside of the fridge please."
        case .handyman: "Two shelves to mount on plaster, plus a dripping tap."
        case .assembly: "Ikea Pax wardrobe, still boxed in the hallway."
        case .moving: "Sofa and a fridge from a second-floor walk-up."
        case .delivery: "Collect a paid order from the Colma store, drop at mine."
        case .yardWork: "Small front lawn, hedge along the fence, bag the clippings."
        case .techHelp: "New router — Wi-Fi doesn't reach the back bedroom."
        case .petCare: "Two walks and a feed. Friendly beagle, pulls a bit."
        case .eventHelp: "Sixty covers, tables and chairs to set and strike."
        case .babysitting: "Two kids, 4 and 7. Dinner's in the fridge, bed at half seven."
        case .tutoring: "Year 10 maths, struggling with algebra. Mocks in January."
        case .seniorCare: "Company and a hot lunch, plus the Thursday supermarket run."
        case .mealPrep: "Five dinners for two. No pork, and one of us hates coriander."
        // Nothing to hint at — the notes *are* the job description here, so the
        // placeholder asks for the two things a helper can't guess.
        case .custom: "What needs doing, and anything you'd want to know before saying yes to it."
        }
    }

    private var durationCard: some View {
        Card(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("How long do you think it'll take?")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(Format.duration(minutes: draft.minutes))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.accent)
            }

            HStack(spacing: 8) {
                ForEach(draft.category.suggestedMinutes, id: \.self) { option in
                    Button {
                        withAnimation(.snappy) { draft.setMinutes(option, now: session.now) }
                    } label: {
                        Text(Format.compactDuration(minutes: option))
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .foregroundStyle(draft.minutes == option ? .white : Palette.accent)
                            .background(
                                draft.minutes == option ? Palette.accent : Palette.accentSoft,
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Stepper(value: Binding(
                get: { draft.minutes },
                set: { draft.setMinutes($0, now: session.now) }
            ), in: 30...600, step: 30) {
                Text("Adjust in half hours")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if draft.hasMinimumBump {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                    Text("\(draft.category.title) books in a \(Format.duration(minutes: draft.category.minimumMinutes)) minimum — you'll be quoted for that.")
                }
                .font(.caption)
                .foregroundStyle(Palette.instant)
            }

            Text("An estimate, not a commitment. You're billed for the time the job actually takes, rounded to the nearest 15 minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Naming your own hourly rate. Compulsory for Custom, which has no going
    /// rate to fall back on; opt-in everywhere else.
    private var rateCard: some View {
        let band = Negotiation.goingRate(for: draft.category, in: session.backend.roster)

        return Card(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(draft.category == .custom ? "Your rate" : "Rate")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(draft.hourlyRate.map(Format.rate) ?? "Not set")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(draft.hourlyRate == nil
                                     ? Palette.danger
                                     : (draft.isNegotiating ? Palette.instant : Palette.accent))
            }

            if !draft.isNegotiating && draft.hourlyRate == nil {
                // Custom, untouched. No number is shown until the customer picks
                // one, because there isn't one to show.
                VStack(alignment: .leading, spacing: 9) {
                    Text("There's no going rate for a custom job. Name what you're willing to pay and helpers can accept it or come back with their own number.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let band {
                        Text("For comparison, helpers near you charge \(band.lowerBound.shortCurrency)–\(band.upperBound.shortCurrency) an hour.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    BigButton(title: "Set a rate", symbol: "dollarsign.circle", tint: Palette.instant) {
                        draft.startNegotiating(roster: session.backend.roster)
                    }
                }
            } else if draft.isNegotiating {
                HStack(spacing: 12) {
                    Button {
                        draft.setOfferedRate((draft.offeredRate ?? draft.suggestedRate(in: session.backend.roster)) - Negotiation.step)
                    } label: {
                        stepperGlyph("minus")
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 1) {
                        Text((draft.hourlyRate ?? draft.suggestedRate(in: session.backend.roster)).shortCurrency)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Palette.instant)
                        Text("per hour")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        draft.setOfferedRate((draft.offeredRate ?? draft.suggestedRate(in: session.backend.roster)) + Negotiation.step)
                    } label: {
                        stepperGlyph("plus")
                    }
                    .buttonStyle(.plain)
                }

                if let band {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                            .font(.caption2)
                        Text("\(draft.category.title) helpers near you charge \(band.lowerBound.shortCurrency)–\(band.upperBound.shortCurrency)")
                            .font(.caption)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(rateReadout(band: band).1)
                    Text(rateReadout(band: band).0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let issue = draft.rateIssue {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(issue.message)
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.danger)
                }

                if draft.category != .custom {
                    Button("Use the going rate instead") {
                        withAnimation(.snappy) { draft.setOfferedRate(nil) }
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("The going rate for \(draft.category.title.lowercased()). You can offer your own instead and let helpers accept or counter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                QuietButton(title: "Name your own rate", symbol: "tag.fill", tint: Palette.instant) {
                    withAnimation(.snappy) { draft.startNegotiating(roster: session.backend.roster) }
                }
            }
        }
    }

    private func stepperGlyph(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.headline)
            .foregroundStyle(Palette.instant)
            .frame(width: 46, height: 46)
            .background(Palette.instantSoft, in: Circle())
    }

    /// Tells the customer where their number sits, because "is this enough?" is
    /// the only real question when you're naming a rate.
    private func rateReadout(band: ClosedRange<Decimal>) -> (String, Color) {
        // Only called from inside the negotiating branch, where a rate exists;
        // the suggestion is a belt-and-braces fallback rather than a default.
        let rate = draft.hourlyRate ?? draft.suggestedRate(in: session.backend.roster)
        if rate < band.lowerBound {
            return ("Under everyone's rate — expect counters, or nobody biting.", Palette.danger)
        }
        if rate >= band.upperBound {
            return ("At or above the top of the range. Anyone free should take it.", Palette.success)
        }
        let takers = session.backend.roster
            .filter { $0.handles(draft.category) && $0.hourlyRate <= rate }
            .count
        return ("\(takers) of them work at this rate or less.", Palette.success)
    }

    private var photosCard: some View {
        Card(spacing: 11) {
            HStack {
                Text("Photos")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                PhotosPicker(selection: $picked, maxSelectionCount: 6, matching: .images) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }

            if draft.photoNames.isEmpty && !isLoadingPhotos {
                Text("Optional, but a photo of the thing that needs doing gets you a faster yes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(draft.photoNames, id: \.self) { name in
                            JobPhotoView(name: name)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        draft.photoNames.removeAll { $0 == name }
                                        PhotoStore.shared.delete(name)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white, .black.opacity(0.5))
                                    }
                                    .padding(3)
                                }
                        }
                        if isLoadingPhotos {
                            ProgressView()
                                .frame(width: 76, height: 76)
                                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                    }
                }
            }
        }
        .onChange(of: picked) { _, items in
            guard !items.isEmpty else { return }
            isLoadingPhotos = true
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let name = PhotoStore.shared.save(image) {
                        draft.photoNames.append(name)
                    }
                }
                picked = []
                isLoadingPhotos = false
            }
        }
    }
}

// MARK: - 3. Location

struct LocationStep: View {
    @Environment(AppSession.self) private var session
    @Bindable var draft: RequestDraft

    @State private var editing: SavedAddress?
    @State private var addingNew = false

    private var selected: SavedAddress { draft.address ?? session.homeAddress }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card(spacing: 0) {
                ForEach(session.addresses) { saved in
                    Button {
                        draft.address = saved
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(saved.id == selected.id ? Palette.accent : Palette.accentSoft)
                                Image(systemName: saved.symbol)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(saved.id == selected.id ? .white : Palette.accent)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(saved.label)
                                    .font(.subheadline.weight(.semibold))
                                Text(saved.oneLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if saved.id == selected.id {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                        .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    if saved.id != session.addresses.last?.id { Divider() }
                }
            }

            QuietButton(title: "Add a different address", symbol: "plus") { addingNew = true }

            Map(initialPosition: .region(MKCoordinateRegion(
                center: selected.point.coordinate,
                latitudinalMeters: 700,
                longitudinalMeters: 700
            ))) {
                Marker(selected.label, systemImage: selected.symbol, coordinate: selected.point.coordinate)
                    .tint(Palette.accent)
            }
            .frame(height: 168)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .allowsHitTesting(false)

            Card(spacing: 8) {
                HStack {
                    Text("Getting in")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Edit") { editing = selected }
                        .font(.subheadline.weight(.semibold))
                }
                Text(selected.accessNotes.isEmpty ? "No access notes yet — buzzer codes, gate quirks, where to park." : selected.accessNotes)
                    .font(.footnote)
                    .foregroundStyle(selected.accessNotes.isEmpty ? .tertiary : .secondary)
            }
        }
        .sheet(item: $editing) { address in
            AddressEditorView(address: address) { updated in
                session.upsert(updated)
                draft.address = updated
            }
        }
        .sheet(isPresented: $addingNew) {
            AddressEditorView(address: nil) { created in
                session.upsert(created)
                draft.address = created
            }
        }
        .onAppear { if draft.address == nil { draft.address = session.homeAddress } }
    }
}

// MARK: - 4. Timing

struct TimingStep: View {
    @Environment(AppSession.self) private var session
    @Bindable var draft: RequestDraft
    let demand: DemandIndex

    @State private var day: Date = Calendar.current.startOfDay(for: Date())

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            modeToggle

            if draft.wantsInstant {
                instantPanel
            } else {
                scheduledPanel
                helperPicker
            }
        }
        .onAppear {
            day = Calendar.current.startOfDay(for: draft.scheduledStart)
        }
        .onChange(of: draft.scheduledStart) { _, newStart in
            // `RequestDraft.setMinutes` slides the start when a longer job no
            // longer fits; the day rail has to follow it.
            let startOfDay = Calendar.current.startOfDay(for: newStart)
            if !Calendar.current.isDate(startOfDay, inSameDayAs: day) { day = startOfDay }
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 11) {
            modeButton(
                isInstant: true, title: "Now",
                detail: draft.category.supportsInstant
                    ? "\(session.backend.nearbyCount(for: draft.category, near: (draft.address ?? session.homeAddress).point)) nearby"
                    : "Not available",
                symbol: "bolt.fill", tint: Palette.instant
            )
            modeButton(
                isInstant: false, title: "Later",
                detail: "Pick a slot",
                symbol: "calendar", tint: Palette.planned
            )
        }
    }

    private func modeButton(isInstant: Bool, title: String, detail: String, symbol: String, tint: Color) -> some View {
        let selected = draft.wantsInstant == isInstant
        let disabled = isInstant && !draft.category.supportsInstant
        return Button {
            withAnimation(.snappy) { draft.setInstant(isInstant, now: session.now) }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption2)
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(selected ? .white : (disabled ? Color.secondary : tint))
            .background(
                selected ? tint : (disabled ? Color.gray.opacity(0.12) : tint.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private var instantPanel: some View {
        VStack(spacing: 14) {
            Card(spacing: 11) {
                HStack(spacing: 10) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3)
                        .foregroundStyle(Palette.instant)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("We'll ask everyone nearby at once")
                            .font(.subheadline.weight(.semibold))
                        Text("Most instant jobs get picked up in under five minutes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                LabeledRow(label: "Instant dispatch fee", value: Pricing.instantDispatchFee.currency, symbol: "bolt.fill", tint: Palette.instant)
                if demand.isSurging {
                    LabeledRow(
                        label: "Busy-area rate",
                        value: "\(demand.multiplier.formatted(.number.precision(.fractionLength(1))))× on labour",
                        symbol: "chart.line.uptrend.xyaxis", tint: Palette.instant
                    )
                    Text("\(demand.openRequests) open requests against \(demand.availableHelpers) free helpers. Booking a time instead skips this.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledRow(label: "Busy-area rate", value: "None right now", symbol: "checkmark.circle.fill", tint: Palette.success)
                }
            }

            Button {
                withAnimation(.snappy) { draft.setInstant(false, now: session.now) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                    Text("Booking ahead is cheaper — see times")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                }
                .foregroundStyle(Palette.planned)
                .padding(13)
                .background(Palette.plannedSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var days: [Date] {
        Scheduling.days(minutes: draft.billableMinutes, now: session.now, leadMinutes: draft.leadMinutes)
    }

    private var slots: [Date] {
        Scheduling.slots(on: day, minutes: draft.billableMinutes, now: session.now, leadMinutes: draft.leadMinutes)
    }

    private var scheduledPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            dayRail

            Card(spacing: 11) {
                if slots.isEmpty {
                    Text("Nothing left on \(Format.day(day, now: session.now).lowercased()) that fits a \(Format.duration(minutes: draft.billableMinutes)) job.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    timeDropdown

                    Divider()

                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(Palette.planned)
                        Text(Format.window(draft.scheduledStart, minutes: draft.billableMinutes))
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 6)
                        if draft.scheduledStart.timeIntervalSince(session.now) >= Pricing.plannedDiscountLead {
                            Chip(text: "5% off labour", symbol: "tag.fill", tint: Palette.success)
                        }
                    }
                }
            }
        }
    }

    /// One row that opens the day's start times.
    ///
    /// The times are still grouped morning / afternoon / evening, but as sections
    /// *inside* the menu — a flat list of 27 half-hour entries is no nicer to
    /// scroll than the grid of buttons this replaced.
    private var timeDropdown: some View {
        Menu {
            ForEach(Scheduling.DayPart.allCases) { part in
                let partSlots = Scheduling.slots(
                    on: day, minutes: draft.billableMinutes, now: session.now, in: part
                )
                if !partSlots.isEmpty {
                    Section(part.title) {
                        ForEach(partSlots, id: \.self) { slot in
                            Button {
                                draft.scheduledStart = slot
                            } label: {
                                // The tick is drawn rather than relying on a
                                // Picker, so the grouping and the checkmark can
                                // coexist.
                                if slot == draft.scheduledStart {
                                    Label(Format.time(slot), systemImage: "checkmark")
                                } else {
                                    Text(Format.time(slot))
                                }
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.subheadline)
                    .foregroundStyle(Palette.planned)
                Text("Start time")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(Format.time(draft.scheduledStart))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.planned)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.planned)
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(Palette.plannedSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var dayRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { candidate in
                    let selected = Calendar.current.isDate(candidate, inSameDayAs: day)
                    Button {
                        withAnimation(.snappy) { select(day: candidate) }
                    } label: {
                        VStack(spacing: 1) {
                            Text(candidate.formatted(.dateTime.weekday(.abbreviated)))
                                .font(.caption2.weight(.semibold))
                                .opacity(0.8)
                            Text(candidate.formatted(.dateTime.day()))
                                .font(.subheadline.weight(.bold))
                        }
                        .frame(width: 46, height: 48)
                        .foregroundStyle(selected ? .white : .primary)
                        .background(
                            selected ? Palette.planned : Palette.card,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Keeping the day and the chosen time in step

    /// Moving to another day has to move the time too — the old slot belongs to
    /// yesterday, and leaving it there would price a booking the dropdown isn't
    /// showing.
    private func select(day newDay: Date) {
        day = newDay
        guard let first = Scheduling.slots(on: newDay, minutes: draft.billableMinutes, now: session.now).first
        else { return }
        draft.scheduledStart = first
    }

    private var helperPicker: some View {
        Card(spacing: 11) {
            HStack {
                Text("Who does it")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                NavigationLink {
                    BrowseHelpersView(category: draft.category, draft: draft)
                } label: {
                    Text(draft.chosenHelper == nil ? "Choose" : "Change")
                        .font(.subheadline.weight(.semibold))
                }
            }

            if let chosen = draft.chosenHelper {
                HStack(spacing: 11) {
                    Avatar(helper: chosen, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(chosen.displayName)
                            .font(.subheadline.weight(.semibold))
                        HStack(spacing: 4) {
                            Stars(value: chosen.rating, size: 10)
                            Text("\(Format.rating(chosen.rating)) · \(Format.rate(chosen.hourlyRate))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 6)
                    Button {
                        draft.chosenHelper = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Text("Leave it to us and you'll get the highest-rated helper free at that time. Or pick somebody yourself.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
