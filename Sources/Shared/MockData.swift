import Foundation

/// The demo neighbourhood. Fixed ids everywhere so favourites, past jobs and
/// reviews still line up after a relaunch — and so tests can name a person.
enum MockData {

    static let homePoint = GeoPoint(latitude: 37.7599, longitude: -122.4148)

    static func fixedID(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
    }

    // MARK: - Account

    static var profile: CustomerProfile {
        CustomerProfile(
            name: "Han-Elliot Phan",
            phone: "(415) 555-0134",
            email: "hanelliotphan@gmail.com",
            creditBalance: .usd(15),
            joined: Calendar.current.date(byAdding: .month, value: -8, to: Date()) ?? Date(),
            favoriteHelperIDs: [fixedID(3)]
        )
    }

    static var addresses: [SavedAddress] {
        [
            SavedAddress(
                id: fixedID(101), label: "Home", symbol: "house.fill",
                street: "1042 Valencia St", unit: "Apt 3B",
                city: "San Francisco", state: "CA", postalCode: "94110",
                point: homePoint,
                accessNotes: "Buzzer 3B. The gate sticks — pull it towards you."
            ),
            SavedAddress(
                id: fixedID(102), label: "Work", symbol: "building.2.fill",
                street: "450 Brannan St", unit: "Floor 2",
                city: "San Francisco", state: "CA", postalCode: "94107",
                point: GeoPoint(latitude: 37.7776, longitude: -122.3948),
                accessNotes: "Front desk will call up. Loading dock on Zoe St."
            ),
            SavedAddress(
                id: fixedID(103), label: "Mum's place", symbol: "heart.fill",
                street: "1385 9th Ave", unit: nil,
                city: "San Francisco", state: "CA", postalCode: "94122",
                point: GeoPoint(latitude: 37.7621, longitude: -122.4665),
                accessNotes: "Side gate, key under the blue pot. Dog is friendly."
            ),
        ]
    }

    /// Card brand and last four only. The app has no field that takes a real
    /// card number, and adding one is deliberately out of scope.
    static var paymentMethods: [PaymentMethod] {
        [
            PaymentMethod(id: fixedID(201), brand: "Visa", last4: "4242", expiry: "07/29", symbol: "creditcard.fill", isDefault: true),
            PaymentMethod(id: fixedID(202), brand: "Amex", last4: "7003", expiry: "11/27", symbol: "creditcard.fill"),
            PaymentMethod(id: fixedID(203), brand: "Apple Pay", last4: "9910", expiry: "—", symbol: "apple.logo"),
        ]
    }

    // MARK: - Helpers

    static let helpers: [Helper] = [
        Helper(
            id: fixedID(1), firstName: "Marisol", lastInitial: "R",
            headline: "Deep cleans and move-outs, 6 years running",
            bio: "I bring everything — vacuum, steamer, non-toxic products. Kitchens and bathrooms are what I'm fastest at, and I'll send photos when I'm done so you can see it before you're home.",
            rating: 4.94, jobsCompleted: 612, hourlyRate: .usd(48),
            skills: [.cleaning, .eventHelp],
            badges: [.backgroundChecked, .topRated, .suppliesIncluded, .insured],
            reviews: [
                Review(id: fixedID(1001), author: "Priya S.", stars: 5, body: "Left the apartment better than the day I moved in. Deposit came back in full.", category: .cleaning, daysAgo: 6),
                Review(id: fixedID(1002), author: "Dan K.", stars: 5, body: "Quiet, quick, and asked before moving anything. Booked again for next month.", category: .cleaning, daysAgo: 19),
                Review(id: fixedID(1003), author: "Alexis W.", stars: 4, body: "Great work. Ran about twenty minutes long, but told me up front.", category: .cleaning, daysAgo: 34),
            ],
            respondsWithinMinutes: 4, yearsExperience: 6, vehicle: "Honda Fit",
            basePoint: homePoint.offset(metersNorth: 900, metersEast: -400), accentHue: 0.02
        ),
        Helper(
            id: fixedID(2), firstName: "Terrence", lastInitial: "B",
            headline: "Licensed handyman — drywall, mounting, leaks",
            bio: "Twelve years in the trade. If it's on a wall, in a wall, or dripping, I've fixed it. I'll tell you straight when a job needs a licensed plumber instead of me.",
            rating: 4.89, jobsCompleted: 848, hourlyRate: .usd(64),
            skills: [.handyman, .assembly, .techHelp],
            badges: [.backgroundChecked, .licensed, .insured, .topRated],
            reviews: [
                Review(id: fixedID(1004), author: "Molly T.", stars: 5, body: "Mounted a 65\" TV on plaster and found the studs first try. Cleaned up the dust too.", category: .handyman, daysAgo: 3),
                Review(id: fixedID(1005), author: "Sam O.", stars: 5, body: "Diagnosed the leak in ten minutes and told me honestly it needed a plumber. Only charged for the hour.", category: .handyman, daysAgo: 12),
                Review(id: fixedID(1006), author: "Ife A.", stars: 5, body: "Patched four holes so well I can't find them.", category: .handyman, daysAgo: 27),
            ],
            respondsWithinMinutes: 7, yearsExperience: 12, vehicle: "Ford Transit",
            basePoint: homePoint.offset(metersNorth: -1600, metersEast: 1200), accentHue: 0.58
        ),
        Helper(
            id: fixedID(3), firstName: "Yuki", lastInitial: "T",
            headline: "Flat-pack specialist. IKEA holds no secrets.",
            bio: "I've built more Kallax units than I can count. Bring me the box and the allen key stays in the bag. Happy to haul the cardboard out when we're done.",
            rating: 4.97, jobsCompleted: 431, hourlyRate: .usd(54),
            skills: [.assembly, .handyman, .moving],
            badges: [.backgroundChecked, .topRated, .quickResponder],
            reviews: [
                Review(id: fixedID(1007), author: "Chris N.", stars: 5, body: "Two wardrobes and a bed frame in under three hours. Unreal.", category: .assembly, daysAgo: 2),
                Review(id: fixedID(1008), author: "Bea L.", stars: 5, body: "Fixed the drawer I'd assembled backwards without making me feel bad about it.", category: .assembly, daysAgo: 9),
                Review(id: fixedID(1009), author: "Omar F.", stars: 5, body: "Anchored everything to the wall for the baby. Thoughtful work.", category: .assembly, daysAgo: 21),
                Review(id: fixedID(1010), author: "Rin K.", stars: 5, body: "Showed up eight minutes after I booked. Still amazed.", category: .assembly, daysAgo: 45),
            ],
            respondsWithinMinutes: 2, yearsExperience: 5, vehicle: "Subaru Outback",
            basePoint: homePoint.offset(metersNorth: 400, metersEast: 700), accentHue: 0.75
        ),
        Helper(
            id: fixedID(4), firstName: "Dominic", lastInitial: "A",
            headline: "Two-person lifts, stairs, and a 16ft truck",
            bio: "Moving help is my whole business. Blankets, straps and a dolly come standard. Third-floor walk-ups don't scare me, but tell me about them so I can plan the day.",
            rating: 4.81, jobsCompleted: 927, hourlyRate: .usd(68),
            skills: [.moving, .delivery, .yardWork],
            badges: [.backgroundChecked, .ownsTruck, .insured],
            reviews: [
                Review(id: fixedID(1011), author: "Hannah B.", stars: 5, body: "Got a sleeper sofa down a spiral staircase. I'd given up before he arrived.", category: .moving, daysAgo: 5),
                Review(id: fixedID(1012), author: "Wes P.", stars: 4, body: "Strong and fast. Truck was smaller than I pictured, so we did two trips.", category: .moving, daysAgo: 16),
                Review(id: fixedID(1013), author: "Nadia H.", stars: 5, body: "Wrapped everything without being asked. Nothing scratched.", category: .moving, daysAgo: 40),
            ],
            respondsWithinMinutes: 11, yearsExperience: 9, vehicle: "16ft box truck",
            basePoint: homePoint.offset(metersNorth: 2600, metersEast: 2100), accentHue: 0.10
        ),
        Helper(
            id: fixedID(5), firstName: "Priya", lastInitial: "N",
            headline: "Store runs, returns, and awkward pickups",
            bio: "Insured driver with a hatchback and a lot of patience for returns desks. I photograph every receipt and every hand-off.",
            rating: 4.91, jobsCompleted: 1_284, hourlyRate: .usd(46),
            skills: [.delivery, .petCare, .techHelp],
            badges: [.backgroundChecked, .quickResponder, .insured, .topRated],
            reviews: [
                Review(id: fixedID(1014), author: "Leo M.", stars: 5, body: "Handled a Costco run and a Home Depot return in one trip. Texted from both.", category: .delivery, daysAgo: 1),
                Review(id: fixedID(1015), author: "Tess R.", stars: 5, body: "Picked up a mattress topper I couldn't fit in my car. Zero fuss.", category: .delivery, daysAgo: 8),
                Review(id: fixedID(1016), author: "Gus D.", stars: 5, body: "Stayed on the phone with the store until they honoured the refund.", category: .delivery, daysAgo: 30),
            ],
            respondsWithinMinutes: 3, yearsExperience: 4, vehicle: "Toyota Corolla",
            basePoint: homePoint.offset(metersNorth: -700, metersEast: -1500), accentHue: 0.90
        ),
        Helper(
            id: fixedID(6), firstName: "Ruth", lastInitial: "O",
            headline: "Gardens, hedges, and hauling the green waste",
            bio: "Mower, trimmer, blower and rake all come with me. I'll edge the beds and sweep the path down before I leave, because a tidy edge is the part you actually notice.",
            rating: 4.86, jobsCompleted: 356, hourlyRate: .usd(50),
            skills: [.yardWork, .moving, .cleaning],
            badges: [.backgroundChecked, .ownsTruck, .suppliesIncluded],
            reviews: [
                Review(id: fixedID(1017), author: "Jerome S.", stars: 5, body: "Front yard went from embarrassing to sharp in three hours.", category: .yardWork, daysAgo: 7),
                Review(id: fixedID(1018), author: "Kat V.", stars: 4, body: "Good work. Bring your own bags if you have a lot of clippings.", category: .yardWork, daysAgo: 24),
            ],
            respondsWithinMinutes: 14, yearsExperience: 7, vehicle: "Tacoma with trailer",
            basePoint: homePoint.offset(metersNorth: -2900, metersEast: 900), accentHue: 0.33
        ),
        Helper(
            id: fixedID(7), firstName: "Elias", lastInitial: "K",
            headline: "Wi-Fi, TVs, printers — patient with all of it",
            bio: "I fix the network, then I write down what I did so you can do it yourself next time. No jargon unless you want it.",
            rating: 4.95, jobsCompleted: 502, hourlyRate: .usd(58),
            skills: [.techHelp, .assembly, .handyman],
            badges: [.backgroundChecked, .topRated, .quickResponder],
            reviews: [
                Review(id: fixedID(1019), author: "Dot W.", stars: 5, body: "Sorted my mum's whole setup and left instructions in big print. Above and beyond.", category: .techHelp, daysAgo: 4),
                Review(id: fixedID(1020), author: "Kenji I.", stars: 5, body: "Found the dead-spot problem was the router in a cupboard. Ten minutes.", category: .techHelp, daysAgo: 18),
                Review(id: fixedID(1021), author: "Marta G.", stars: 5, body: "Migrated everything to the new laptop while I made lunch.", category: .techHelp, daysAgo: 52),
            ],
            respondsWithinMinutes: 5, yearsExperience: 8, vehicle: nil,
            basePoint: homePoint.offset(metersNorth: 1500, metersEast: -1800), accentHue: 0.62
        ),
        Helper(
            id: fixedID(8), firstName: "Camila", lastInitial: "S",
            headline: "Dog walks, drop-ins, and vet runs",
            bio: "Certified in pet first aid. Every walk comes with a GPS track and an unreasonable number of photos. Comfortable with reactive dogs — just tell me first.",
            rating: 4.98, jobsCompleted: 743, hourlyRate: .usd(40),
            skills: [.petCare, .delivery],
            badges: [.backgroundChecked, .topRated, .quickResponder, .insured],
            reviews: [
                Review(id: fixedID(1022), author: "Bryn A.", stars: 5, body: "My anxious rescue actually likes her. That's never happened.", category: .petCare, daysAgo: 2),
                Review(id: fixedID(1023), author: "Fern T.", stars: 5, body: "Drove us to the emergency vet at 9pm. I won't forget it.", category: .petCare, daysAgo: 11),
                Review(id: fixedID(1024), author: "Ollie C.", stars: 5, body: "Photos every visit. Litter box spotless.", category: .petCare, daysAgo: 29),
            ],
            respondsWithinMinutes: 2, yearsExperience: 6, vehicle: "Nissan Leaf",
            basePoint: homePoint.offset(metersNorth: 300, metersEast: -600), accentHue: 0.47
        ),
        Helper(
            id: fixedID(9), firstName: "Grigor", lastInitial: "M",
            headline: "Event setup and teardown crews",
            bio: "I run a four-person crew for parties, pop-ups and receptions. Tables, chairs, linens, bar, and a full haul-out at the end of the night.",
            rating: 4.78, jobsCompleted: 214, hourlyRate: .usd(45),
            skills: [.eventHelp, .moving, .cleaning],
            badges: [.backgroundChecked, .insured, .ownsTruck],
            reviews: [
                Review(id: fixedID(1025), author: "Susannah D.", stars: 5, body: "Set 120 covers in ninety minutes and stayed to strike it all down.", category: .eventHelp, daysAgo: 13),
                Review(id: fixedID(1026), author: "Ravi B.", stars: 4, body: "Crew was great. Confirm your headcount early — they book out.", category: .eventHelp, daysAgo: 38),
            ],
            respondsWithinMinutes: 26, yearsExperience: 11, vehicle: "Two vans",
            basePoint: homePoint.offset(metersNorth: 3400, metersEast: -2600), accentHue: 0.80
        ),
        Helper(
            id: fixedID(10), firstName: "Nia", lastInitial: "F",
            headline: "Weekly cleans, laundry, and reset days",
            bio: "I'm the person you book every other Thursday. Consistent routine, same checklist each visit, and I'll flag anything that looks like it needs a repair.",
            rating: 4.88, jobsCompleted: 398, hourlyRate: .usd(44),
            skills: [.cleaning, .petCare],
            badges: [.backgroundChecked, .suppliesIncluded],
            reviews: [
                Review(id: fixedID(1027), author: "Theo J.", stars: 5, body: "Six months in and it's never been less than perfect.", category: .cleaning, daysAgo: 5),
                Review(id: fixedID(1028), author: "Aoife R.", stars: 4, body: "Reliable and kind. Ask for the inside of the oven if you want it.", category: .cleaning, daysAgo: 22),
            ],
            respondsWithinMinutes: 9, yearsExperience: 3, vehicle: nil,
            basePoint: homePoint.offset(metersNorth: -1100, metersEast: -300), accentHue: 0.14
        ),
        Helper(
            id: fixedID(11), firstName: "Owen", lastInitial: "H",
            headline: "Odd jobs, hauling, and dump runs",
            bio: "Whatever's in the garage that you'd rather not deal with — I'll load it and take it away. Cash-in-hand simplicity, on the app.",
            rating: 4.72, jobsCompleted: 189, hourlyRate: .usd(42),
            skills: [.moving, .delivery, .yardWork, .handyman],
            badges: [.backgroundChecked, .ownsTruck],
            reviews: [
                Review(id: fixedID(1029), author: "Lorna E.", stars: 5, body: "Cleared a whole garage in an afternoon. No complaints, no upselling.", category: .moving, daysAgo: 10),
                Review(id: fixedID(1030), author: "Ade K.", stars: 4, body: "Solid. Text him the gate code and it's smooth.", category: .delivery, daysAgo: 31),
            ],
            respondsWithinMinutes: 18, yearsExperience: 2, vehicle: "Silverado",
            basePoint: homePoint.offset(metersNorth: -3800, metersEast: -2200), accentHue: 0.55
        ),
        Helper(
            id: fixedID(12), firstName: "Saoirse", lastInitial: "L",
            headline: "Tech help and assembly, evenings and weekends",
            bio: "Day job in IT, evenings on here. Best on smart-home setups, mesh networks, and desks that came in nine boxes.",
            rating: 4.84, jobsCompleted: 147, hourlyRate: .usd(52),
            skills: [.techHelp, .assembly],
            badges: [.backgroundChecked, .quickResponder],
            reviews: [
                Review(id: fixedID(1031), author: "Petra Z.", stars: 5, body: "Whole-house mesh in two hours and explained every step.", category: .techHelp, daysAgo: 6),
                Review(id: fixedID(1032), author: "Cody V.", stars: 5, body: "Standing desk plus three monitor arms. Cable management is art.", category: .assembly, daysAgo: 17),
            ],
            respondsWithinMinutes: 6, yearsExperience: 3, vehicle: "Mazda 3",
            basePoint: homePoint.offset(metersNorth: 2100, metersEast: 400), accentHue: 0.70
        ),
    ]

    static func helper(_ id: UUID) -> Helper? {
        helpers.first { $0.id == id }
    }

    // MARK: - History

    /// A little history so Activity isn't an empty screen on first launch, and
    /// so the receipt and rating views have something real to render.
    static func seedJobs(now: Date = Date()) -> [Job] {
        let addressList = addresses
        let home = addressList[0]
        let mums = addressList[2]

        func daysAgo(_ days: Int, hour: Int) -> Date {
            let calendar = Calendar.current
            let day = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }

        var jobs: [Job] = []

        // A rated deep clean.
        let cleanStart = daysAgo(9, hour: 10)
        var clean = Job(
            id: fixedID(301),
            category: .cleaning,
            title: "Move-out deep clean",
            notes: "Two bed, one bath. Oven and inside of the fridge please — landlord inspects Friday.",
            address: home,
            timing: .scheduled(start: cleanStart),
            estimatedMinutes: 240,
            quote: Pricing.quote(
                category: .cleaning, requestedMinutes: 240, hourlyRate: .usd(48),
                timing: .scheduled(start: cleanStart), now: daysAgo(12, hour: 9)
            ),
            status: .completed,
            helper: helper(fixedID(1)),
            createdAt: daysAgo(12, hour: 9),
            rating: JobRating(stars: 5, comment: "Deposit came back in full. Booking again.", tip: .usd(20), compliments: ["Left it spotless", "On time"]),
            paymentMethodID: fixedID(201),
            billedMinutes: 255,
            helperWasChosen: true
        )
        clean.finalTotal = Pricing.settle(clean.quote, billedMinutes: 255).total
        clean.events = [
            JobEvent(at: cleanStart, status: .accepted, note: "Marisol R. confirmed"),
            JobEvent(at: cleanStart.addingTimeInterval(600), status: .inProgress, note: "Started work"),
            JobEvent(at: cleanStart.addingTimeInterval(15_900), status: .completed, note: "Job completed"),
        ]
        clean.messages = [
            Message(at: cleanStart.addingTimeInterval(-3600), body: "On my way, about 15 minutes out.", fromCustomer: false),
            Message(at: cleanStart.addingTimeInterval(-3400), body: "Perfect, buzzer is 3B.", fromCustomer: true),
            Message(at: cleanStart.addingTimeInterval(15_600), body: "All done — sent photos to your email too.", fromCustomer: false),
        ]
        jobs.append(clean)

        // An instant assembly job, taken by a favourite.
        let assemblyStart = daysAgo(23, hour: 18)
        var assembly = Job(
            id: fixedID(302),
            category: .assembly,
            title: "Two Kallax units and a bed frame",
            notes: "Boxes are in the hallway. Please anchor the tall one to the wall.",
            address: home,
            timing: .now,
            estimatedMinutes: 120,
            quote: Pricing.quote(
                category: .assembly, requestedMinutes: 120, hourlyRate: .usd(54),
                timing: .now, demand: DemandIndex(openRequests: 9, availableHelpers: 8), now: assemblyStart
            ),
            status: .completed,
            helper: helper(fixedID(3)),
            createdAt: assemblyStart,
            rating: JobRating(stars: 5, comment: "Eight minutes to accept. Anchored everything without being asked.", tip: .usd(15), compliments: ["Careful work", "Went above and beyond"]),
            paymentMethodID: fixedID(201),
            billedMinutes: 135
        )
        assembly.finalTotal = Pricing.settle(assembly.quote, billedMinutes: 135).total
        assembly.events = [
            JobEvent(at: assemblyStart, status: .searching, note: "Asked 6 helpers nearby"),
            JobEvent(at: assemblyStart.addingTimeInterval(480), status: .accepted, note: "Yuki T. accepted"),
            JobEvent(at: assemblyStart.addingTimeInterval(1_500), status: .arrived, note: "Arrived at 1042 Valencia St"),
            JobEvent(at: assemblyStart.addingTimeInterval(9_600), status: .completed, note: "Job completed"),
        ]
        jobs.append(assembly)

        // A tech-help visit at a family member's place.
        let techStart = daysAgo(41, hour: 14)
        var tech = Job(
            id: fixedID(303),
            category: .techHelp,
            title: "New router and TV setup",
            notes: "Wi-Fi doesn't reach the back bedroom. Mum is home all afternoon.",
            address: mums,
            timing: .scheduled(start: techStart),
            estimatedMinutes: 90,
            quote: Pricing.quote(
                category: .techHelp, requestedMinutes: 90, hourlyRate: .usd(58),
                timing: .scheduled(start: techStart), now: daysAgo(44, hour: 11)
            ),
            status: .completed,
            helper: helper(fixedID(7)),
            createdAt: daysAgo(44, hour: 11),
            rating: JobRating(stars: 5, comment: "Left written instructions in big print for her. Thoughtful.", tip: .usd(10), compliments: ["Great communication", "Friendly"]),
            paymentMethodID: fixedID(202),
            billedMinutes: 90,
            helperWasChosen: true
        )
        tech.finalTotal = tech.quote.total
        tech.events = [
            JobEvent(at: techStart, status: .accepted, note: "Elias K. confirmed"),
            JobEvent(at: techStart.addingTimeInterval(300), status: .inProgress, note: "Started work"),
            JobEvent(at: techStart.addingTimeInterval(5_700), status: .completed, note: "Job completed"),
        ]
        jobs.append(tech)

        // One cancelled request, so the empty-ish states get exercised too.
        let cancelledAt = daysAgo(4, hour: 12)
        var cancelled = Job(
            id: fixedID(304),
            category: .delivery,
            title: "Pick up a mattress topper",
            notes: "Order is paid for, just needs collecting from the Colma store.",
            address: home,
            timing: .now,
            estimatedMinutes: 60,
            quote: Pricing.quote(category: .delivery, requestedMinutes: 60, hourlyRate: .usd(44), timing: .now, now: cancelledAt),
            status: .cancelled,
            createdAt: cancelledAt,
            paymentMethodID: fixedID(201),
            cancellationReason: "Changed my mind — going myself"
        )
        // Dropped before anyone accepted, so there was nothing to charge.
        cancelled.finalTotal = .zero
        cancelled.events = [
            JobEvent(at: cancelledAt, status: .searching, note: "Asked 4 helpers nearby"),
            JobEvent(at: cancelledAt.addingTimeInterval(90), status: .cancelled, note: "Cancelled before anyone accepted — no charge"),
        ]
        jobs.append(cancelled)

        return jobs.sorted { $0.createdAt > $1.createdAt }
    }
}
