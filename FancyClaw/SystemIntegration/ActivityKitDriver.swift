import ActivityKit
import Foundation
import os
import SystemIntegration
import SystemActions

final class ActivityKitDriver: RunActivityDriver {
    // ActivityKit's Activity isn't Sendable in this SDK. Retain only identifiers on the main actor.
    private var activityIDs: [String: String] = [:]
    private let logger = Logger(subsystem: "com.zacisnotacompany.fancyclaw", category: "LiveActivity")

    func publish(_ run: RunActivityTracker.Run) async {
        let id = run.attributes.runID
        let content = ActivityContent(state: run.state, staleDate: run.state.status == .reconnecting ? .now : .now.addingTimeInterval(60))
        if run.state.status.isTerminal {
            guard let activityID = activityIDs.removeValue(forKey: id) else { return }
            await Self.update(activityID: activityID, content: content, end: true)
        } else if let activityID = activityIDs[id] {
            await Self.update(activityID: activityID, content: content, end: false)
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            do {
                activityIDs[id] = try Activity.request(attributes: run.attributes, content: content, pushType: nil).id
            } catch {
                logger.notice("Couldn’t start Live Activity: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func endAll() async {
        let ids = Set(activityIDs.values)
        activityIDs.removeAll()
        await Self.endActivities(ids: ids)
    }

    func endOrphanedActivities() async {
        await Self.endActivities(ids: nil)
    }

    @concurrent private static func update(activityID: String, content: ActivityContent<RunActivityAttributes.ContentState>, end: Bool) async {
        guard let activity = Activity<RunActivityAttributes>.activities.first(where: { $0.id == activityID }) else { return }
        if end { await activity.end(content, dismissalPolicy: .default) }
        else { await activity.update(content) }
    }

    @concurrent private static func endActivities(ids: Set<String>?) async {
        for activity in Activity<RunActivityAttributes>.activities where ids == nil || ids?.contains(activity.id) == true {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
