import Foundation

// MARK: - 앱 인텐트 → 앱 본체로 넘기는 자리
//
// 인텐트는 앱을 열면서 결과를 넘겨야 하는데, 인텐트가 도는 프로세스와 화면을
// 그리는 프로세스가 항상 같다고 보장할 수 없다. 그래서 앱 그룹 컨테이너에
// 적어두고, 앱이 활성화될 때 집어간다.
//
// 스크린샷 원본도 같이 둔다 — 확인 시트에서 "이 화면을 이렇게 읽었어요"를
// 보여줘야 잘못 읽은 걸 사람이 알아챌 수 있다.

enum PendingCapture {

    private static let scanKey = "capture.pendingScan"
    private static let imageName = "capture-pending.jpg"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: WidgetShared.appGroupID) ?? .standard
    }

    private static var imageURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupID)?
            .appendingPathComponent(imageName)
    }

    static func stash(_ scan: ReceiptScan, imageData: Data?) {
        guard let encoded = try? JSONEncoder().encode(scan) else { return }
        defaults.set(encoded, forKey: scanKey)
        if let imageData, let url = imageURL {
            try? imageData.write(to: url, options: .atomic)
        }
    }

    /// 한 번만 꺼내진다 — 앱이 여러 번 활성화돼도 시트가 반복해서 뜨지 않도록.
    static func take() -> (scan: ReceiptScan, imageData: Data?)? {
        guard let data = defaults.data(forKey: scanKey),
              let scan = try? JSONDecoder().decode(ReceiptScan.self, from: data)
        else { return nil }

        defaults.removeObject(forKey: scanKey)
        var imageData: Data?
        if let url = imageURL {
            imageData = try? Data(contentsOf: url)
            try? FileManager.default.removeItem(at: url)
        }
        return (scan, imageData)
    }

    static var hasPending: Bool { defaults.data(forKey: scanKey) != nil }
}
