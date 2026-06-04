import SwiftUI
import UIKit

/// UITextView wrapper that renders NSAttributedString with tappable links
/// while honoring the per-run foreground color (SwiftUI Text always renders links blue).
struct LinkedTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let onTap: (URL) -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = AutoSizingTextView()
        tv.isEditable = false
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.linkTextAttributes = [:]
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        uiView.attributedText = attributedText
        context.coordinator.onTap = onTap
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, UITextViewDelegate {
        var onTap: ((URL) -> Void)?

        func textView(_ textView: UITextView,
                      shouldInteractWith URL: URL,
                      in characterRange: NSRange,
                      interaction: UITextItemInteraction) -> Bool {
            onTap?(URL)
            return false
        }
    }
}

private class AutoSizingTextView: UITextView {
    override var contentSize: CGSize {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: CGSize {
        let w = bounds.width.isZero ? CGFloat.greatestFiniteMagnitude : bounds.width
        let h = sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: UIView.noIntrinsicMetric, height: max(h, 16))
    }
}
