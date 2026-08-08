import SwiftUI
import SwiftData

/// 노션 동기화가 **문제일 때만** 보이는 카드.
///
/// 정상일 때 조용한 게 핵심이다. 동기화는 저장할 때마다 3초 디바운스로 도는데,
/// 조용히 실패하면 앱과 노션이 서서히 어긋나고 — 메일로 수집한 거래가 노션에
/// 안 올라가면 검증 루틴이 그걸 "파서가 놓침"으로 오진한다. 그래서 실패와
/// 지연만큼은 눈에 띄어야 한다.
struct NotionStatusCard: View {
    @Query private var databases: [POSDatabase]
    @ObservedObject private var sync = NotionSyncService.shared

    private var linkedCount: Int {
        databases.filter { $0.notionSyncEnabled && $0.notionDatabaseID != nil }.count
    }

    var body: some View {
        switch sync.health(linkedCount: linkedCount) {
        case .idle, .ok, .syncing:
            EmptyView()

        case .stale(let last):
            banner(
                tint: .orange,
                icon: "clock.badge.exclamationmark",
                title: "노션 동기화 지연",
                detail: last.map { "마지막 성공 \(relative($0))" } ?? "아직 한 번도 성공하지 않았어요"
            )

        case .failing(let reason):
            banner(
                tint: .red,
                icon: "exclamationmark.triangle.fill",
                title: "노션 동기화 실패",
                detail: reason
            )
        }
    }

    private func banner(tint: Color, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacingS) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.caption().bold())
                Text(detail)
                    .font(Theme.caption2())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                if sync.pendingArchiveCount > 0 {
                    Text("노션에 반영 못 한 삭제 \(sync.pendingArchiveCount)건")
                        .font(Theme.caption2())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer(minLength: 0)

            if sync.isSyncing {
                ProgressView().controlSize(.small)
            } else {
                Button("다시 시도") {
                    Task { await sync.syncAll() }
                }
                .font(Theme.caption2().bold())
                .buttonStyle(.plain)
                .foregroundStyle(tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingM)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.radiusL))
    }

    private func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L.locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
