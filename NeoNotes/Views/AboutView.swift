import AppKit
import SwiftUI

struct AboutView: View {
    private static let version =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 108, height: 108)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 5)

            Text("NeoNotes")
                .font(.title2.weight(.bold))
                .padding(.top, 12)

            Text("Version \(Self.version)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text("Markdown notes in your menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            HStack(spacing: 8) {
                linkButton("GitHub", symbol: "chevron.left.forwardslash.chevron.right",
                           url: "https://github.com/lodev09/neonotes")
                linkButton("@lodev09", symbol: "person.crop.circle",
                           url: "https://github.com/lodev09")
            }
            .padding(.top, 14)

            Text("© 2026 Jovanni Lo")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 18)
        }
        .padding(.horizontal, 48)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .fixedSize()
    }

    private func linkButton(_ title: String, symbol: String, url: String) -> some View {
        Button {
            NSWorkspace.shared.open(URL(string: url)!)
        } label: {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
