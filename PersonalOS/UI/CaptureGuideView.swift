import SwiftUI

// MARK: - 스크린샷 기록 사용법
//
// 공유 시트에 뜨게 하려면 사용자가 단축어를 한 번 만들어야 한다.
// App Intent 자체는 공유 메뉴에 안 나오고, 그걸 감싼 단축어가 나온다.
// (Share Extension이면 설정이 필요 없지만 새 타겟이 필요하다 —
//  CaptureIntent.swift 위쪽에 이유를 적어뒀다.)

struct CaptureGuideView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Step: Identifiable {
        let id = UUID()
        let number: Int
        let text: String
        let detail: String?
    }

    /// 실제로 쓸 때 하는 것. 준비가 끝난 뒤의 흐름이라 맨 위에 둔다.
    private let usage: [Step] = [
        .init(number: 1, text: "송금 완료 화면에서 스크린샷을 찍는다",
              detail: "전원 + 볼륨업"),
        .init(number: 2, text: "왼쪽 아래 뜬 미리보기를 탭한다", detail: nil),
        .init(number: 3, text: "오른쪽 위 공유 버튼 → \"가계부에 기록\"", detail: nil),
        .init(number: 4, text: "금액·받는 사람은 채워져 있으니 왜 보냈는지만 쓰고 저장",
              detail: nil),
    ]

    private let setup: [Step] = [
        .init(number: 1, text: "단축어 앱에서 새 단축어를 만든다", detail: nil),
        .init(number: 2, text: "\"스크린샷으로 가계부에 기록\" 액션을 넣는다",
              detail: "검색창에 PersonalOS를 치면 나와요"),
        .init(number: 3, text: "단축어 세부사항에서 \"공유 시트에 표시\"를 켠다",
              detail: "받는 항목은 이미지만 남겨두면 깔끔해요"),
        .init(number: 4, text: "이름을 \"가계부에 기록\" 으로 바꾼다",
              detail: "공유 메뉴에 이 이름으로 뜹니다"),
    ]

    private let backTap: [Step] = [
        .init(number: 1, text: "단축어를 하나 더 만들고 \"스크린샷 찍기\"를 먼저 넣는다", detail: nil),
        .init(number: 2, text: "그 아래에 \"스크린샷으로 가계부에 기록\"을 잇는다", detail: nil),
        .init(number: 3, text: "설정 → 손쉬운 사용 → 터치 → 뒷면 탭에서 이 단축어를 고른다",
              detail: "송금 완료 화면에서 폰 뒷면을 두 번 톡톡 치면 스크린샷부터 저장 화면까지 한 번에 가요"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.spacingL) {
                    GlassSection(
                        "쓸 때",
                        footnote: "금액·받는 사람·날짜는 화면에서 읽어요. 화면에 안 적혀 있는 건 \"왜 보냈는지\" 하나뿐이라 그것만 쓰면 됩니다."
                    ) {
                        stepList(usage)
                    }

                    GlassSection("준비 — 공유 메뉴에 올리기",
                                 footnote: "한 번만 하면 됩니다. 앱 자체는 공유 메뉴에 못 올라가고, 앱을 감싼 단축어가 올라가요.") {
                        stepList(setup)
                    }

                    GlassSection(
                        "더 빠르게 — 뒷면 탭",
                        footnote: "스크린샷을 찍고 공유를 누르는 두 단계까지 없앨 수 있어요."
                    ) {
                        stepList(backTap)
                    }

                    if let url = URL(string: "shortcuts://") {
                        Link(destination: url) {
                            Label("단축어 앱 열기", systemImage: "arrow.up.forward.app")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    GlassSection(
                        "왜 이렇게 하나",
                        footnote: "Chase는 Zelle로 받은 돈은 메일을 보내지만, 보낸 돈은 안 보내요. 계좌 이체 알림은 이미 최소 금액($1)으로 켜져 있는데도 Zelle 송금은 그 알림 대상이 아니라서, 메일로는 영영 잡을 수 없어요. 그래서 화면을 직접 읽습니다."
                    ) {
                        Text("송금 확인 화면은 어차피 한 번 보게 되니까, 그때 스크린샷 한 장이면 기록이 끝나요.")
                            .font(Theme.body())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }

                    GlassSection(
                        "Zelle 말고도",
                        footnote: "읽는 방식이 특정 은행 화면에 묶여 있지 않아서, 글자만 보이면 대체로 읽어요. 잘못 읽으면 저장 전에 고치면 됩니다."
                    ) {
                        Text("Venmo · Cash App · 토스 · 종이 영수증 사진도 같은 방법으로 들어와요.")
                            .font(Theme.body())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }

                    Spacer(minLength: Theme.spacingXL)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacingM)
            }
            .posScreen()
            .navigationTitle("스크린샷으로 기록")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private func stepList(_ steps: [Step]) -> some View {
        ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
            if index > 0 { PosDivider() }
            HStack(alignment: .top, spacing: Theme.spacingS) {
                Text("\(step.number)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.08), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.text)
                        .font(Theme.body())
                        .fixedSize(horizontal: false, vertical: true)
                    if let detail = step.detail {
                        Text(detail)
                            .font(Theme.caption2())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        }
    }
}
