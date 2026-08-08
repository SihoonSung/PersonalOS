import Foundation
#if canImport(Vision)
import Vision
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - 스크린샷에서 글자 읽기
//
// Vision 은 온디바이스라 네트워크도, 사용자 권한도 필요 없다. 스크린샷 한 장에
// 수십 ms 걸리므로 백그라운드로 넘기지 않고 그냥 호출한 자리에서 돌린다.
//
// 줄 순서가 중요하다 — 파서가 "라벨 다음 줄에 값" 배치를 읽기 때문이다.
// Vision 은 관측을 화면 순서로 주지 않으므로 반드시 위→아래로 다시 세운다.

enum ReceiptOCR {

    enum Failure: LocalizedError {
        case unreadableImage
        case noText
        case unsupported

        var errorDescription: String? {
            switch self {
            case .unreadableImage: return "이미지를 열 수 없었어요."
            case .noText: return "화면에서 글자를 찾지 못했어요."
            case .unsupported: return "이 기기에서는 글자 인식을 쓸 수 없어요."
            }
        }
    }

    static func lines(from data: Data) throws -> [String] {
        #if canImport(Vision)
        guard let image = cgImage(from: data) else { throw Failure.unreadableImage }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US", "ko-KR"]
        // 금액·계좌번호를 "고쳐주는" 걸 막는다. 사전 교정은 이름에도 해롭다.
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        let observations = request.results ?? []
        let lines = observations
            .sorted { lhs, rhs in
                // 위쪽 먼저. 같은 높이면 왼쪽 먼저.
                if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > 0.005 {
                    return lhs.boundingBox.midY > rhs.boundingBox.midY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            .compactMap { $0.topCandidates(1).first?.string }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { throw Failure.noText }
        return lines
        #else
        throw Failure.unsupported
        #endif
    }

    /// 스크린샷 → 확인 시트에 채울 값.
    static func scan(from data: Data, now: Date = .now) throws -> ReceiptScan {
        ReceiptTextParser.parse(lines: try lines(from: data), now: now)
    }

    private static func cgImage(from data: Data) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(data: data)?.cgImage
        #elseif canImport(AppKit)
        return NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return nil
        #endif
    }
}
