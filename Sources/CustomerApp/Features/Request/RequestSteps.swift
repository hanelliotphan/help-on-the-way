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
                Text(Format.rate(category.defaultHourlyRate))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selected ? .white : Palette.accent)
                if !category.supportsInstant {
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
            photosCard

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
    @State private var part: Scheduling.DayPart = .morning

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
            part = Scheduling.DayPart.containing(draft.scheduledStart)
        }
        .onChange(of: draft.minutes) { _, _ in
            // A longer job can empty the part that's on screen; slide to one
            // that still fits rather than showing an empty grid.
            if partSlots.isEmpty, let fallback = firstAvailablePart(on: day) {
                withAnimation(.snappy) { select(part: fallback) }
            }
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
        Scheduling.days(minutes: draft.billableMinutes, now: session.now)
    }

    private var slots: [Date] {
        Scheduling.slots(on: day, minutes: draft.billableMinutes, now: session.now)
    }

    private var availability: [Scheduling.DayPart: Int] {
        Scheduling.availability(on: day, minutes: draft.billableMinutes, now: session.now)
    }

    private var partSlots: [Date] {
        Scheduling.slots(on: day, minutes: draft.billableMinutes, now: session.now, in: part)
    }

    private var scheduledPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            dayRail

            Card(spacing: 11) {
                partPicker

                if partSlots.isEmpty {
                    Text(slots.isEmpty
                         ? "Nothing left on \(Format.day(day, now: session.now).lowercased()) that fits a \(Format.duration(minutes: draft.billableMinutes)) job."
                         : "No \(part.title.lowercased()) slots left. Try another part of the day.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    // Four across keeps a part of day to two or three rows.
                    LazyVGrid(columns: Array(repeating: GridItem(spacing: 7), count: 4), spacing: 7) {
                        ForEach(partSlots, id: \.self) { slot in
                            let selected = slot == draft.scheduledStart
                            Button {
                                draft.scheduledStart = slot
                            } label: {
                                Text(Format.shortTime(slot))
                                    .font(.footnote.weight(.semibold))
                                    .minimumScaleFactor(0.8)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .foregroundStyle(selected ? .white : Palette.planned)
                                    .background(
                                        selected ? Palette.planned : Palette.plannedSoft,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

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

    private var partPicker: some View {
        HStack(spacing: 7) {
            ForEach(Scheduling.DayPart.allCases) { candidate in
                let count = availability[candidate] ?? 0
                let selected = candidate == part
                Button {
                    withAnimation(.snappy) { select(part: candidate) }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: candidate.symbol)
                            .font(.caption)
                        Text(candidate.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(selected ? .white : (count == 0 ? .secondary : Palette.planned))
                    .background(
                        selected ? Palette.planned : (count == 0 ? Color.secondary.opacity(0.1) : Palette.plannedSoft),
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .disabled(count == 0)
            }
        }
    }

    // MARK: Keeping day, part and slot in step

    private func select(day newDay: Date) {
        day = newDay
        guard let firstPart = firstAvailablePart(on: newDay) else { return }
        select(part: firstPart)
    }

    private func select(part newPart: Scheduling.DayPart) {
        part = newPart
        // The selection always has to live inside the part on screen, or the
        // footer would price a slot the customer can no longer see.
        if let first = Scheduling.slots(on: day, minutes: draft.billableMinutes, now: session.now, in: newPart).first,
           !newPart.contains(draft.scheduledStart) || !Calendar.current.isDate(draft.scheduledStart, inSameDayAs: day) {
            draft.scheduledStart = first
        }
    }

    private func firstAvailablePart(on someDay: Date) -> Scheduling.DayPart? {
        let counts = Scheduling.availability(on: someDay, minutes: draft.billableMinutes, now: session.now)
        return Scheduling.DayPart.allCases.first { (counts[$0] ?? 0) > 0 }
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
