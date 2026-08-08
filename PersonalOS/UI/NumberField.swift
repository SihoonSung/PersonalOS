import SwiftUI

// MARK: - 숫자 입력
//
// 소숫점이 안 찍히던 버그가 살던 자리.
//
// 원래 방식은 TextField가 매 글자마다 모델의 Double을 다시 문자열로 만들어
// 되돌려주는 왕복 바인딩이었다. "12" 뒤에 "."을 누르면
//
//     "12."  →  Double("12.") = 12.0  →  다시 그리기  →  "12"
//
// 가 되어 점이 영영 남지 않는다. `TextField(value:format:)` 를 쓴 곳도
// 포맷터가 같은 왕복을 하기 때문에 똑같이 막힌다.
//
// 그래서 규칙을 뒤집는다: **편집 중에는 화면의 문자열이 진실이고**, 모델에는
// 완성된 숫자일 때만 흘려보낸다. 모델이 밖에서 바뀌면(노션 pull 등) 포커스가
// 없을 때만 다시 읽어온다 — 타이핑 중인 사람과 싸우지 않기 위해서다.
//
// **되돌리지 말 것**: `Binding<String>`의 get에서 모델 값을 포맷하는 형태로
// 돌아가면 소숫점 버그가 그대로 재발한다.

enum NumberText {

    /// 타이핑 중간 상태를 살려두는 정리기.
    ///
    /// "12." 나 "-" 처럼 아직 숫자가 아닌 것도 **문자열 그대로 남긴다**.
    /// 여기서 Double로 접었다 펴는 순간 소숫점이 사라진다.
    static func clean(
        _ raw: String,
        allowsNegative: Bool = true,
        allowsDecimal: Bool = true
    ) -> String {
        var out = ""
        var seenSeparator = false
        for ch in raw {
            if ch.isNumber {
                out.append(ch)
            } else if allowsDecimal, ch == "." || ch == ",", !seenSeparator {
                // 일부 로케일의 숫자 키패드는 쉼표를 찍는다 — 점으로 통일.
                seenSeparator = true
                out.append(".")
            } else if allowsNegative, ch == "-", out.isEmpty {
                out.append("-")
            }
        }
        return out
    }

    /// 완성된 숫자일 때만 값을 준다. "12." · "-" · "" 는 nil.
    static func value(_ text: String) -> Double? {
        Double(clean(text))
    }

    /// 모델 → 편집용 문자열.
    /// 자리 구분 쉼표와 지수 표기를 빼야 다시 파싱할 수 있다.
    static func display(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(
            .number
                .precision(.fractionLength(0...6))
                .grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX"))
        )
    }
}

/// 앱 전체에서 쓰는 숫자 입력 칸. 숫자 TextField는 전부 이걸 쓴다.
struct PosNumberField: View {
    let placeholder: String
    /// 모델의 현재 값. 편집 중에는 무시된다.
    let value: Double?
    var allowsDecimal: Bool = true
    var allowsNegative: Bool = false
    var alignment: TextAlignment = .trailing
    /// 완성된 숫자이거나 비었을 때만 불린다. "12." 같은 중간 상태는 안 보낸다.
    let onChange: (Double?) -> Void

    @State private var text = ""
    @State private var loaded = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .multilineTextAlignment(alignment)
            .focused($focused)
            .monospacedDigit()
            #if os(iOS)
            .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
            #endif
            .onAppear {
                guard !loaded else { return }
                loaded = true
                text = NumberText.display(value)
            }
            .onChange(of: text) { _, new in
                let cleaned = NumberText.clean(
                    new,
                    allowsNegative: allowsNegative,
                    allowsDecimal: allowsDecimal
                )
                // 정리된 게 다르면 되쓰기만 하고 빠진다.
                // 그 대입이 onChange를 한 번 더 돌려 아래 분기로 들어온다.
                guard cleaned == new else {
                    text = cleaned
                    return
                }
                if cleaned.isEmpty {
                    onChange(nil)
                } else if let parsed = NumberText.value(cleaned) {
                    onChange(parsed)
                }
                // "12." · "-" 는 여기서 멈춘다 — 모델을 건드리면 점이 지워진다.
            }
            .onChange(of: value) { _, new in
                // 밖에서 바뀐 값만 반영한다.
                guard !focused else { return }
                let shown = NumberText.display(new)
                if shown != text { text = shown }
            }
    }
}
