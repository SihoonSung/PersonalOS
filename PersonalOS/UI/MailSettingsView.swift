import SwiftUI
import SwiftData

/// Gmail app-password setup for the 가계부 mail importer.
struct MailSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(MailSettings.addressKey) private var address = ""
    @AppStorage(MailSettings.backfillDaysKey) private var backfillDays = MailSettings.defaultBackfillDays
    @AppStorage(MailSettings.autoSyncKey) private var autoSync = true
    @AppStorage(MailSettings.notifyKey) private var notify = true
    @AppStorage(MailSettings.mailboxKey) private var mailbox = ""

    @State private var password = ""
    @State private var hasStoredPassword = false
    @State private var testing = false
    @State private var testMessage: String?
    @State private var sourceToggles: [String: Bool] = [:]

    private let sync = MailSyncService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Gmail 주소", text: $address)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    SecureField(hasStoredPassword ? "앱 비밀번호 (저장됨)" : "앱 비밀번호 16자리", text: $password)
                        .autocorrectionDisabled()
                        .onSubmit(savePassword)

                    if !password.isEmpty {
                        Button("앱 비밀번호 저장", action: savePassword)
                    }
                    if hasStoredPassword {
                        Button("저장된 비밀번호 삭제", role: .destructive) {
                            MailSettings.password = nil
                            hasStoredPassword = false
                            password = ""
                        }
                    }
                } header: {
                    Text("Gmail 연결")
                } footer: {
                    Text("""
                    일반 Gmail 비밀번호가 아니라 **앱 비밀번호**가 필요해요.
                    ① Google 계정 → 보안에서 2단계 인증을 켜고
                    ② myaccount.google.com/apppasswords 에서 새 앱 비밀번호를 만든 뒤
                    ③ 여기에 붙여넣으면 됩니다. 비밀번호는 이 기기의 Keychain에만 저장돼요.
                    """)
                }

                Section {
                    Button {
                        runTest()
                    } label: {
                        HStack {
                            Text("연결 테스트")
                            if testing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(testing || address.isEmpty || (password.isEmpty && !hasStoredPassword))

                    if let testMessage {
                        Text(testMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("가져올 메일") {
                    ForEach(MailSource.allCases) { source in
                        Toggle(isOn: binding(for: source)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayName)
                                Text(source.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Picker("처음 가져올 기간", selection: $backfillDays) {
                        Text("30일").tag(30)
                        Text("90일").tag(90)
                        Text("180일").tag(180)
                        Text("1년").tag(365)
                    }
                    Toggle("앱 열 때 자동으로 가져오기", isOn: $autoSync)
                    Toggle("새 거래 알림", isOn: $notify)
                    TextField("메일함 (비우면 자동)", text: $mailbox)
                        .autocorrectionDisabled()
                } header: {
                    Text("가져오기")
                } footer: {
                    Text("메일함을 비워두면 Gmail의 전체보관함을 자동으로 찾아서 읽어요. 메일은 읽음 표시 없이 그대로 둡니다.")
                }

                Section {
                    Button {
                        Task { await sync.syncNow(force: true) }
                    } label: {
                        HStack {
                            Text("지금 전체 다시 가져오기")
                            if sync.isSyncing {
                                Spacer()
                                Text(sync.progressText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(sync.isSyncing || !MailSettings.isConfigured)

                    if let result = sync.lastResult {
                        LabeledContent("마지막 결과", value: result.summary)
                            .font(.caption)
                    }
                    if let last = MailSettings.lastSyncAt {
                        LabeledContent("마지막 동기화", value: last.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                    }
                } footer: {
                    Text("이미 가져온 거래는 메일 고유 ID로 걸러져서 다시 가져와도 중복되지 않아요.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("메일 가계부")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        savePassword()
                        dismiss()
                    }
                }
            }
            .onAppear {
                hasStoredPassword = !(MailSettings.password ?? "").isEmpty
                sourceToggles = Dictionary(
                    uniqueKeysWithValues: MailSource.allCases.map { ($0.id, MailSettings.isEnabled($0.id)) }
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 560)
        #endif
    }

    private func binding(for source: MailSource) -> Binding<Bool> {
        Binding(
            get: { sourceToggles[source.id] ?? MailSettings.isEnabled(source.id) },
            set: { newValue in
                sourceToggles[source.id] = newValue
                MailSettings.setEnabled(newValue, for: source.id)
            }
        )
    }

    private func savePassword() {
        guard !password.isEmpty else { return }
        MailSettings.password = password.replacingOccurrences(of: " ", with: "")
        hasStoredPassword = true
        password = ""
    }

    private func runTest() {
        savePassword()
        guard let stored = MailSettings.password, !stored.isEmpty else { return }
        testing = true
        testMessage = nil
        Task {
            let message = await sync.testConnection(address: address, password: stored)
            testMessage = message
            testing = false
        }
    }
}
