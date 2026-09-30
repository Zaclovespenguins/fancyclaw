import Foundation

@MainActor public protocol RunActivityDriver: AnyObject {
    func publish(_ run: RunActivityTracker.Run) async
    func endAll() async
}
