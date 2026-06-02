import Foundation

enum BudgetCategory: String, CaseIterable, Codable {
    case food = "식비"
    case coffee = "카페"
    case transport = "교통"
    case shopping = "쇼핑"
    case entertainment = "여가"
    case health = "의료/건강"
    case subscription = "구독"
    case utility = "공과금"
    case salary = "급여"
    case investmentIncome = "투자수입"
    case other = "기타"

    var icon: String {
        switch self {
        case .food: return "fork.knife"
        case .coffee: return "cup.and.saucer.fill"
        case .transport: return "bus.fill"
        case .shopping: return "bag.fill"
        case .entertainment: return "gamecontroller.fill"
        case .health: return "cross.fill"
        case .subscription: return "repeat"
        case .utility: return "bolt.fill"
        case .salary: return "briefcase.fill"
        case .investmentIncome: return "chart.line.uptrend.xyaxis"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

enum GoalCategory: String, CaseIterable, Codable {
    case savings = "저축"
    case fitness = "운동"
    case learning = "학습"
    case reading = "독서"
    case faith = "신앙"
    case other = "기타"

    var icon: String {
        switch self {
        case .savings: return "banknote.fill"
        case .fitness: return "figure.run"
        case .learning: return "brain.head.profile"
        case .reading: return "book.fill"
        case .faith: return "heart.fill"
        case .other: return "star.fill"
        }
    }
}

enum EntryType: String, Codable {
    case expense = "expense"
    case income = "income"
}
