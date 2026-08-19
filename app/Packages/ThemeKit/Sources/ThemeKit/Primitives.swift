import AppKit
import SwiftUI

public struct RowContainer<Content: View>: View {
    @Environment(\.studioTheme) private var theme
    var isSelected: Bool
    var isHovered: Bool
    @ViewBuilder var content: () -> Content

    public init(isSelected: Bool, isHovered: Bool, @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.isHovered = isHovered
        self.content = content
    }

    public var body: some View {
        let metrics = theme.metrics
        content()
            .padding(metrics.rowPadding)
            .background(
                RoundedRectangle(cornerRadius: theme.cornerRadius(metrics.rowCornerRadius), style: theme.cornerStyle)
                    .fill(isSelected ? theme.colors.selection : (isHovered ? theme.colors.hover : .clear))
            )
    }
}

public struct CopyChip: View {
    @Environment(\.studioTheme) private var theme
    var text: String
    var copied: Bool
    var accessibilityName: String
    var action: () -> Void

    @State private var isHovered = false

    public init(text: String, copied: Bool, accessibilityName: String, action: @escaping () -> Void) {
        self.text = text
        self.copied = copied
        self.accessibilityName = accessibilityName
        self.action = action
    }

    public var body: some View {
        let colors = theme.colors
        Button(action: action) {
            Text(copied ? "copied ✓" : text)
                .font(theme.typography.chip)
                .foregroundStyle(copied ? colors.copied : colors.sub.opacity(isHovered ? 1 : 0.55))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(copied ? "Copied" : accessibilityName)
    }
}

public struct PrimaryButton: View {
    @Environment(\.studioTheme) private var theme
    var title: String
    var action: () -> Void

    public init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(theme.typography.button)
                .foregroundStyle(theme.colors.primaryText)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(theme.colors.primaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(6), style: theme.cornerStyle))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// A `PrimaryButton` pill with an optional attached caret segment that opens
/// a menu of alternate destinations — `[title|⌄]` as one pill, divided by a
/// hairline. The caret is omitted entirely when `menuItems` is empty.
public struct SplitPrimaryButton: View {
    public struct MenuItem: Identifiable {
        public var id: String
        public var title: String
        public var action: () -> Void

        public init(id: String, title: String, action: @escaping () -> Void) {
            self.id = id
            self.title = title
            self.action = action
        }
    }

    @Environment(\.studioTheme) private var theme
    var title: String
    var action: () -> Void
    var menuItems: [MenuItem]

    @State private var menuAnchor: NSView?
    @State private var activeMenuRouter: MenuActionRouter?

    public init(_ title: String, action: @escaping () -> Void, menuItems: [MenuItem] = []) {
        self.title = title
        self.action = action
        self.menuItems = menuItems
    }

    public var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                Text(title)
                    .font(theme.typography.button)
                    .foregroundStyle(theme.colors.primaryText)
                    .padding(.leading, 9)
                    .padding(.trailing, menuItems.isEmpty ? 9 : 7)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)

            if !menuItems.isEmpty {
                Rectangle()
                    .fill(theme.colors.primaryText.opacity(0.3))
                    .frame(width: 1, height: 11)

                Button {
                    showMenu()
                } label: {
                    Image(systemName: "chevron.down")
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.semibold)
                        .frame(width: 6, height: 6)
                        .foregroundStyle(theme.colors.primaryText)
                        .padding(.vertical, 4)
                        .background(MenuAnchorView(anchor: $menuAnchor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("More Studio URLs")
                .padding(.horizontal, 6)
            }
        }
        .background(theme.colors.primaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(6), style: theme.cornerStyle))
        .accessibilityElement(children: .contain)
    }

    /// Shown natively via `NSMenu` rather than SwiftUI's `Menu` — the latter always
    /// draws its own disclosure indicator alongside a custom label (even with
    /// `.menuIndicator(.hidden)`), which read as a distracting "double caret" next
    /// to our own chevron.
    private func showMenu() {
        guard let menuAnchor else { return }
        let menu = NSMenu()

        let header = NSMenuItem(title: "Studio URLs", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        let router = MenuActionRouter()
        for item in menuItems {
            router.addItem(to: menu, title: item.title, action: item.action)
        }
        // NSMenuItem.target is unretained — hold the router in @State so its
        // action closures survive through popUp (which blocks until dismissal).
        activeMenuRouter = router

        // `at:` is the menu's top-left corner in the (non-flipped) anchor's own
        // coordinate space, where the menu always extends downward from there —
        // a small negative y drops that corner just below the anchor's bottom
        // edge, instead of overlapping the button by aligning it to the top.
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: menuAnchor)
    }
}

/// An invisible `NSView` used only to capture a stable AppKit anchor for
/// `NSMenu.popUp(positioning:at:in:)`, since SwiftUI has no public API to
/// present a menu without a user-initiated click on it.
private struct MenuAnchorView: NSViewRepresentable {
    @Binding var anchor: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { anchor = view }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class MenuActionRouter: NSObject {
    private var actions: [() -> Void] = []

    func addItem(to menu: NSMenu, title: String, action: @escaping () -> Void) {
        let index = actions.count
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self
        item.tag = index
        menu.addItem(item)
    }

    @objc private func invoke(_ sender: NSMenuItem) {
        actions[sender.tag]()
    }
}

public struct IconButton: View {
    private enum Source {
        case system(String)
        /// A template-rendered asset from the app's own asset catalog (e.g. a Sanity icon).
        case asset(String)
    }

    @Environment(\.studioTheme) private var theme
    private var source: Source
    var accessibilityLabel: String
    var action: () -> Void

    public init(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.source = .system(systemName)
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public init(imageName: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.source = .asset(imageName)
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics
        Button(action: action) {
            icon
                .foregroundStyle(theme.colors.buttonText)
                .frame(width: metrics.iconButtonSize.width, height: metrics.iconButtonSize.height)
                .background(theme.colors.buttonBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: theme.cornerRadius(metrics.iconButtonCornerRadius), style: theme.cornerStyle)
                        .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(metrics.iconButtonCornerRadius), style: theme.cornerStyle))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch source {
        case .system(let name):
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
        case .asset(let name):
            Image(name)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 16, height: 16)
        }
    }
}

public struct SectionHeader: View {
    @Environment(\.studioTheme) private var theme
    var title: String
    var itemCount: Int?
    var accessory: String?
    var accessoryCopied: Bool
    var onAccessory: (() -> Void)?
    var isFavorite: Bool?
    var onToggleFavorite: (() -> Void)?

    @State private var isAccessoryHovered = false

    public init(
        title: String,
        itemCount: Int? = nil,
        accessory: String? = nil,
        accessoryCopied: Bool = false,
        onAccessory: (() -> Void)? = nil,
        isFavorite: Bool? = nil,
        onToggleFavorite: (() -> Void)? = nil
    ) {
        self.title = title
        self.itemCount = itemCount
        self.accessory = accessory
        self.accessoryCopied = accessoryCopied
        self.onAccessory = onAccessory
        self.isFavorite = isFavorite
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        let colors = theme.colors
        HStack(spacing: 6) {
            if let isFavorite {
                Button {
                    onToggleFavorite?()
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(isFavorite ? theme.colors.star : colors.faint)
                        .frame(width: theme.metrics.starColumnWidth)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFavorite ? "Remove organization from favorites" : "Add organization to favorites")
            }

            Text(itemCount.map { "\(title.uppercased()) (\($0))" } ?? title.uppercased())
                .font(theme.typography.section)
                .tracking(0.7)
                .foregroundStyle(colors.faint)

            if let accessory {
                Button {
                    onAccessory?()
                } label: {
                    Text(accessoryCopied ? "copied ✓" : accessory)
                        .font(theme.typography.chip)
                        .tracking(0.2)
                        .foregroundStyle(accessoryCopied ? colors.copied : colors.faint.opacity(isAccessoryHovered ? 1 : 0.55))
                }
                .buttonStyle(.plain)
                .onHover { isAccessoryHovered = $0 }
                .accessibilityLabel(accessoryCopied ? "Copied" : "Copy organization ID \(accessory)")
            }

            Rectangle()
                .fill(colors.divider)
                .frame(height: 1)
        }
        .padding(.leading, 8 + theme.metrics.listPadding.leading)
        .padding(.trailing, 8 + theme.metrics.listPadding.trailing)
        .padding(.top, 3)
        .padding(.bottom, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backing)
    }

    @ViewBuilder
    private var backing: some View {
        if theme.surface.kind == .glass {
            Color.clear
        } else {
            theme.colors.panelFill
        }
    }
}

public struct AvatarStack: View {
    @Environment(\.studioTheme) private var theme

    public struct Item: Identifiable, Sendable {
        public var id: String
        public var name: String
        public var initials: String
        public var color: Color
        public var imageURL: URL?
        public var deepLinkURL: URL?

        public init(id: String, name: String, initials: String, color: Color, imageURL: URL? = nil, deepLinkURL: URL? = nil) {
            self.id = id
            self.name = name
            self.initials = initials
            self.color = color
            self.imageURL = imageURL
            self.deepLinkURL = deepLinkURL
        }
    }

    var items: [Item]
    var maxVisible: Int
    var onSelect: (Item) -> Void

    @State private var hoveredID: String?
    /// The item the tooltip renders — kept alive (unlike `hoveredID`) once the
    /// mouse leaves the stack so the fade-out animates its last content instead
    /// of jumping to blank.
    @State private var displayedItem: Item?
    @State private var isTooltipVisible = false
    @State private var avatarFrames: [String: CGRect] = [:]
    @State private var showTask: Task<Void, Never>?

    private static let coordinateSpaceName = "avatarStack"

    public init(items: [Item], maxVisible: Int = 3, onSelect: @escaping (Item) -> Void = { _ in }) {
        self.items = items
        self.maxVisible = maxVisible
        self.onSelect = onSelect
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let visible = Array(items.prefix(maxVisible))
            let overflow = items.count - visible.count
            HStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(item)
                    } label: {
                        avatarCircle(item)
                    }
                    .buttonStyle(.plain)
                    .disabled(item.deepLinkURL == nil)
                    .padding(.leading, index == 0 ? 0 : -4)
                    // Raised above overlapping neighbors on hover so the
                    // whole circle is visible rather than clipped by
                    // whichever avatar is stacked on top of it.
                    .zIndex(hoveredID == item.id ? 1 : 0)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: AvatarFramePreferenceKey.self,
                                value: [item.id: proxy.frame(in: .named(Self.coordinateSpaceName))]
                            )
                        }
                    )
                    // Reports this avatar's bounds as an `Anchor` (rather than a
                    // resolved rect in some coordinate space) whenever it's the
                    // one the tooltip should point at, so whichever ancestor
                    // ends up rendering the tooltip can resolve it correctly
                    // via its own `GeometryProxy` regardless of nesting/padding.
                    .anchorPreference(key: AvatarTooltipAnchorKey.self, value: .bounds) { bounds in
                        item.id == displayedItem?.id ? bounds : nil
                    }
                }
                if overflow > 0 {
                    Text("+\(overflow)")
                        .font(theme.typography.presence)
                        .foregroundStyle(theme.colors.sub)
                        .padding(.leading, 4)
                }
            }
            .padding(.leading, 4)
            .coordinateSpace(name: Self.coordinateSpaceName)
            // A single continuous-hover region (rather than per-avatar `onHover`)
            // avoids the flicker of one avatar's hover-exit racing another's
            // hover-enter as the mouse crosses their overlapping edge.
            .onContinuousHover(coordinateSpace: .named(Self.coordinateSpaceName)) { phase in
                handleHover(phase, visible: visible)
            }
            // The tooltip itself isn't rendered here: this stack sits inside a
            // pinned-header `LazyVStack` row, and a pinned header gets an
            // elevated compositing layer no in-row `.zIndex` can out-rank, so
            // an ancestor above the scroll view (via `AvatarTooltipAnchorKey`
            // above) renders it instead.
            .preference(
                key: AvatarTooltipPreferenceKey.self,
                value: displayedItem.map { item in
                    AvatarTooltipDisplay(name: item.name, isVisible: isTooltipVisible)
                }
            )
            .onPreferenceChange(AvatarFramePreferenceKey.self) { avatarFrames = $0 }
        }
    }

    private func handleHover(_ phase: HoverPhase, visible: [Item]) {
        switch phase {
        case .active(let location):
            guard let hit = visible.reversed().first(where: { avatarFrames[$0.id]?.contains(location) == true }) else {
                hideTooltip()
                return
            }
            guard hoveredID != hit.id else { return }
            let wasHidden = hoveredID == nil
            // Snap instantly — no animation — while moving between touching avatars.
            hoveredID = hit.id
            displayedItem = hit
            if wasHidden {
                // Only the very first avatar of a session waits — matches how a
                // native tooltip delays before appearing, but not before updating.
                showTask?.cancel()
                showTask = Task {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) { isTooltipVisible = true }
                }
            }
        case .ended:
            hideTooltip()
        }
    }

    private func hideTooltip() {
        guard hoveredID != nil else { return }
        showTask?.cancel()
        showTask = nil
        hoveredID = nil
        withAnimation(.easeOut(duration: 0.12)) { isTooltipVisible = false }
    }

    @ViewBuilder
    private func avatarCircle(_ item: Item) -> some View {
        Group {
            if let imageURL = item.imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsCircle(item)
                }
            } else {
                initialsCircle(item)
            }
        }
        .frame(width: theme.metrics.presenceSize, height: theme.metrics.presenceSize)
        .clipShape(Circle())
        .overlay(Circle().stroke(theme.colors.ring, lineWidth: 1.5))
        .accessibilityLabel(item.initials.isEmpty ? "Someone is editing now" : "\(item.initials) is editing now")
    }

    /// Blank (no letter) rather than guessing from a raw id — `item.initials`
    /// is empty until the member's real name/photo has actually loaded (see
    /// `Member.initials(from:)` on an empty `displayName`).
    private func initialsCircle(_ item: Item) -> some View {
        Text(item.initials)
            .font(theme.typography.presence)
            .foregroundStyle(.white)
            .frame(width: theme.metrics.presenceSize, height: theme.metrics.presenceSize)
            .background(item.color)
    }
}

private struct AvatarFrameInfo: Equatable {
    var local: CGRect
    var global: CGRect
}

private struct AvatarFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The currently-hovered avatar's bounds, reported as an `Anchor` rather than
/// a rect resolved in some fixed coordinate space, so whichever ancestor ends
/// up rendering the tooltip (see `AvatarTooltipPreferenceKey`) can resolve it
/// correctly via its own `GeometryProxy` regardless of nesting.
public struct AvatarTooltipAnchorKey: PreferenceKey {
    public static let defaultValue: Anchor<CGRect>? = nil
    public static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// What `AvatarStack` wants shown for its hover tooltip — reported via
/// preference so an ancestor above the scroll view can render it (see the
/// comment at the `.preference` call site in `AvatarStack.body`).
public struct AvatarTooltipDisplay: Equatable, Sendable {
    public var name: String
    public var isVisible: Bool

    public init(name: String, isVisible: Bool) {
        self.name = name
        self.isVisible = isVisible
    }
}

public struct AvatarTooltipPreferenceKey: PreferenceKey {
    public static let defaultValue: AvatarTooltipDisplay? = nil
    public static func reduce(value: inout AvatarTooltipDisplay?, nextValue: () -> AvatarTooltipDisplay?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Custom (non-native) tooltip bubble for `AvatarStack`'s hover. Rendered by
/// an ancestor of the scroll view — see `AvatarTooltipPreferenceKey`.
public struct AvatarTooltip: View {
    @Environment(\.studioTheme) private var theme
    var name: String

    public init(name: String) {
        self.name = name
    }

    public var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.colors.text)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(theme.colors.panelFill)
            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            // `.overlay(alignment:)` on the avatar stack proposes the stack's own
            // (narrow) width to this tooltip — without this it would get squeezed
            // into that width instead of sizing to fit the name.
            .fixedSize()
    }
}

public struct TypeBadge: View {
    @Environment(\.studioTheme) private var theme
    var typeName: String

    public init(typeName: String) {
        self.typeName = typeName
    }

    public var body: some View {
        let letter = String(typeName.prefix(1)).uppercased()
        Text(letter)
            .font(theme.typography.typeBadge)
            .foregroundStyle(theme.colors.faint)
            .frame(width: theme.metrics.typeBadgeSize, height: theme.metrics.typeBadgeSize)
            .background(theme.colors.chipBackground)
            .overlay(
                RoundedRectangle(cornerRadius: theme.cornerRadius(theme.metrics.typeBadgeCornerRadius), style: theme.cornerStyle)
                    .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(theme.metrics.typeBadgeCornerRadius), style: theme.cornerStyle))
            .accessibilityLabel("Schema type: \(typeName)")
    }
}

public struct SearchFieldChrome<Content: View>: View {
    @Environment(\.studioTheme) private var theme
    @ViewBuilder var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.colors.faint)
            content()
            KeycapLegend([.symbol("command"), .text("K")])
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            ZStack {
                theme.colors.chipBackground
                Color.black.opacity(0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(theme.metrics.searchFieldCornerRadius), style: theme.cornerStyle))
    }
}

/// A single keyboard-key glyph rendered in a keycap legend — an SF Symbol where one exists,
/// otherwise a literal character (e.g. "," or "1–9", which have no SF Symbol equivalent).
public enum KeyGlyph: Hashable, Sendable {
    case symbol(String)
    case text(String)
}

/// A single glyph within a `KeycapLegend`, drawn with no background of its own —
/// the legend applies one shared border around the whole combo, not per-glyph.
private struct KeyGlyphView: View {
    @Environment(\.studioTheme) private var theme
    var glyph: KeyGlyph

    init(_ glyph: KeyGlyph) {
        self.glyph = glyph
    }

    var body: some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 8, weight: .semibold))
        case .text(let text):
            Text(text)
                .font(.system(size: 8, weight: .semibold))
        }
    }
}

/// Renders a keyboard shortcut as a single keycap chip — every glyph in the combo
/// (e.g. ⌘ + K) shares one border, rather than each glyph getting its own box.
public struct KeycapLegend: View {
    @Environment(\.studioTheme) private var theme
    var glyphs: [KeyGlyph]
    var compact: Bool

    /// `compact` shrinks the chip's own padding/frame only — glyph font sizes are
    /// unaffected, so the keys stay legible while taking up less room in tight rows.
    public init(_ glyphs: [KeyGlyph], compact: Bool = false) {
        self.glyphs = glyphs
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 2 : 3) {
            ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
                KeyGlyphView(glyph)
            }
        }
        .foregroundStyle(theme.colors.faint)
        .frame(minHeight: compact ? 11 : 14)
        .padding(.horizontal, compact ? 2 : 5)
        .padding(.vertical, compact ? 1.5 : 2)
        .background(theme.colors.chipBackground)
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius(4), style: theme.cornerStyle)
                .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(4), style: theme.cornerStyle))
        .accessibilityHidden(true)
    }
}

public struct GroupByControl<Value: Hashable>: View {
    @Environment(\.studioTheme) private var theme
    var selection: Binding<Value>
    var options: [(Value, String)]
    var legend: [KeyGlyph]

    @State private var isHovered = false

    public init(selection: Binding<Value>, options: [(Value, String)], legend: [KeyGlyph] = []) {
        self.selection = selection
        self.options = options
        self.legend = legend
    }

    private var selectedTitle: String {
        options.first(where: { $0.0 == selection.wrappedValue })?.1 ?? ""
    }

    public var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(options, id: \.0) { value, title in
                    Button(title) {
                        selection.wrappedValue = value
                    }
                }
            } label: {
                Text(selectedTitle)
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(theme.colors.faint)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .tint(theme.colors.faint)
            .fixedSize()

            if !legend.isEmpty {
                KeycapLegend(legend, compact: true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            ZStack {
                theme.colors.chipBackground
                Color.black.opacity(isHovered ? 0.10 : 0.04)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(4), style: theme.cornerStyle))
        .onHover { isHovered = $0 }
    }
}

public struct ProjectAvatar: View {
    @Environment(\.studioTheme) private var theme
    var name: String
    var brandHex: String?
    var favicon: Image?

    public init(name: String, brandHex: String?, favicon: Image? = nil) {
        self.name = name
        self.brandHex = brandHex
        self.favicon = favicon
    }

    public var body: some View {
        let size = theme.metrics.avatarSize
        let letter = String(name.prefix(1)).uppercased()
        let initials = DisplayInitials.from(name)
        ZStack {
            if let favicon {
                theme.colors.tagBackground
                favicon
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
            } else if let brandHex {
                Color(hex: brandHex)
                Text(letter)
                    .font(theme.typography.avatar)
                    .foregroundStyle(.white)
            } else {
                theme.colors.tagBackground
                Text(initials)
                    .font(theme.typography.avatar)
                    .foregroundStyle(theme.colors.sub)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(theme.metrics.avatarCornerRadius), style: theme.cornerStyle))
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius(theme.metrics.avatarCornerRadius), style: theme.cornerStyle)
                .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

public enum DisplayInitials {
    public static func from(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: #"[()]"#, with: "", options: .regularExpression)
        let parts = cleaned.split { $0 == " " || $0 == "&" }.filter { !$0.isEmpty }
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }
}
