import SwiftUI

struct AIUnavailableBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: Theme.spacingS) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(Theme.caption())
                .foregroundStyle(.secondary)
            Spacer()
            Button(L.aiBannerSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(Theme.caption().bold())
            .foregroundStyle(.blue)
        }
        .padding(Theme.spacingS)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusS))
    }
}
