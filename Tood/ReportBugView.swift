import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Text + an optional screenshot, straight to `docs/api/report-bug.js` —
/// the app never knows (and can't know) where it actually ends up. That
/// endpoint is the only thing holding the real destination, as a
/// server-side env var never committed to the (public) repo.
struct ReportBugView: View {
    var onDone: () -> Void

    @State private var text = ""
    @State private var image: NSImage?
    @State private var isSending = false
    @State private var sendError: String?
    @State private var didSend = false

    var body: some View {
        Form {
            Section("What happened?") {
                TextEditor(text: $text)
                    .tint(.primary) // otherwise the cursor/selection inherits the app's green accent, jarring on this plain, neutral form
                    .frame(minHeight: 100)
                Text("No need to include your email, this can't be replied to.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Screenshot (optional)") {
                if let image {
                    HStack {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Spacer()
                        Button("Remove") { self.image = nil }
                    }
                } else {
                    HStack {
                        Button("Attach File…") { pickImage() }
                        Button("Paste from Clipboard") { pasteImage() }
                    }
                }
            }

            if let sendError {
                Text(sendError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Cancel") { onDone() }
                Button(didSend ? "Sent!" : (isSending ? "Sending…" : "Send")) { send() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending || didSend)
            }
            .padding()
        }
        .frame(width: 420, height: 360)
    }

    private func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url, let picked = NSImage(contentsOf: url) else { return }
        image = picked
    }

    private func pasteImage() {
        guard let objects = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
              let pasted = objects.first
        else { return }
        image = pasted
    }

    private func send() {
        isSending = true
        sendError = nil

        var body: [String: Any] = [
            "text": text,
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "macOSVersion": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
        if let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            body["imageBase64"] = pngData.base64EncodedString()
        }

        var request = URLRequest(url: URL(string: "https://toodapp.com/api/report-bug")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { _, response, _ in
            DispatchQueue.main.async {
                isSending = false
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    didSend = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { onDone() }
                } else {
                    sendError = "Couldn't send, check your connection and try again."
                }
            }
        }.resume()
    }
}
