import XCTest
import UserNotifications
@testable import Moonlog

@MainActor
final class ReminderEraseTests: XCTestCase {
    func testEraseSynchronouslyClearsPendingAndDeliveredNotifications() {
        let requests = FakeFeedNotificationRequests()
        requests.pending = ["old-pending"]
        requests.delivered = ["old-delivered"]
        let lifecycle = FeedNotificationLifecycle(requests: requests)
        let epoch = lifecycle.epoch

        lifecycle.cancelAll()

        XCTAssertTrue(requests.pending.isEmpty)
        XCTAssertTrue(requests.delivered.isEmpty)
        XCTAssertEqual(requests.removeAllPendingCalls, 1)
        XCTAssertEqual(requests.removeAllDeliveredCalls, 1)
        XCTAssertNotEqual(lifecycle.epoch, epoch)
    }

    func testAnAddAcceptedAfterEraseCannotResurrectItsNotice() async throws {
        let requests = FakeFeedNotificationRequests()
        requests.holdAdd = true
        let lifecycle = FeedNotificationLifecycle(requests: requests)
        let request = UNNotificationRequest(identifier: UUID().uuidString,
            content: UNMutableNotificationContent(),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 90, repeats: false))
        let epoch = lifecycle.epoch
        let adding = Task { @MainActor in
            try await lifecycle.add(request, scheduledAtEpoch: epoch)
        }
        await requests.waitForAddStart()
        lifecycle.cancelAll()
        requests.pending.insert("new-family-request")
        requests.delivered.insert("new-family-request")
        // Model OS acceptance arriving after the remove-all request.
        requests.releaseAdd()
        do {
            try await adding.value
            XCTFail("the erased generation was reported as scheduled")
        } catch is CancellationError { }
        catch { XCTFail("unexpected error: \(error)") }

        XCTAssertEqual(requests.pending, Set(["new-family-request"]))
        XCTAssertEqual(requests.delivered, Set(["new-family-request"]))
        XCTAssertEqual(requests.removedPending, [request.identifier])
        XCTAssertEqual(requests.removedDelivered, [request.identifier])
        XCTAssertEqual(requests.removeAllPendingCalls, 1)
        XCTAssertEqual(requests.removeAllDeliveredCalls, 1)
    }

    func testEraseDuringWriterOrAuthorizationAwaitPreventsTheLaterAddEntirely() async throws {
        let requests = FakeFeedNotificationRequests()
        let lifecycle = FeedNotificationLifecycle(requests: requests)
        let epochBeforeAuthorization = lifecycle.epoch
        lifecycle.cancelAll()
        let request = UNNotificationRequest(identifier: UUID().uuidString,
            content: UNMutableNotificationContent(), trigger: nil)
        do {
            try await lifecycle.add(request, scheduledAtEpoch: epochBeforeAuthorization)
            XCTFail("a stale scheduling attempt reached the OS")
        } catch is CancellationError { }
        catch { XCTFail("unexpected error: \(error)") }
        XCTAssertEqual(requests.addCalls, 0)
    }
}

@MainActor
private final class FakeFeedNotificationRequests: FeedNotificationRequests {
    var pending: Set<String> = []
    var delivered: Set<String> = []
    var holdAdd = false
    var addCalls = 0
    var removeAllPendingCalls = 0
    var removeAllDeliveredCalls = 0
    var removedPending: [String] = []
    var removedDelivered: [String] = []
    private var addStarted = false
    private var addWaiter: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func add(_ request: UNNotificationRequest) async throws {
        addCalls += 1
        addStarted = true
        startWaiter?.resume(); startWaiter = nil
        if holdAdd { await withCheckedContinuation { addWaiter = $0 } }
        pending.insert(request.identifier)
        delivered.insert(request.identifier)
    }
    func waitForAddStart() async {
        if addStarted { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func releaseAdd() { addWaiter?.resume(); addWaiter = nil }
    func removePending(_ identifiers: [String]) {
        removedPending += identifiers
        pending.subtract(identifiers)
    }
    func removeDelivered(_ identifiers: [String]) {
        removedDelivered += identifiers
        delivered.subtract(identifiers)
    }
    func removeAllPending() { removeAllPendingCalls += 1; pending.removeAll() }
    func removeAllDelivered() { removeAllDeliveredCalls += 1; delivered.removeAll() }
}
