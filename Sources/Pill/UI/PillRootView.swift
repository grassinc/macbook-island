import SwiftUI
import PillCore

struct PillRootView: View {
    @ObservedObject var model: PillViewModel

    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.black)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, y: 2)

            content
                .padding(.horizontal, 14)
        }
        .frame(width: model.presentation.size.width,
               height: model.presentation.size.height)
        .animation(.spring(response: 0.34, dampingFraction: 0.82),
                   value: model.presentation)
        .onHover { model.setHovered($0) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .collapsed:
            HStack(spacing: 8) {
                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: 6, height: 6)
                Text(model.activity?.id ?? "Pill")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        case .expanded:
            VStack(alignment: .leading, spacing: 6) {
                Text(model.activity?.id ?? "Pill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("v0.1 — window layer up")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
    }
}
