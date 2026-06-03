import SwiftUI
import SwiftData

struct GoalsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Goal.createdAt) private var goals: [Goal]

    @State private var showAddSheet = false
    @State private var selectedGoal: Goal?
    @State private var filter: GoalFilter = .active

    enum GoalFilter: String, CaseIterable {
        case all, active, done

        var label: String {
            switch self {
            case .all:    return L.goalsFilterAll
            case .active: return L.goalsFilterActive
            case .done:   return L.goalsFilterDone
            }
        }
    }

    private var filteredGoals: [Goal] {
        switch filter {
        case .all:    return goals
        case .active: return goals.filter { !$0.isCompleted }
        case .done:   return goals.filter { $0.isCompleted }
        }
    }

    var body: some View {
        Group {
            if goals.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    Picker(L.goalsFilterAll, selection: $filter) {
                        ForEach(GoalFilter.allCases, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(Theme.spacingM)

                    if filteredGoals.isEmpty {
                        Spacer()
                        Text(filter == .done ? L.goalsFilterDone : L.goalsFilterActive)
                            .font(Theme.body())
                            .foregroundStyle(.secondary)
                        Spacer()
                    } else {
                        List {
                            ForEach(filteredGoals) { goal in
                                GoalRowView(goal: goal)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedGoal = goal }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            context.delete(goal)
                                            try? context.save()
                                        } label: {
                                            Label(L.goalsSwipeDelete, systemImage: "trash")
                                        }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            withAnimation {
                                                goal.isCompleted.toggle()
                                                try? context.save()
                                            }
                                        } label: {
                                            Label(
                                                goal.isCompleted ? L.tasksSwipeUncomplete : L.tasksSwipeComplete,
                                                systemImage: goal.isCompleted ? "arrow.uturn.left" : "checkmark"
                                            )
                                        }
                                        .tint(goal.isCompleted ? .orange : .green)
                                    }
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus.circle.fill").font(.title3)
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddGoalSheet().presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedGoal) { goal in
            AddGoalSheet(editing: goal).presentationDetents([.medium, .large])
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.spacingM) {
            Spacer()
            Image(systemName: "target")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text(L.goalsEmptyTitle)
                .font(Theme.headline())
            Text(L.goalsEmptyHint)
                .font(Theme.body())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L.goalsAddButton) { showAddSheet = true }
                .buttonStyle(.bordered)
            Spacer()
        }
        .padding(Theme.spacingXL)
    }
}

// MARK: - 목표 행

struct GoalRowView: View {
    let goal: Goal

    private var category: GoalCategory { goal.goalCategory }

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            // 아이콘
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(goal.isCompleted ? 0.08 : 0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: category.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(goal.isCompleted ? .secondary : categoryColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(goal.title)
                        .font(Theme.body())
                        .foregroundStyle(goal.isCompleted ? .secondary : .primary)
                        .strikethrough(goal.isCompleted, color: .secondary)
                        .lineLimit(1)
                    if goal.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.caption())
                            .foregroundStyle(.green)
                    }
                }

                // 진행률 바
                if !goal.isCompleted {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.15))
                            Capsule()
                                .fill(categoryColor)
                                .frame(width: max(4, proxy.size.width * goal.progress))
                        }
                    }
                    .frame(height: 5)
                }

                // 진행 수치
                HStack(spacing: 4) {
                    Text(progressText)
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                    if let deadline = goal.deadline, !goal.isCompleted {
                        Text("·")
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                        Text(deadline.formatted(.dateTime.month(.abbreviated).day()))
                            .font(Theme.caption2())
                            .foregroundStyle(deadline < Date.now ? .red : .secondary)
                    }
                }
            }

            Spacer()

            Text("\(goal.progressPercent)%")
                .font(Theme.caption().bold())
                .foregroundStyle(goal.isCompleted ? .green : categoryColor)
                .monospacedDigit()
        }
        .padding(.vertical, Theme.spacingXS)
        .opacity(goal.isCompleted ? 0.6 : 1.0)
    }

    private var progressText: String {
        L.goalProgressText(
            formatValue(goal.currentValue),
            formatValue(goal.targetValue),
            goal.unit
        )
    }

    private func formatValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.1f", v)
    }

    private var categoryColor: Color {
        switch category {
        case .savings:  return .green
        case .fitness:  return .orange
        case .learning: return .blue
        case .reading:  return .purple
        case .faith:    return .pink
        case .other:    return .gray
        }
    }
}
