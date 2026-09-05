import SwiftUI

/// This screen deliberately has no model container: no logging UI or background
/// seeding can accidentally accept changes while durable storage is unavailable.
struct PersistenceUnavailableView: View {
    let failure: PersistenceOpenFailure
    let retry: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPreparingCopy = false
    @State private var recoveryCopy: URL?
    @State private var copyFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.largeTitle)
                    .accessibilityHidden(true)
                Text("Unable to open workouts")
                    .font(.title2.bold())
                    .accessibilityIdentifier("Storage.Unavailable.Title")
                Text(failure.guidance)
                    .font(.body)
                Text("Logging is paused. Marble has not replaced or erased your saved workout files.")
                    .font(.body)
                Button("Try Again", action: retry)
                    .buttonStyle(MarbleActionButtonStyle(expandsHorizontally: true, prominence: .primary))
                    .disabled(isPreparingCopy)
                    .accessibilityIdentifier("Storage.Retry")
                if let recoveryCopy {
                    ShareLink(item: recoveryCopy) {
                        Label("Save Recovery Copy", systemImage: "square.and.arrow.up")
                            .frame(minHeight: 44)
                    }
                        .accessibilityIdentifier("Storage.ShareRecovery")
                    Text("This copy contains private workout data. Save it somewhere you trust or share it only with support you choose.")
                        .font(.footnote)
                } else {
                    Button {
                        isPreparingCopy = true
                        copyFailed = false
                        Task {
                            do { recoveryCopy = try await PersistenceRecoveryCopy.prepare(at: PersistenceController.storeURL) }
                            catch { copyFailed = true }
                            isPreparingCopy = false
                        }
                    } label: {
                        Label(isPreparingCopy ? "Preparing Copy…" : "Prepare Recovery Copy", systemImage: "doc.on.doc")
                            .frame(minHeight: 44)
                    }
                    .disabled(isPreparingCopy)
                    .accessibilityIdentifier("Storage.PrepareRecovery")
                }
                if copyFailed {
                    Text("The copy couldn't be prepared. Your original files remain in place. Try again after storage access is restored.")
                        .font(.body)
                        .accessibilityIdentifier("Storage.CopyError")
                }
            }
            .foregroundStyle(Theme.primaryTextColor(for: colorScheme))
            .frame(maxWidth: 560, alignment: .leading)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.backgroundColor(for: colorScheme))
    }
}
