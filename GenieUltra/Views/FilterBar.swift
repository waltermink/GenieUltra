import SwiftUI

enum SortOption: String, CaseIterable {
    case waitTime = "Wait Time"
    case name = "Name"
}

enum FilterOption: String, CaseIterable {
    case all = "All"
    case operating = "Operating"
    case lightningLane = "LL Available"
}

enum ShowFilterOption: String, CaseIterable {
    case todayScheduled = "Today's Shows"
    case all = "All Shows"
}
