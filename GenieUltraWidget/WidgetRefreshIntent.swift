import AppIntents
import WidgetKit

/// Invoked by the refresh button in the widget. Triggers the timeline provider
/// to run again so it can read the latest data from the App Group cache.
struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Wait Times"
    static var description = IntentDescription("Updates the widget with the latest cached wait times.")

    func perform() async throws -> some IntentResult {
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
