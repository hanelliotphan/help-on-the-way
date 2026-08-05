import Foundation

/// Deterministic noise. Two runs of the same job draw the same route and pick
/// the same helper, which matters more here than true randomness would.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    init(seed: UUID) {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        withUnsafeBytes(of: seed.uuid) { bytes in
            for byte in bytes {
                hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            }
        }
        state = hash
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A value in -1...1.
    mutating func jitter() -> Double {
        Double(next() % 2000) / 1000 - 1
    }
}

enum Route {
    /// A believable path without a network round-trip: step from origin to
    /// destination in legs, nudging each waypoint sideways so the line bends
    /// like a street grid instead of running as the crow flies.
    ///
    /// The nudge is strictly perpendicular to the straight line. Offsetting on
    /// both axes independently would let a waypoint land *behind* the previous
    /// one, and a helper who visibly reverses down the map reads as a bug.
    static func synthetic(from origin: GeoPoint, to destination: GeoPoint, seed: UUID, legs: Int = 7) -> [GeoPoint] {
        guard legs > 1 else { return [origin, destination] }
        var generator = SplitMix64(seed: seed)

        // Bends scale with the trip: a half-mile hop shouldn't wander a block.
        let sway = min(max(origin.miles(to: destination) * 0.10, 0.015), 0.12) * 1609.344

        let northSpan = (destination.latitude - origin.latitude) * 111_320
        let eastSpan = (destination.longitude - origin.longitude) * 111_320 * cos(origin.latitude * .pi / 180)
        let length = max((northSpan * northSpan + eastSpan * eastSpan).squareRoot(), 1)
        let perpendicularNorth = -eastSpan / length
        let perpendicularEast = northSpan / length

        var points = [origin]
        for leg in 1..<legs {
            let fraction = Double(leg) / Double(legs)
            // Taper towards both ends so the path starts and lands cleanly.
            let amount = generator.jitter() * sway * sin(fraction * .pi)
            let base = origin.interpolated(to: destination, fraction: fraction)
            points.append(base.offset(
                metersNorth: perpendicularNorth * amount,
                metersEast: perpendicularEast * amount
            ))
        }
        points.append(destination)
        return points
    }

    /// Walks the polyline by real distance so a helper crossing a long leg
    /// doesn't visibly speed up.
    static func point(along route: [GeoPoint], fraction: Double) -> GeoPoint {
        guard let first = route.first else { return GeoPoint(latitude: 0, longitude: 0) }
        guard route.count > 1 else { return first }
        let clamped = min(max(fraction, 0), 1)

        var legs: [Double] = []
        var total = 0.0
        for index in 1..<route.count {
            let length = route[index - 1].miles(to: route[index])
            legs.append(length)
            total += length
        }
        guard total > 0 else { return first }

        var travelled = clamped * total
        for (index, length) in legs.enumerated() {
            if travelled <= length || index == legs.count - 1 {
                let within = length > 0 ? travelled / length : 1
                return route[index].interpolated(to: route[index + 1], fraction: within)
            }
            travelled -= length
        }
        return route[route.count - 1]
    }

    /// Compass bearing in degrees, for pointing the car marker the right way.
    static func heading(along route: [GeoPoint], fraction: Double) -> Double {
        let here = point(along: route, fraction: fraction)
        let ahead = point(along: route, fraction: min(fraction + 0.03, 1))
        let deltaLongitude = (ahead.longitude - here.longitude) * cos(here.latitude * .pi / 180)
        let deltaLatitude = ahead.latitude - here.latitude
        guard deltaLatitude != 0 || deltaLongitude != 0 else { return 0 }
        return atan2(deltaLongitude, deltaLatitude) * 180 / .pi
    }
}

/// Everything needed to replay a job's live timeline without a server. All the
/// boundaries are absolute dates, so the current phase is a pure function of
/// "now" — quit the app halfway through a job and reopening lands you exactly
/// where you'd expect rather than restarting the trip.
struct DispatchPlan: Codable, Hashable, Sendable {
    var acceptedAt: Date
    /// Wall-clock seconds allowed per simulated minute. 60 is real time; the
    /// app runs compressed so a whole job is watchable.
    var timeScale: Double
    var confirmMinutes: Double
    var travelMinutes: Int
    var greetMinutes: Double
    var jobMinutes: Int
    var origin: GeoPoint
    var destination: GeoPoint
    var route: [GeoPoint]

    private func seconds(_ minutes: Double) -> TimeInterval { minutes * timeScale }

    var enRouteStartsAt: Date { acceptedAt.addingTimeInterval(seconds(confirmMinutes)) }
    var arrivesAt: Date { enRouteStartsAt.addingTimeInterval(seconds(Double(travelMinutes))) }
    var startsWorkAt: Date { arrivesAt.addingTimeInterval(seconds(greetMinutes)) }
    var finishesAt: Date { startsWorkAt.addingTimeInterval(seconds(Double(jobMinutes))) }

    func status(at now: Date) -> JobStatus {
        if now >= finishesAt { return .completed }
        if now >= startsWorkAt { return .inProgress }
        if now >= arrivesAt { return .arrived }
        if now >= enRouteStartsAt { return .enRoute }
        return .accepted
    }

    /// 0 at the helper's origin, 1 at the customer's door.
    func travelFraction(at now: Date) -> Double {
        let total = arrivesAt.timeIntervalSince(enRouteStartsAt)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(enRouteStartsAt) / total, 0), 1)
    }

    func helperPoint(at now: Date) -> GeoPoint {
        Route.point(along: route, fraction: travelFraction(at: now))
    }

    func helperHeading(at now: Date) -> Double {
        Route.heading(along: route, fraction: travelFraction(at: now))
    }

    /// Minutes until arrival, in the units a customer reads — simulated
    /// minutes, not the compressed seconds the demo actually burns.
    func etaMinutes(at now: Date) -> Int {
        guard now < arrivesAt else { return 0 }
        return Int((arrivesAt.timeIntervalSince(now) / timeScale).rounded(.up))
    }

    func workRemainingMinutes(at now: Date) -> Int {
        guard now < finishesAt else { return 0 }
        guard now >= startsWorkAt else { return jobMinutes }
        return Int((finishesAt.timeIntervalSince(now) / timeScale).rounded(.up))
    }

    func workFraction(at now: Date) -> Double {
        let total = finishesAt.timeIntervalSince(startsWorkAt)
        guard total > 0 else { return 1 }
        return min(max(now.timeIntervalSince(startsWorkAt) / total, 0), 1)
    }

    /// How long the job really ran, for the settlement pass at completion.
    func elapsedWorkMinutes(at now: Date) -> Int {
        guard now > startsWorkAt else { return 0 }
        let capped = min(now, finishesAt)
        return Int((capped.timeIntervalSince(startsWorkAt) / timeScale).rounded())
    }
}

/// What the helper app does to a job in flight.
///
/// The helper never sets `status` directly. Instead each action reshapes the
/// plan's boundaries so that `status(at: now)` *derives* the new phase — tapping
/// "I'm here" shortens `travelMinutes` until `arrivesAt` is now. The plan stays
/// the single source of truth, both apps keep deriving the same phase from it
/// with no coordination, and a job whose window elapsed while an app was closed
/// still resolves correctly.
extension DispatchPlan {

    mutating func markEnRoute(at now: Date) {
        acceptedAt = now.addingTimeInterval(-confirmMinutes * timeScale)
    }

    /// Arriving early cuts the drive short; arriving late stretches it.
    mutating func markArrived(at now: Date) {
        let elapsed = now.timeIntervalSince(enRouteStartsAt) / timeScale
        travelMinutes = max(0, Int(elapsed.rounded()))
    }

    mutating func markWorkStarted(at now: Date) {
        greetMinutes = max(0, now.timeIntervalSince(arrivesAt) / timeScale)
    }

    /// Completion is what sets the billed duration — the job took as long as it
    /// took, and `Pricing.settle` charges for that.
    mutating func markCompleted(at now: Date) {
        jobMinutes = max(1, Int((now.timeIntervalSince(startsWorkAt) / timeScale).rounded()))
    }
}

enum Dispatch {
    /// The demo timeline. One simulated minute every two seconds means a
    /// two-hour clean plays out in about four minutes of watching.
    static let demoTimeScale: Double = 2
    static let realTimeScale: Double = 60

    static let averageSpeedMPH: Double = 19
    /// Straight-line miles under-report the drive; streets don't run diagonally.
    static let streetFactor: Double = 1.35
    static let confirmMinutes: Double = 0.6
    static let greetMinutes: Double = 1.5

    static func travelMinutes(from origin: GeoPoint, to destination: GeoPoint) -> Int {
        let miles = origin.miles(to: destination) * streetFactor
        let minutes = miles / averageSpeedMPH * 60
        // Even a next-street helper needs a few minutes to pack up and park.
        return max(3, Int(minutes.rounded()))
    }

    static func plan(
        helper: Helper,
        destination: GeoPoint,
        jobMinutes: Int,
        acceptedAt: Date,
        timeScale: Double = demoTimeScale,
        seed: UUID
    ) -> DispatchPlan {
        let origin = helper.basePoint
        return DispatchPlan(
            acceptedAt: acceptedAt,
            timeScale: timeScale,
            confirmMinutes: confirmMinutes,
            travelMinutes: travelMinutes(from: origin, to: destination),
            greetMinutes: greetMinutes,
            jobMinutes: jobMinutes,
            origin: origin,
            destination: destination,
            route: Route.synthetic(from: origin, to: destination, seed: seed)
        )
    }
}
