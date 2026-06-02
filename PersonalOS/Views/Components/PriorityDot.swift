import SwiftUI

struct PriorityDot: View {
    let priority: Int

    var color: Color {
        switch priority {
        case 3: return Theme.priorityHigh
        case 2: return Theme.priorityMedium
        case 1: return Theme.priorityLow
        default: return .clear
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }
}
