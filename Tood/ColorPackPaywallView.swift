import SwiftUI

/// Small sheet shown when tapping a locked pack color in any swatch picker:
/// buy via Polar checkout in the browser, or redeem an already-purchased
/// license key without leaving the app.
struct ColorPackPaywallView: View {
    let pack: ColorPack
    var onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var licenseKey = ""
    @State private var isRedeeming = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    ForEach(pack.colors) { c in
                        Circle().fill(c.paper).frame(width: 20, height: 20)
                    }
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(pack.displayName)
                .font(.system(size: 16, weight: .semibold))
            Text("Unlock 5 new sticky colors for \(pack.priceDisplay), one-time, no subscription.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button("Buy \(pack.displayName)") {
                NSWorkspace.shared.open(pack.checkoutURL)
            }
            .buttonStyle(.borderedProminent)

            Divider()

            Text("Already bought it? Paste your license key:")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            HStack {
                TextField("License key", text: $licenseKey)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isRedeeming)
                Button(isRedeeming ? "Checking…" : "Redeem") { redeem() }
                    .disabled(licenseKey.trimmingCharacters(in: .whitespaces).isEmpty || isRedeeming)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func redeem() {
        isRedeeming = true
        errorMessage = nil
        Task {
            defer { isRedeeming = false }
            do {
                try await ColorPackStore.shared.redeem(licenseKey: licenseKey, for: pack)
                onUnlocked()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
