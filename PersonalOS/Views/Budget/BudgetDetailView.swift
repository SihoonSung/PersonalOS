import SwiftUI

struct BudgetDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var entry: BudgetEntry

    @State private var amountText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("유형") {
                    Picker("유형", selection: $entry.type) {
                        Text("지출").tag("expense")
                        Text("수입").tag("income")
                    }
                    .pickerStyle(.segmented)
                }

                Section("내용") {
                    TextField("상호명", text: $entry.merchant)
                    HStack {
                        Text("금액")
                        Spacer()
                        TextField("금액", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: amountText) { _, v in
                                entry.amount = Double(v.filter { $0.isNumber }) ?? entry.amount
                            }
                        Text("원").foregroundStyle(.secondary)
                    }
                }

                Section("카테고리") {
                    Picker("카테고리", selection: $entry.category) {
                        ForEach(BudgetCategory.allCases, id: \.rawValue) { cat in
                            Label(cat.rawValue, systemImage: cat.icon).tag(cat.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("날짜 / 메모") {
                    DatePicker("날짜", selection: $entry.date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                    TextField("메모", text: $entry.note)
                }
            }
            .navigationTitle("편집")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { amountText = String(Int(entry.amount)) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("완료") {
                        try? context.save()
                        dismiss()
                    }
                    .bold()
                }
            }
        }
    }
}
