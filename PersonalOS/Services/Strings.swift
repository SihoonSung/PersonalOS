import Foundation

enum AppLanguage {
    case korean
    case english
}

// MARK: - Localized String Lookup

struct L {
    // 앱 실행 중 언어는 바뀌지 않으므로 한 번만 계산
    nonisolated static let lang: AppLanguage = {
        let preferred = Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier
        return preferred.lowercased().hasPrefix("ko") ? .korean : .english
    }()

    nonisolated static let locale: Locale = {
        Locale(identifier: Locale.preferredLanguages.first ?? Locale.autoupdatingCurrent.identifier)
    }()

    private static func s(_ ko: String, _ en: String) -> String {
        lang == .korean ? ko : en
    }

    // MARK: - Tabs
    static var tabHome:     String { s("홈", "Home") }
    static var tabTasks:    String { s("할 일", "Tasks") }
    static var tabBudget:   String { s("가계부", "Budget") }
    static var tabSettings: String { s("설정", "Settings") }

    // MARK: - Dashboard
    static var greetingMorning:   String { s("좋은 아침이에요", "Good morning") }
    static var greetingAfternoon: String { s("좋은 오후예요", "Good afternoon") }
    static var greetingEvening:   String { s("좋은 저녁이에요", "Good evening") }
    static var greetingNight:     String { s("늦은 시간이네요", "Late night") }
    static var focusNow:          String { s("지금 집중할 일", "Focus Now") }

    // MARK: - Glass Dashboard
    static var dashTodayTitle:  String { s("오늘", "Today") }
    static func dashDoneCount(_ done: Int, _ total: Int) -> String { s("\(done)/\(total) 완료", "\(done)/\(total) done") }
    static var dashAllClear:    String { s("오늘 할 일을 모두 끝냈어요", "All done for today") }
    static var dashNoTasks:     String { s("오늘은 등록된 할 일이 없어요", "Nothing scheduled today") }
    static func dashMoreTasks(_ n: Int) -> String { s("외 \(n)개", "+\(n) more") }
    static var dashBudgetTitle: String { s("예산", "Budget") }
    static func dashBudgetUsed(_ pct: Int) -> String { s("\(pct)% 사용", "\(pct)% used") }
    static func dashBudgetOver(_ amount: String) -> String { s("\(amount) 초과", "\(amount) over") }
    static var dashTodaySpent:  String { s("오늘 지출", "Spent today") }
    static var dashMonthSpent:  String { s("이번 달 지출", "Spent this month") }
    static func dashWeekSpent(_ amount: String) -> String { s("이번 주 \(amount)", "This week \(amount)") }
    static var overdueBadge:      String { s("연체", "Overdue") }

    // MARK: - Task Summary Card
    static var taskSummaryLabel:  String { s("할 일", "Tasks") }
    static var taskToday:         String { s("오늘", "Today") }
    static var taskOverdue:       String { s("연체", "Overdue") }
    static func taskRemaining(_ n: Int) -> String { s("\(n)개 남음", "\(n) left") }

    // MARK: - Budget Summary Card
    static var budgetMonthlyTitle:    String { s("이번 달 가계부", "This Month") }
    static var budgetExpense:         String { s("지출", "Spent") }
    static var budgetIncome:          String { s("수입", "Income") }
    static var budgetNet:             String { s("순", "Net") }
    static var budgetCarryover:       String { s("이월", "Carryover") }
    static var budgetTotalBalance:    String { s("총 보유", "Total Balance") }
    static var budgetTodayExpense:    String { s("오늘 지출", "Today's Spend") }
    static var budgetOtherCurrency:   String { s("+ 다른 통화 항목 있음", "+ Other currency entries") }
    static func budgetProgressPct(_ n: Int) -> String { s("예산 \(n)% 사용", "\(n)% of budget used") }
    static func budgetOverBy(_ s_: String) -> String { s("예산 \(s_) 초과", "\(s_) over budget") }

    // MARK: - Calendar Card
    static var calendarTitle:        String { s("오늘 일정", "Today's Events") }
    static var calendarEmpty:        String { s("오늘 일정이 없어요", "No events today") }
    static var calendarPermission:   String { s("캘린더 접근 권한이 필요합니다", "Calendar access required") }
    static var calendarConnect:      String { s("캘린더 연동하기", "Connect Calendar") }
    static var calendarSettings:     String { s("설정", "Settings") }
    static var calendarAllDay:       String { s("종일", "All Day") }
    static var calendarNoTitle:      String { s("제목 없음", "No Title") }
    static var calendarWriteOnly:    String {
        s("캘린더 쓰기 권한만 허용되어 오늘 일정은 표시할 수 없어요.",
          "Only calendar write access is allowed, so today's events can't be shown.")
    }
    static func calendarMore(_ n: Int) -> String { s("+ \(n)개 더", "+ \(n) more") }

    // MARK: - Quick Add Bar
    static var quickAddPlaceholderAI:     String { s("할 일이나 지출을 입력해 보세요...", "Enter a task or expense...") }
    static var quickAddPlaceholderBudget: String { s("스타벅스 6000원...", "Starbucks $6...") }
    static var quickAddPlaceholderTodo:   String { s("할 일을 입력하세요...", "Enter a task...") }
    static var quickAddTypeTodo:          String { s("할 일", "Task") }
    static var quickAddTypeBudget:        String { s("지출/수입", "Expense/Income") }
    static var quickAddTypeLabel:         String { s("유형", "Type") }
    static var quickAddSave:              String { s("저장", "Save") }
    static func quickAddSavedTodo(_ t: String) -> String { s("'\(t)' 추가됨", "'\(t)' added") }
    static func quickAddSavedBudget(_ m: String, _ a: String) -> String { s("\(m) \(a) 기록됨", "\(m) \(a) recorded") }
    static func quickAddSavedBudgetManual(_ t: String) -> String { s("'\(t)' 가계부 추가됨 (금액 수정 필요)", "'\(t)' added to budget (edit amount)") }

    // MARK: - Tasks View
    static var tasksNavTitle:        String { s("할 일", "Tasks") }
    static var tasksFilterActive:    String { s("미완료", "Active") }
    static var tasksFilterToday:     String { s("오늘", "Today") }
    static var tasksFilterOverdue:   String { s("연체", "Overdue") }
    static var tasksFilterDone:      String { s("완료", "Done") }
    static var tasksFilterLabel:     String { s("필터", "Filter") }
    static var tasksSwipeDelete:     String { s("삭제", "Delete") }
    static var tasksSwipeComplete:   String { s("완료", "Complete") }
    static var tasksSwipeUncomplete: String { s("미완료로", "Undo") }
    static var tasksAddButton:       String { s("할 일 추가", "Add Task") }
    static var tasksRepeat:          String { s("반복", "Repeat") }

    static func tasksEmptyMessage(_ filter: String) -> String {
        switch (lang, filter) {
        case (.korean, "미완료"): return "할 일이 없어요"
        case (.korean, "오늘"):   return "오늘 할 일이 없어요"
        case (.korean, "연체"):   return "연체된 할 일이 없어요"
        case (.korean, "완료"):   return "완료된 할 일이 없어요"
        case (.english, "Active"):   return "No active tasks"
        case (.english, "Today"):    return "No tasks due today"
        case (.english, "Overdue"):  return "No overdue tasks"
        case (.english, "Done"):     return "No completed tasks"
        default: return lang == .korean ? "할 일이 없어요" : "No tasks"
        }
    }
    static var tasksEmptyInstruction: String {
        s("자연어로 입력해 보세요\n예: \"내일 오후 3시 병원 예약\"",
          "Try natural language\ne.g. \"Doctor appointment tomorrow at 3pm\"")
    }

    // MARK: - Add Task Sheet
    static var addTaskNavTitle:       String { s("할 일 추가", "Add Task") }
    static var addTaskNLTitle:        String { s("자연어로 입력", "Natural Language") }
    static var addTaskNLExample:      String {
        s("예시: \"다음주 금요일까지 보고서 제출\", \"내일 오후 3시 병원 예약\"",
          "e.g. \"Submit report by next Friday\", \"Doctor at 3pm tomorrow\"")
    }
    static var addTaskAIParsing:      String { s("분석 중...", "Analyzing...") }
    static var addTaskAIAnalyze:      String { s("AI로 분석", "Analyze with AI") }
    static var addTaskParsedTitle:    String { s("파싱 결과", "Parsed Result") }
    static var addTaskManualTitle:    String { s("직접 입력", "Manual Input") }
    static var addTaskTitlePlaceholder: String { s("할 일 제목", "Task title") }
    static var addTaskDueDate:        String { s("마감일", "Due Date") }
    static var addTaskDueDateToggle:  String { s("마감일 설정", "Set Due Date") }
    static var addTaskDueDatePicker:  String { s("날짜/시간", "Date/Time") }
    static var addTaskPriority:       String { s("우선순위", "Priority") }
    static var addTaskCancel:         String { s("취소", "Cancel") }
    static var addTaskSave:           String { s("저장", "Save") }

    // MARK: - Task Detail View
    static var taskDetailNavTitle:    String { s("할 일 편집", "Edit Task") }
    static var taskDetailSection:     String { s("할 일", "Task") }
    static var taskDetailTitle:       String { s("제목", "Title") }
    static var taskDetailNotes:       String { s("메모 (선택)", "Notes (optional)") }
    static var taskDetailDueSection:  String { s("마감일", "Due Date") }
    static var taskDetailDueToggle:   String { s("마감일 설정", "Set Due Date") }
    static var taskDetailDuePicker:   String { s("마감일", "Due Date") }
    static var taskDetailPrioritySection: String { s("우선순위", "Priority") }
    static var taskDetailRepeatSection:   String { s("반복", "Repeat") }
    static var taskDetailDone:        String { s("완료", "Done") }
    static func taskDetailCompleted(_ d: String) -> String { s("완료: \(d)", "Completed: \(d)") }

    // MARK: - Priority
    static var priorityNone:   String { s("없음", "None") }
    static var priorityLow:    String { s("낮음", "Low") }
    static var priorityMedium: String { s("보통", "Medium") }
    static var priorityHigh:   String { s("높음", "High") }

    // MARK: - Repeat Rules
    static var repeatNone:    String { s("없음", "None") }
    static var repeatDaily:   String { s("매일", "Daily") }
    static var repeatWeekly:  String { s("매주", "Weekly") }
    static var repeatMonthly: String { s("매월", "Monthly") }

    static func repeatLabel(_ rule: String?) -> String {
        guard let rule else { return repeatNone }
        if rule.contains("DAILY")   { return repeatDaily }
        if rule.contains("WEEKLY")  { return repeatWeekly }
        if rule.contains("MONTHLY") { return repeatMonthly }
        return s("반복", "Repeat")
    }

    // MARK: - Budget View
    static var budgetNavTitle:     String { s("가계부", "Budget") }
    static var budgetRoutineBtn:   String { s("루틴", "Routines") }
    static var budgetOverviewTab:  String { s("개요", "Overview") }
    static var budgetRecordsTab:   String { s("기록", "Records") }
    static var budgetAnalyticsTab: String { s("분석", "Analytics") }
    static var budgetSearchPrompt: String { s("상호명, 메모, 카테고리 검색", "Search merchant, note, or category") }
    static var budgetAllTypes:     String { s("전체 유형", "All Types") }
    static var budgetAllCategories: String { s("전체 카테고리", "All Categories") }
    static var budgetAllCurrencies: String { s("전체 통화", "All Currencies") }
    static var budgetFilterExpense: String { s("지출만", "Expenses") }
    static var budgetFilterIncome:  String { s("수입만", "Income") }
    static var budgetExportCSV:     String { s("CSV 내보내기", "Export CSV") }
    static var budgetExportReady:   String { s("내보낼 파일", "Export File") }
    static var budgetExportShare:   String { s("공유하기", "Share") }
    static var budgetBudgetProgress: String { s("예산 진행률", "Budget Progress") }
    static var budgetNoBudgetSet:   String { s("월 예산을 설정하면 진행률이 표시돼요", "Set a monthly budget to see progress") }
    static var budgetRemaining:     String { s("남은 예산", "Remaining") }
    static var budgetOverAmount:    String { s("초과 금액", "Over") }
    static var budgetCategoryBreakdown: String { s("카테고리별 지출", "Spending by Category") }
    static var budgetLargestEntries: String { s("큰 지출", "Largest Expenses") }
    static var budgetNoAnalytics:   String { s("분석할 지출 기록이 없어요", "No expense entries to analyze") }
    static var budgetNoFilteredResults: String { s("조건에 맞는 기록이 없어요", "No records match these filters") }
    static var budgetEmptyTitle:   String { s("이번 달 기록이 없어요", "No entries this month") }
    static var budgetEmptyHint:    String {
        s("'스타벅스 6000원' 형태로 입력해 보세요", "Try 'Starbucks $6' to add an entry")
    }
    static var budgetAddBtn:       String { s("기록 추가", "Add Entry") }
    static func budgetRecordsCount(_ n: Int) -> String { s("\(n)개 기록", "\(n) records") }
    static func budgetPercentUsed(_ n: Int) -> String { s("\(n)% 사용", "\(n)% used") }
    static func budgetCategoryShare(_ amount: String, _ percent: Int) -> String {
        s("\(amount) · \(percent)%", "\(amount) · \(percent)%")
    }

    // MARK: - Add Budget Sheet
    static var addBudgetNavTitle:     String { s("지출/수입 추가", "Add Entry") }
    static var addBudgetNLTitle:      String { s("자연어로 입력", "Natural Language") }
    static var addBudgetNLExample:    String {
        s("예시: \"스타벅스 6000원\", \"어제 택시 12000원\", \"월급 280만원\"",
          "e.g. \"Starbucks $6\", \"Taxi yesterday $12\", \"Salary $2800\"")
    }
    static var addBudgetAIParsing:    String { s("분석 중...", "Analyzing...") }
    static var addBudgetAIAnalyze:    String { s("AI로 분석", "Analyze with AI") }
    static var addBudgetParsedTitle:  String { s("파싱 결과", "Parsed Result") }
    static var addBudgetType:         String { s("유형", "Type") }
    static var addBudgetExpense:      String { s("지출", "Expense") }
    static var addBudgetIncome:       String { s("수입", "Income") }
    static var addBudgetContentSection: String { s("내용", "Details") }
    static var addBudgetMerchant:     String { s("상호명 / 내용", "Merchant / Description") }
    static var addBudgetAmount:       String { s("금액", "Amount") }
    static var addBudgetAmountZero:   String { s("0", "0") }
    static var addBudgetCategory:     String { s("카테고리", "Category") }
    static var addBudgetDateMemo:     String { s("날짜 / 메모", "Date / Note") }
    static var addBudgetDate:         String { s("날짜", "Date") }
    static var addBudgetNote:         String { s("메모 (선택)", "Note (optional)") }
    static var addBudgetCancel:       String { s("취소", "Cancel") }
    static var addBudgetSave:         String { s("저장", "Save") }

    // MARK: - Budget Detail View
    static var budgetDetailNavTitle:  String { s("편집", "Edit") }
    static var budgetDetailDone:      String { s("완료", "Done") }
    static var budgetDetailType:      String { s("유형", "Type") }
    static var budgetDetailContent:   String { s("내용", "Details") }
    static var budgetDetailMerchant:  String { s("상호명", "Merchant") }
    static var budgetDetailAmount:    String { s("금액", "Amount") }
    static var budgetDetailCategory:  String { s("카테고리", "Category") }
    static var budgetDetailDateMemo:  String { s("날짜 / 메모", "Date / Note") }
    static var budgetDetailDate:      String { s("날짜", "Date") }
    static var budgetDetailNote:      String { s("메모", "Note") }

    // MARK: - Recurring View
    static var recurringNavTitle:     String { s("루틴", "Routines") }
    static var recurringSwipeDelete:  String { s("삭제", "Delete") }
    static var recurringSwipeDisable: String { s("비활성화", "Disable") }
    static var recurringSwipeEnable:  String { s("활성화", "Enable") }
    static var recurringEmptyTitle:   String { s("루틴이 없어요", "No Routines") }
    static var recurringEmptyHint:    String {
        s("월급, 넷플릭스 등 매달 반복되는\n수입과 지출을 등록해 보세요",
          "Add recurring income and expenses\nlike salary or Netflix")
    }
    static var recurringAddBtn:       String { s("루틴 추가", "Add Routine") }
    static var recurringInactiveBadge: String { s("비활성", "Inactive") }
    static func recurringDayOfMonth(_ d: Int) -> String { s("매월 \(d)일", "Every month on day \(d)") }
    static var recurringExpense:      String { s("지출", "Expense") }
    static var recurringIncome:       String { s("수입", "Income") }
    static var recurringAutoNote:     String { s("루틴 자동 추가", "Auto-added by routine") }

    // MARK: - Add Recurring Sheet
    static var addRecurringNew:       String { s("루틴 추가", "Add Routine") }
    static var addRecurringEdit:      String { s("루틴 편집", "Edit Routine") }
    static var addRecurringBasic:     String { s("기본 정보", "Basic Info") }
    static var addRecurringNamePlaceholder: String { s("이름 (예: 넷플릭스, 월급)", "Name (e.g. Netflix, Salary)") }
    static var addRecurringType:      String { s("유형", "Type") }
    static var addRecurringAmount:    String { s("금액", "Amount") }
    static var addRecurringAmountPlaceholder: String { s("금액", "Amount") }
    static var addRecurringCategory:  String { s("카테고리", "Category") }
    static var addRecurringRepeat:    String { s("반복 설정", "Repeat Settings") }
    static var addRecurringActive:    String { s("활성화", "Active") }
    static var addRecurringCancel:    String { s("취소", "Cancel") }
    static var addRecurringSave:      String { s("저장", "Save") }

    // MARK: - Settings View
    static var settingsNavTitle:      String { s("설정", "Settings") }
    static var settingsPersonalSection: String { s("내 정보", "Personal") }
    static var settingsPreferencesSection: String { s("직접 설정", "Preferences") }
    static var settingsIntegrationsSection: String { s("연동", "Integrations") }
    static var settingsProfile:       String { s("프로필", "Profile") }
    static var settingsProfileEmpty:  String { s("이름 없음", "No name") }
    static var settingsNamePlaceholder: String { s("이름 입력", "Enter name") }
    static var settingsAISection:     String { s("Apple Intelligence", "Apple Intelligence") }
    static var settingsAIFooter:      String {
        s("자연어 입력 파싱과 AI 비서 기능에 사용됩니다. 모든 처리는 이 기기 안에서만 이루어지며 외부 서버로 데이터가 전송되지 않습니다.",
          "Used for natural language parsing and AI assistant. All processing happens on this device — no data is sent to external servers.")
    }
    static var settingsBudgetSection: String { s("예산", "Budget") }
    static var settingsBudgetLabel:   String { s("월 지출 예산", "Monthly Budget") }
    static var settingsBudgetPlaceholder: String { s("설정 안 함", "Not set") }
    static var settingsBudgetReset:   String { s("예산 초기화", "Clear Budget") }
    static var settingsBudgetNotSet:  String { s("설정 안 함", "Not set") }
    static var settingsBudgetFooter:  String {
        s("설정하면 대시보드에 이번 달 예산 진행률이 표시됩니다.",
          "When set, your monthly budget progress will be shown on the dashboard.")
    }
    static var settingsBudgetAlert: String { s("예산 초과 알림", "Budget Alerts") }
    static var settingsBudgetAlertFooter: String {
        s("기본 통화 기준 월 지출이 예산을 넘으면 한 달에 한 번 알림을 보냅니다.",
          "Sends one alert per month when spending in your default currency exceeds the budget.")
    }
    static var settingsCurrencySection: String { s("기본 통화", "Default Currency") }
    static var settingsCurrencyFooter: String {
        s("자연어 입력 시 통화를 명시하지 않으면 기본 통화로 저장됩니다.\n'달러', '$' 입력 시 USD, '원', '₩' 입력 시 KRW로 자동 인식됩니다.",
          "If no currency is specified in natural language input, the default currency is used.\n'Dollar', '$' → USD, '원', '₩' → KRW.")
    }
    static var currencyKRWLabel: String { s("원화 (₩ KRW)", "Korean won (₩ KRW)") }
    static var currencyUSDLabel: String { s("달러 ($ USD)", "US dollar ($ USD)") }
    static var settingsLanguageManaged: String {
        s("앱 언어는 iOS 앱별 언어 설정을 따릅니다.", "App language follows the iOS per-app language setting.")
    }
    static var settingsAppInfo:       String { s("앱 정보", "App Info") }
    static var settingsVersion:       String { s("버전", "Version") }
    static var settingsStockData:     String { s("주가 데이터", "Stock Data") }
    static var settingsDisclaimer:    String {
        s("주가 데이터는 Yahoo Finance 비공식 API를 사용합니다. 실시간 데이터가 아닐 수 있으며 투자 결정에 사용하지 마세요.",
          "Stock data uses Yahoo Finance's unofficial API. Data may be delayed. Do not use for investment decisions.")
    }

    // MARK: - AI Status
    static var aiStatusAvailable:    String { s("사용 가능", "Available") }
    static var aiStatusUnavailable:  String { s("사용 불가", "Unavailable") }
    static var aiStatusLabel:        String { s("온디바이스 AI", "On-Device AI") }
    static var aiStatusOpenSettings: String { s("Apple Intelligence 설정 열기", "Open Apple Intelligence Settings") }

    static var aiReasonDeviceNotEligible: String {
        s("이 기기는 Apple Intelligence를 지원하지 않습니다.", "This device does not support Apple Intelligence.")
    }
    static var aiReasonNotEnabled: String {
        s("Apple Intelligence가 꺼져 있습니다. 설정에서 켜주세요.", "Apple Intelligence is turned off. Enable it in Settings.")
    }
    static var aiReasonModelNotReady: String {
        s("AI 모델을 다운로드하는 중입니다. 잠시 후 다시 시도해주세요.", "The AI model is downloading. Please try again later.")
    }
    static var aiReasonUnavailable: String {
        s("AI 기능을 사용할 수 없습니다.", "AI features are unavailable.")
    }

    // MARK: - Calendar Sync Settings
    static var calendarSyncConnected: String { s("연동됨", "Connected") }
    static var calendarSyncDisconnected: String { s("연동 안 됨", "Not Connected") }
    static var calendarSyncTitle: String { s("캘린더 연동", "Calendar Sync") }
    static var calendarSyncAllow: String { s("캘린더 접근 허용", "Allow Calendar Access") }
    static var calendarSyncDescription: String {
        s("마감일이 있는 할 일을 추가/수정/삭제하면 캘린더에 자동으로 반영됩니다.",
          "Tasks with due dates are automatically synced to your calendar.")
    }

    // MARK: - Notifications
    static var notificationDueSoon: String { s("마감 임박", "Due Soon") }
    static var budgetAlertTitle: String { s("예산을 초과했어요", "Budget Exceeded") }
    static func budgetAlertBody(_ over: String, _ spend: String, _ budget: String) -> String {
        s("이번 달 지출이 예산보다 \(over) 많아요. 현재 \(spend) / 예산 \(budget)",
          "This month's spending is \(over) over budget. Current \(spend) / budget \(budget)")
    }
    static var calendarCompletedNote: String { s("✓ PersonalOS에서 완료됨", "✓ Completed in PersonalOS") }

    // MARK: - AI Unavailable Banner
    static var aiBannerSettings:     String { s("설정", "Settings") }

    // MARK: - Parsed Preview Chips
    static var chipUnknownMerchant:  String { s("알 수 없음", "Unknown") }

    // MARK: - Budget Categories (for display)
    static var catFood:         String { s("식비", "Food") }
    static var catCoffee:       String { s("카페", "Café") }
    static var catTransport:    String { s("교통", "Transport") }
    static var catShopping:     String { s("쇼핑", "Shopping") }
    static var catEntertainment: String { s("여가", "Entertainment") }
    static var catHealth:       String { s("의료/건강", "Health") }
    static var catSubscription: String { s("구독", "Subscription") }
    static var catUtility:      String { s("공과금", "Utilities") }
    static var catSalary:       String { s("급여", "Salary") }
    static var catInvestment:   String { s("투자수입", "Investment") }
    static var catOther:        String { s("기타", "Other") }

    // MARK: - Goal Categories
    static var goalSavings:     String { s("저축", "Savings") }
    static var goalFitness:     String { s("운동", "Fitness") }
    static var goalLearning:    String { s("학습", "Learning") }
    static var goalReading:     String { s("독서", "Reading") }
    static var goalFaith:       String { s("신앙", "Faith") }
    static var goalOther:       String { s("기타", "Other") }

    // MARK: - Goals View
    static var goalsSegment:        String { s("목표", "Goals") }
    static var goalsNavTitle:        String { s("목표", "Goals") }
    static var goalsAddButton:       String { s("목표 추가", "Add Goal") }
    static var goalsEmptyTitle:      String { s("목표가 없어요", "No goals yet") }
    static var goalsEmptyHint:       String { s("운동, 저축, 독서 등 달성하고 싶은 목표를 추가해 보세요", "Add fitness, savings, reading goals and more") }
    static var goalsFilterAll:       String { s("전체", "All") }
    static var goalsFilterActive:    String { s("진행 중", "Active") }
    static var goalsFilterDone:      String { s("완료", "Done") }
    static var goalsSwipeDelete:     String { s("삭제", "Delete") }
    static var goalsProgressLabel:   String { s("진행률", "Progress") }

    // MARK: - Add / Edit Goal Sheet
    static var addGoalNavTitle:      String { s("목표 추가", "Add Goal") }
    static var editGoalNavTitle:     String { s("목표 편집", "Edit Goal") }
    static var addGoalTitlePlaceholder: String { s("목표 제목", "Goal title") }
    static var addGoalCategory:      String { s("카테고리", "Category") }
    static var addGoalTarget:        String { s("목표값", "Target") }
    static var addGoalCurrent:       String { s("현재값", "Current") }
    static var addGoalUnit:          String { s("단위 (예: km, 권, 만원)", "Unit (e.g. km, books, $)") }
    static var addGoalDeadline:      String { s("마감일", "Deadline") }
    static var addGoalDeadlineToggle: String { s("마감일 설정", "Set Deadline") }
    static var addGoalNotes:         String { s("메모 (선택)", "Notes (optional)") }
    static var addGoalCancel:        String { s("취소", "Cancel") }
    static var addGoalSave:          String { s("저장", "Save") }
    static var addGoalDone:          String { s("완료", "Done") }
    static var taskGoalLink:         String { s("연결된 목표", "Linked Goal") }
    static var taskGoalNone:         String { s("없음", "None") }
    static var taskGoalIncrement:    String { s("완료 시 진행도 +1", "Increment goal on complete") }
    static func goalProgressText(_ current: String, _ target: String, _ unit: String) -> String {
        unit.isEmpty ? s("\(current) / \(target)", "\(current) / \(target)")
                     : s("\(current) / \(target) \(unit)", "\(current) / \(target) \(unit)")
    }

    // MARK: - Investment View
    static var investmentSegment:    String { s("투자", "Invest") }
    static var investmentNavTitle:   String { s("투자 포트폴리오", "Portfolio") }
    static var investmentAddButton:  String { s("종목 추가", "Add Position") }
    static var investmentEmptyTitle: String { s("보유 종목이 없어요", "No positions") }
    static var investmentEmptyHint:  String { s("AAPL, TSLA 등 보유 종목을 추가해 보세요", "Add positions like AAPL, TSLA") }
    static var investmentTotalValue: String { s("평가금액", "Value") }
    static var investmentTotalCost:  String { s("투자금액", "Cost") }
    static var investmentPnL:        String { s("손익", "P&L") }
    static var investmentShares:     String { s("보유수량", "Shares") }
    static var investmentAvgCost:    String { s("평균단가", "Avg Cost") }
    static var investmentCurrentPrice: String { s("현재가", "Price") }
    static var investmentDayChange:  String { s("일간 변동", "Day Change") }
    static var investmentLoading:    String { s("시세 조회 중...", "Fetching prices...") }
    static var investmentRefresh:    String { s("새로고침", "Refresh") }
    static var investmentSwipeDelete: String { s("삭제", "Delete") }
    static var investmentDisclaimer: String { s("Yahoo Finance 비공식 API 사용. 투자 결정에 활용하지 마세요.", "Uses Yahoo Finance unofficial API. Not for investment decisions.") }

    // MARK: - Add Investment Sheet
    static var addInvestmentNavTitle:   String { s("종목 추가", "Add Position") }
    static var editInvestmentNavTitle:  String { s("종목 편집", "Edit Position") }
    static var addInvestmentTicker:     String { s("티커 (예: AAPL, 005930.KS)", "Ticker (e.g. AAPL, 005930.KS)") }
    static var addInvestmentName:       String { s("종목명", "Name") }
    static var addInvestmentShares:     String { s("수량", "Shares") }
    static var addInvestmentAvgCost:    String { s("평균단가", "Avg Cost") }
    static var addInvestmentCurrency:   String { s("통화", "Currency") }
    static var addInvestmentCancel:     String { s("취소", "Cancel") }
    static var addInvestmentSave:       String { s("저장", "Save") }

    // MARK: - AI Assistant
    static var aiAssistantCardTitle:    String { s("AI 비서", "AI Assistant") }
    static var aiAssistantCardHint:     String { s("탭해서 대화하기", "Tap to chat") }
    static var aiAssistantNavTitle:     String { s("AI 비서", "AI Assistant") }
    static var aiAssistantPlaceholder:  String { s("무엇이든 물어보세요...", "Ask me anything...") }
    static var aiAssistantSend:         String { s("전송", "Send") }
    static var aiAssistantThinking:     String { s("생각 중...", "Thinking...") }
    static var aiAssistantUnavailable:  String { s("AI 비서를 사용하려면 Apple Intelligence가 필요합니다.", "Apple Intelligence is required to use the AI assistant.") }
    static var aiAssistantWelcome:      String { s("안녕하세요! 할 일, 가계부, 투자, 목표에 대해 무엇이든 물어보세요.", "Hi! Ask me anything about your tasks, budget, investments, or goals.") }
    static var aiAssistantDisclaimer:   String { s(
        "Apple 온디바이스 AI로 구동됩니다. 답변 품질이 제한될 수 있어요.",
        "Powered by Apple on-device AI. Response quality may be limited."
    ) }

    // MARK: - Investment Dashboard Card
    static var investmentCardTitle:     String { s("투자", "Portfolio") }
    static var investmentCardNoData:    String { s("보유 종목 없음", "No positions") }
}
