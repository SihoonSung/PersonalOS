import Foundation

enum BudgetCategory: String, CaseIterable, Codable {
    case food = "food"
    case coffee = "coffee"
    case transport = "transport"
    case shopping = "shopping"
    case entertainment = "entertainment"
    case health = "health"
    case subscription = "subscription"
    case utility = "utility"
    case salary = "salary"
    case investmentIncome = "investmentIncome"
    case other = "other"

    var localizedName: String {
        switch self {
        case .food:            return L.catFood
        case .coffee:          return L.catCoffee
        case .transport:       return L.catTransport
        case .shopping:        return L.catShopping
        case .entertainment:   return L.catEntertainment
        case .health:          return L.catHealth
        case .subscription:    return L.catSubscription
        case .utility:         return L.catUtility
        case .salary:          return L.catSalary
        case .investmentIncome: return L.catInvestment
        case .other:           return L.catOther
        }
    }

    // AI 파싱에서 받는 한국어/영어 문자열 → enum 변환
    static func from(_ string: String) -> BudgetCategory {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // rawValue 직접 매칭
        if let direct = BudgetCategory(rawValue: trimmed) { return direct }
        if let lowercased = BudgetCategory.allCases.first(where: { $0.rawValue.lowercased() == trimmed.lowercased() }) {
            return lowercased
        }
        // 한국어 이름 매칭
        let koMap: [String: BudgetCategory] = [
            "식비": .food, "카페": .coffee, "교통": .transport,
            "쇼핑": .shopping, "여가": .entertainment, "의료/건강": .health,
            "구독": .subscription, "공과금": .utility, "급여": .salary,
            "투자수입": .investmentIncome, "기타": .other
        ]
        if let match = koMap[trimmed] { return match }
        // 영어 이름 매칭
        let enMap: [String: BudgetCategory] = [
            "Food": .food, "Café": .coffee, "Cafe": .coffee, "Transport": .transport,
            "Shopping": .shopping, "Entertainment": .entertainment, "Health": .health,
            "Subscription": .subscription, "Utilities": .utility, "Salary": .salary,
            "Investment": .investmentIncome, "Other": .other
        ]
        if let match = enMap[trimmed] { return match }
        return .other
    }

    var icon: String {
        switch self {
        case .food:            return "fork.knife"
        case .coffee:          return "cup.and.saucer.fill"
        case .transport:       return "bus.fill"
        case .shopping:        return "bag.fill"
        case .entertainment:   return "gamecontroller.fill"
        case .health:          return "cross.fill"
        case .subscription:    return "repeat"
        case .utility:         return "bolt.fill"
        case .salary:          return "briefcase.fill"
        case .investmentIncome: return "chart.line.uptrend.xyaxis"
        case .other:           return "ellipsis.circle.fill"
        }
    }
}

enum GoalCategory: String, CaseIterable, Codable {
    case savings = "savings"
    case fitness = "fitness"
    case learning = "learning"
    case reading = "reading"
    case faith = "faith"
    case other = "other"

    var localizedName: String {
        switch self {
        case .savings:  return L.goalSavings
        case .fitness:  return L.goalFitness
        case .learning: return L.goalLearning
        case .reading:  return L.goalReading
        case .faith:    return L.goalFaith
        case .other:    return L.goalOther
        }
    }

    static func from(_ string: String) -> GoalCategory {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = GoalCategory(rawValue: trimmed) { return direct }
        if let lowercased = GoalCategory.allCases.first(where: { $0.rawValue.lowercased() == trimmed.lowercased() }) {
            return lowercased
        }

        let koMap: [String: GoalCategory] = [
            "저축": .savings, "운동": .fitness, "학습": .learning,
            "독서": .reading, "신앙": .faith, "기타": .other
        ]
        if let match = koMap[trimmed] { return match }

        let enMap: [String: GoalCategory] = [
            "Savings": .savings, "Fitness": .fitness, "Learning": .learning,
            "Reading": .reading, "Faith": .faith, "Other": .other
        ]
        if let match = enMap[trimmed] { return match }
        return .other
    }

    var icon: String {
        switch self {
        case .savings:  return "banknote.fill"
        case .fitness:  return "figure.run"
        case .learning: return "brain.head.profile"
        case .reading:  return "book.fill"
        case .faith:    return "heart.fill"
        case .other:    return "star.fill"
        }
    }
}

enum EntryType: String, Codable {
    case expense = "expense"
    case income = "income"
}

enum Priority: Int, CaseIterable, Codable {
    case none   = 0
    case low    = 1
    case medium = 2
    case high   = 3

    var label: String {
        switch self {
        case .none:   return L.priorityNone
        case .low:    return L.priorityLow
        case .medium: return L.priorityMedium
        case .high:   return L.priorityHigh
        }
    }

    var color: String {
        switch self {
        case .high:   return "red"
        case .medium: return "orange"
        case .low:    return "blue"
        case .none:   return "gray"
        }
    }
}
