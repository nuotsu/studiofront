import SwiftUI

struct SettingsPaneChrome<Content: View>: View {
    @Environment(SettingsSearchState.self) private var search

    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollViewReader { proxy in
            content()
                .scrollEdgeEffectStyle(.soft, for: .top)
                .safeAreaBar(edge: .top) {
                    Text(title)
                        .font(.title.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 8)
                }
                .onChange(of: search.highlightedTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
        }
    }
}
