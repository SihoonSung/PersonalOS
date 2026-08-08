import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - 공유 시트에서 들어오는 입구
//
// 왜 Share Extension이 아니라 App Intent인가:
// Share Extension은 **새 타겟**이 필요하다. 이 프로젝트는
// PBXFileSystemSynchronizedRootGroup 방식이라 새 타겟이 자동으로 안 붙고,
// 프로비저닝 프로파일이 하나 더 생기고, Xcode Cloud 아카이브 변수도 늘어난다.
// App Intent는 앱 타겟 안의 파일 하나면 끝이고, 단축어 앱에서 "공유 시트에
// 표시"를 켜면 공유 메뉴에 똑같이 나타난다.
//
// 설정 → 자동 기록 화면에 단축어 만드는 법을 적어뒀다.

struct CaptureTransactionIntent: AppIntent {

    static var title: LocalizedStringResource = "스크린샷으로 가계부에 기록"

    static var description = IntentDescription(
        "송금·결제 완료 화면을 읽어서 금액과 상대를 채운 채로 앱을 열어요. 저장은 확인하고 누르면 됩니다."
    )

    /// 확인 시트를 사람이 봐야 하므로 항상 앱을 연다.
    /// (메모를 직접 쓰는 게 이 기능의 핵심이라 조용히 저장하지 않는다.)
    static var openAppWhenRun: Bool = true

    @Parameter(title: "스크린샷", supportedContentTypes: [.image])
    var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult {
        let data = Self.load(screenshot)
        let scan = try ReceiptOCR.scan(from: data)
        PendingCapture.stash(scan, imageData: data)
        return .result()
    }

    /// `IntentFile`은 디스크 참조일 수도, 인메모리일 수도 있다.
    /// `data` 는 현재 SDK 에서 throws 가 아니라 `try` 를 붙이면 경고가 난다.
    private static func load(_ file: IntentFile) -> Data {
        if let url = file.fileURL, let data = try? Data(contentsOf: url) {
            return data
        }
        return file.data
    }
}
