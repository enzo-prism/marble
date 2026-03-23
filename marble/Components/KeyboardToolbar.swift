import SwiftUI
import UIKit

struct KeyboardToolbarAction {
    let title: String
    var accessibilityIdentifier: String?
    var isEnabled: Bool = true
    let handler: () -> Void
}

enum MarbleKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct MarbleKeyboardToolbarModifier: ViewModifier {
    let primaryAction: KeyboardToolbarAction?
    let doneIdentifier: String
    let onDone: (() -> Void)?

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if let primaryAction {
                    keyboardActionButton(for: primaryAction)
                }

                Spacer()

                Button("Done") {
                    if let onDone {
                        onDone()
                    } else {
                        MarbleKeyboard.dismiss()
                    }
                }
                .accessibilityIdentifier(doneIdentifier)
            }
        }
    }

    @ViewBuilder
    private func keyboardActionButton(for action: KeyboardToolbarAction) -> some View {
        let button = Button(action.title) {
            MarbleKeyboard.dismiss()
            action.handler()
        }
        .disabled(!action.isEnabled)

        if let accessibilityIdentifier = action.accessibilityIdentifier {
            button.accessibilityIdentifier(accessibilityIdentifier)
        } else {
            button
        }
    }
}

extension View {
    func marbleKeyboardToolbar(
        primaryAction: KeyboardToolbarAction? = nil,
        doneIdentifier: String = "Keyboard.Done",
        onDone: (() -> Void)? = nil
    ) -> some View {
        modifier(
            MarbleKeyboardToolbarModifier(
                primaryAction: primaryAction,
                doneIdentifier: doneIdentifier,
                onDone: onDone
            )
        )
    }
}
