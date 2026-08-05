import MapKit
import SwiftUI

/// Add or edit a place. There's no geocoder behind this — the demo drops the pin
/// near the existing neighbourhood and lets you nudge it, which is enough to
/// exercise everything that depends on a coordinate.
struct AddressEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let address: SavedAddress?
    let onSave: (SavedAddress) -> Void

    @State private var label = ""
    @State private var symbol = "mappin.circle.fill"
    @State private var street = ""
    @State private var unit = ""
    @State private var city = "San Francisco"
    @State private var state = "CA"
    @State private var postalCode = ""
    @State private var accessNotes = ""
    @State private var point = MockData.homePoint

    private let symbols = ["house.fill", "building.2.fill", "heart.fill", "briefcase.fill", "mappin.circle.fill", "tent.fill"]

    private var canSave: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty
            && !street.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name it") {
                    TextField("Home, Work, Mum's place", text: $label)
                    Picker("Icon", selection: $symbol) {
                        ForEach(symbols, id: \.self) { option in
                            Image(systemName: option).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Address") {
                    TextField("Street", text: $street)
                    TextField("Apartment, unit (optional)", text: $unit)
                    TextField("City", text: $city)
                    HStack {
                        TextField("State", text: $state)
                        Divider()
                        TextField("ZIP", text: $postalCode)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: point.coordinate,
                        latitudinalMeters: 900,
                        longitudinalMeters: 900
                    ))) {
                        Marker(label.isEmpty ? "Here" : label, systemImage: symbol, coordinate: point.coordinate)
                            .tint(Palette.accent)
                    }
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets())

                    HStack {
                        Button("Nudge north") { point = point.offset(metersNorth: 220, metersEast: 0) }
                        Spacer()
                        Button("Nudge east") { point = point.offset(metersNorth: 0, metersEast: 220) }
                    }
                    .font(.footnote)
                } header: {
                    Text("Pin")
                } footer: {
                    Text("ETAs and the helpers you see are worked out from this pin.")
                }

                Section {
                    TextField("Buzzer codes, gate quirks, where to park", text: $accessNotes, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Getting in")
                }
            }
            .navigationTitle(address == nil ? "New address" : "Edit address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(.headline)
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let address else {
            // A new pin lands a couple of blocks off the demo home so it isn't
            // stacked on top of an existing marker.
            point = MockData.homePoint.offset(metersNorth: 420, metersEast: 260)
            return
        }
        label = address.label
        symbol = address.symbol
        street = address.street
        unit = address.unit ?? ""
        city = address.city
        state = address.state
        postalCode = address.postalCode
        accessNotes = address.accessNotes
        point = address.point
    }

    private func save() {
        let saved = SavedAddress(
            id: address?.id ?? UUID(),
            label: label.trimmingCharacters(in: .whitespaces),
            symbol: symbol,
            street: street.trimmingCharacters(in: .whitespaces),
            unit: unit.isEmpty ? nil : unit,
            city: city,
            state: state,
            postalCode: postalCode,
            point: point,
            accessNotes: accessNotes
        )
        onSave(saved)
        dismiss()
    }
}
