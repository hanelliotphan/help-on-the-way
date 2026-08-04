import Foundation
import Testing

@testable import HelpOnTheWay

@Suite("Dispatch timeline")
struct DispatchTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let origin = GeoPoint(latitude: 37.77, longitude: -122.42)
    private let destination = GeoPoint(latitude: 37.79, longitude: -122.40)

    private func plan(timeScale: Double = 60) -> DispatchPlan {
        DispatchPlan(
            acceptedAt: base,
            timeScale: timeScale,
            confirmMinutes: 1,
            travelMinutes: 10,
            greetMinutes: 2,
            jobMinutes: 60,
            origin: origin,
            destination: destination,
            route: [origin, destination]
        )
    }

    // MARK: Phase boundaries

    @Test("Each phase starts exactly where the last one ends")
    func boundaries() {
        let plan = plan()
        #expect(plan.enRouteStartsAt == base.addingTimeInterval(60))
        #expect(plan.arrivesAt == base.addingTimeInterval(660))
        #expect(plan.startsWorkAt == base.addingTimeInterval(780))
        #expect(plan.finishesAt == base.addingTimeInterval(4380))
    }

    @Test("Status is read off the clock, not stepped through")
    func statusAtEveryPhase() {
        let plan = plan()
        #expect(plan.status(at: base) == .accepted)
        #expect(plan.status(at: base.addingTimeInterval(59)) == .accepted)
        #expect(plan.status(at: base.addingTimeInterval(60)) == .enRoute)
        #expect(plan.status(at: base.addingTimeInterval(659)) == .enRoute)
        #expect(plan.status(at: base.addingTimeInterval(660)) == .arrived)
        #expect(plan.status(at: base.addingTimeInterval(779)) == .arrived)
        #expect(plan.status(at: base.addingTimeInterval(780)) == .inProgress)
        #expect(plan.status(at: base.addingTimeInterval(4379)) == .inProgress)
        #expect(plan.status(at: base.addingTimeInterval(4380)) == .completed)
    }

    @Test("A long-dead job reads as complete, not as something in flight")
    func statusFarInTheFuture() {
        #expect(plan().status(at: base.addingTimeInterval(999_999)) == .completed)
    }

    @Test("Asking twice gives the same answer — the plan holds no state")
    func statusIsPure() {
        let plan = plan()
        let moment = base.addingTimeInterval(700)
        #expect(plan.status(at: moment) == plan.status(at: moment))
        // Reading a later moment first must not affect an earlier one.
        _ = plan.status(at: base.addingTimeInterval(5000))
        #expect(plan.status(at: base.addingTimeInterval(100)) == .enRoute)
    }

    // MARK: ETA

    @Test("ETA counts down in simulated minutes and lands on zero")
    func etaCountsDown() {
        let plan = plan()
        #expect(plan.etaMinutes(at: base) == 11)
        #expect(plan.etaMinutes(at: base.addingTimeInterval(60)) == 10)
        #expect(plan.etaMinutes(at: base.addingTimeInterval(600)) == 1)
        #expect(plan.etaMinutes(at: base.addingTimeInterval(660)) == 0)
        #expect(plan.etaMinutes(at: base.addingTimeInterval(5000)) == 0)
    }

    @Test("A compressed clock shows the same minutes as a real one")
    func etaIgnoresTheDemoTimeScale() {
        let fast = plan(timeScale: 2)
        // Two wall-clock seconds per simulated minute: 20s in, ten minutes left.
        #expect(fast.etaMinutes(at: base.addingTimeInterval(2)) == 10)
        #expect(fast.status(at: base.addingTimeInterval(2)) == .enRoute)
        #expect(fast.status(at: base.addingTimeInterval(146)) == .completed)
    }

    @Test("Remaining work reports the full job before it starts")
    func workRemaining() {
        let plan = plan()
        #expect(plan.workRemainingMinutes(at: base) == 60)
        #expect(plan.workRemainingMinutes(at: base.addingTimeInterval(780)) == 60)
        #expect(plan.workRemainingMinutes(at: base.addingTimeInterval(2580)) == 30)
        #expect(plan.workRemainingMinutes(at: base.addingTimeInterval(4380)) == 0)
    }

    @Test("Elapsed work is capped at the job length")
    func elapsedWorkIsCapped() {
        let plan = plan()
        #expect(plan.elapsedWorkMinutes(at: base) == 0)
        #expect(plan.elapsedWorkMinutes(at: base.addingTimeInterval(2580)) == 30)
        #expect(plan.elapsedWorkMinutes(at: base.addingTimeInterval(99_999)) == 60)
    }

    // MARK: Fractions and position

    @Test("Travel fraction spans zero to one across the drive")
    func travelFraction() {
        let plan = plan()
        #expect(plan.travelFraction(at: base) == 0)
        #expect(abs(plan.travelFraction(at: base.addingTimeInterval(360)) - 0.5) < 0.0001)
        #expect(plan.travelFraction(at: base.addingTimeInterval(660)) == 1)
        #expect(plan.travelFraction(at: base.addingTimeInterval(5000)) == 1)
    }

    @Test("Work fraction spans zero to one across the job")
    func workFraction() {
        let plan = plan()
        #expect(plan.workFraction(at: base.addingTimeInterval(780)) == 0)
        #expect(abs(plan.workFraction(at: base.addingTimeInterval(2580)) - 0.5) < 0.0001)
        #expect(plan.workFraction(at: base.addingTimeInterval(4380)) == 1)
    }

    @Test("The helper starts at their base and finishes at the door")
    func helperPointEndpoints() {
        let plan = plan()
        #expect(plan.helperPoint(at: base) == origin)
        #expect(plan.helperPoint(at: base.addingTimeInterval(660)) == destination)
    }

    @Test("Halfway through the drive is halfway along the line")
    func helperPointMidway() {
        let point = plan().helperPoint(at: base.addingTimeInterval(360))
        #expect(abs(point.latitude - 37.78) < 0.0005)
        #expect(abs(point.longitude - -122.41) < 0.0005)
    }
}

@Suite("Routing")
struct RouteTests {

    private let origin = GeoPoint(latitude: 37.76, longitude: -122.43)
    private let destination = GeoPoint(latitude: 37.79, longitude: -122.40)

    @Test("A route always begins and ends where it should")
    func endpointsAreExact() {
        let route = Route.synthetic(from: origin, to: destination, seed: MockData.fixedID(1))
        #expect(route.first == origin)
        #expect(route.last == destination)
        #expect(route.count == 8)
    }

    @Test("The same job always draws the same road")
    func routeIsDeterministic() {
        let seed = MockData.fixedID(42)
        let first = Route.synthetic(from: origin, to: destination, seed: seed)
        let second = Route.synthetic(from: origin, to: destination, seed: seed)
        #expect(first == second)
    }

    @Test("Different jobs get different roads")
    func differentSeedsDiffer() {
        let first = Route.synthetic(from: origin, to: destination, seed: MockData.fixedID(1))
        let second = Route.synthetic(from: origin, to: destination, seed: MockData.fixedID(2))
        #expect(first != second)
    }

    @Test("A bent route still measures longer than the straight line")
    func routeWandersButStaysNearby() {
        let route = Route.synthetic(from: origin, to: destination, seed: MockData.fixedID(7))
        let direct = origin.miles(to: destination)
        let along = zip(route, route.dropFirst()).reduce(0.0) { $0 + $1.0.miles(to: $1.1) }
        #expect(along >= direct)
        // ...but it shouldn't take a scenic detour either.
        #expect(along < direct * 1.5)
    }

    @Test("Walking the polyline is clamped at both ends")
    func pointAlongIsClamped() {
        let route = Route.synthetic(from: origin, to: destination, seed: MockData.fixedID(3))
        #expect(Route.point(along: route, fraction: -1) == origin)
        #expect(Route.point(along: route, fraction: 2) == destination)
    }

    @Test("A degenerate route doesn't crash the walk")
    func emptyAndSinglePointRoutes() {
        #expect(Route.point(along: [], fraction: 0.5).latitude == 0)
        #expect(Route.point(along: [origin], fraction: 0.5) == origin)
        // Origin and destination identical: nothing to interpolate.
        #expect(Route.point(along: [origin, origin], fraction: 0.5) == origin)
    }

    @Test("Travel time never quotes less than a few minutes")
    func travelTimeHasAFloor() {
        #expect(Dispatch.travelMinutes(from: origin, to: origin) == 3)
        #expect(Dispatch.travelMinutes(from: origin, to: destination) > 3)
    }

    @Test("Further away means longer")
    func travelTimeGrowsWithDistance() {
        let near = origin.offset(metersNorth: 800, metersEast: 0)
        let far = origin.offset(metersNorth: 9000, metersEast: 0)
        #expect(Dispatch.travelMinutes(from: origin, to: near) < Dispatch.travelMinutes(from: origin, to: far))
    }

    @Test("A plan built for a helper starts at that helper's base")
    func planUsesHelperBase() {
        let helper = MockData.helpers[0]
        let plan = Dispatch.plan(
            helper: helper, destination: destination, jobMinutes: 120,
            acceptedAt: Date(), timeScale: 2, seed: MockData.fixedID(9)
        )
        #expect(plan.origin == helper.basePoint)
        #expect(plan.destination == destination)
        #expect(plan.jobMinutes == 120)
        #expect(plan.timeScale == 2)
    }
}

@Suite("Geography")
struct GeoPointTests {

    @Test("Miles between two points is symmetric")
    func distanceIsSymmetric() {
        let a = GeoPoint(latitude: 37.76, longitude: -122.43)
        let b = GeoPoint(latitude: 37.79, longitude: -122.40)
        #expect(abs(a.miles(to: b) - b.miles(to: a)) < 0.0001)
        #expect(a.miles(to: a) == 0)
    }

    @Test("A metre offset comes back out as roughly that many metres")
    func offsetRoundTrips() {
        let start = MockData.homePoint
        let moved = start.offset(metersNorth: 1000, metersEast: 0)
        #expect(abs(start.miles(to: moved) - 0.6214) < 0.01)
    }

    @Test("Interpolation is clamped to the segment")
    func interpolationIsClamped() {
        let a = GeoPoint(latitude: 0, longitude: 0)
        let b = GeoPoint(latitude: 10, longitude: 20)
        #expect(a.interpolated(to: b, fraction: 0) == a)
        #expect(a.interpolated(to: b, fraction: 1) == b)
        #expect(a.interpolated(to: b, fraction: -3) == a)
        #expect(a.interpolated(to: b, fraction: 9) == b)
        #expect(a.interpolated(to: b, fraction: 0.5) == GeoPoint(latitude: 5, longitude: 10))
    }
}
