import SwiftUI

struct PlanningFilterOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String
    var id: Value { value }
}

/// A single glass surface keeps filters distinct from the scrolling results.
struct PlanningFilters<Value: Hashable>: View {
    let options: [PlanningFilterOption<Value>]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AETheme.spacingXS) {
                ForEach(options) { option in
                    Button { selection = option.value } label: {
                        Label(option.title, systemImage: option.symbol)
                            .font(.subheadline.weight(.medium))
                            .fixedSize()
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                            .background(selection == option.value
                                ? AETheme.accent.opacity(0.2) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                }
            }
            .padding(4)
        }
        .scrollIndicators(.hidden)
        .aeGlass(in: RoundedRectangle(cornerRadius: 28))
        .aeAnimation(AEMotion.selection, value: selection)
    }
}
