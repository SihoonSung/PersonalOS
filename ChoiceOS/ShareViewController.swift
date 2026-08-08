import UIKit
import UniformTypeIdentifiers

// MARK: - 공유 시트에서 바로 받기
//
// 이 익스텐션은 **얇게** 만든다. 화면에서 글자를 읽어 앱 그룹에 적어두고 본체
// 앱을 여는 것까지만 한다. 확인·저장은 앱 안의 `CaptureReviewSheet` 가 한다.
//
// 왜 여기서 저장까지 하지 않나:
// SwiftData 저장소가 앱 컨테이너에 있어서 익스텐션은 같은 DB 를 못 본다.
// 앱 그룹으로 옮기면 되지만, CloudKit 이 붙은 **운영 중인 데이터**를 이사시키는
// 일이라 위험 대비 이득이 없다. 카테고리 학습·중복 검사도 전부 DB 가 있어야
// 제대로 되므로 앱 쪽에서 하는 게 맞다.
//
// 공유하는 파일(타겟 멤버십을 이 익스텐션에도 켜야 하는 것):
//   PersonalOS/Capture/ReceiptScan.swift
//   PersonalOS/Capture/ReceiptOCR.swift
//   PersonalOS/Capture/PendingCapture.swift
//   PersonalOS/Core/WidgetSnapshot.swift   (앱 그룹 ID)
//   PersonalOS/Core/Templates.swift        (EntryKind)

final class ShareViewController: UIViewController {

    private let spinner = UIActivityIndicatorView(style: .large)
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpUI()
        Task { await handleSharedItem() }
    }

    private func setUpUI() {
        view.backgroundColor = .systemBackground

        label.text = "화면을 읽는 중…"
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
        spinner.startAnimating()
    }

    // MARK: 처리

    private func handleSharedItem() async {
        guard let data = await firstImageData() else {
            return finish(error: "이미지를 찾지 못했어요.")
        }
        do {
            let scan = try ReceiptOCR.scan(from: data)
            PendingCapture.stash(scan, imageData: data)
            openContainingApp()
            complete()
        } catch {
            finish(error: error.localizedDescription)
        }
    }

    /// 첨부 중 첫 번째 이미지. 스크린샷은 보통 하나지만 여러 장이 올 수도 있다.
    private func firstImageData() async -> Data? {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for item in items {
            for provider in item.attachments ?? [] {
                guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
                if let data = await loadImageData(from: provider) { return data }
            }
        }
        return nil
    }

    /// `loadItem` 은 URL · UIImage · Data 중 아무거나 줄 수 있어서 셋 다 받는다.
    private func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { value, _ in
                switch value {
                case let url as URL:
                    continuation.resume(returning: try? Data(contentsOf: url))
                case let image as UIImage:
                    continuation.resume(returning: image.pngData())
                case let data as Data:
                    continuation.resume(returning: data)
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: 본체 앱 열기
    //
    // 익스텐션에서는 `UIApplication.shared` 를 쓸 수 없다. 최근 iOS 에서는
    // `extensionContext.open(_:)` 이 동작하지만 보장이 약해서, 실패하면
    // 응답 체인을 거슬러 올라가 `openURL:` 을 직접 부르는 길을 남겨둔다.
    private func openContainingApp() {
        guard let url = URL(string: "personalos://capture") else { return }
        extensionContext?.open(url) { [weak self] opened in
            guard !opened else { return }
            self?.openViaResponderChain(url)
        }
    }

    private func openViaResponderChain(_ url: URL) {
        var responder: UIResponder? = self
        let selector = NSSelectorFromString("openURL:")
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
    }

    // MARK: 종료

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func finish(error: String) {
        spinner.stopAnimating()
        label.text = error
        // 사람이 문구를 읽을 시간을 준 뒤 닫는다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.complete()
        }
    }
}
