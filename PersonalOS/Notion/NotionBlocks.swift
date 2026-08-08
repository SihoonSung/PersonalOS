import Foundation

// MARK: - 노션 블록 ↔ 평문
//
// 앱은 본문을 **읽고 덧붙이기만** 한다. 기존 블록을 평문으로 되쓰면 루틴이
// 만들어 둔 표·토글·콜아웃이 전부 날아가므로, 편집은 지원하지 않는다.

/// 화면에 한 줄로 그릴 수 있게 펴 놓은 블록.
struct NotionBlockLine: Identifiable, Equatable {
    enum Kind: Equatable {
        case paragraph
        case heading(level: Int)
        case bullet
        case numbered
        case todo(checked: Bool)
        case quote
        case code
        case callout(icon: String)
        case divider
        case unsupported(String)
    }

    let id: String
    let kind: Kind
    let text: String

    /// 본문에 덧붙일 위치를 고를 때 쓸 후보인지 (제목만).
    var isSectionAnchor: Bool {
        if case .heading = kind { return true }
        return false
    }
}

enum NotionBlocks {

    // MARK: 노션 → 평문

    static func lines(from raw: [[String: Any]]) -> [NotionBlockLine] {
        raw.compactMap { line(from: $0) }
    }

    private static func line(from block: [String: Any]) -> NotionBlockLine? {
        guard let id = block["id"] as? String,
              let type = block["type"] as? String
        else { return nil }

        let payload = block[type] as? [String: Any]
        let text = NotionAPI.plainText(payload?["rich_text"])

        switch type {
        case "paragraph":
            return NotionBlockLine(id: id, kind: .paragraph, text: text)
        case "heading_1":
            return NotionBlockLine(id: id, kind: .heading(level: 1), text: text)
        case "heading_2":
            return NotionBlockLine(id: id, kind: .heading(level: 2), text: text)
        case "heading_3":
            return NotionBlockLine(id: id, kind: .heading(level: 3), text: text)
        case "bulleted_list_item":
            return NotionBlockLine(id: id, kind: .bullet, text: text)
        case "numbered_list_item":
            return NotionBlockLine(id: id, kind: .numbered, text: text)
        case "to_do":
            return NotionBlockLine(id: id, kind: .todo(checked: payload?["checked"] as? Bool ?? false), text: text)
        case "quote":
            return NotionBlockLine(id: id, kind: .quote, text: text)
        case "code":
            return NotionBlockLine(id: id, kind: .code, text: text)
        case "callout":
            let icon = ((payload?["icon"] as? [String: Any])?["emoji"] as? String) ?? "💡"
            return NotionBlockLine(id: id, kind: .callout(icon: icon), text: text)
        case "divider":
            return NotionBlockLine(id: id, kind: .divider, text: "")
        case "toggle":
            // 토글은 접힌 제목만 보여준다 (자식은 따라가지 않음).
            return NotionBlockLine(id: id, kind: .paragraph, text: text)
        default:
            // 표·이미지·임베드 등 — 자리만 표시하고 넘어간다.
            return NotionBlockLine(id: id, kind: .unsupported(type), text: text)
        }
    }

    // MARK: 평문 → 노션

    /// 빈 줄로 나눠 문단 블록을 만든다. 서식은 넣지 않는다 — 앱에서 쓴 글은
    /// 평문이라는 게 예측 가능해서 좋다.
    static func paragraphs(from text: String) -> [[String: Any]] {
        text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { line in
                [
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": [
                        "rich_text": [["type": "text", "text": ["content": line]]]
                    ],
                ]
            }
    }
}
