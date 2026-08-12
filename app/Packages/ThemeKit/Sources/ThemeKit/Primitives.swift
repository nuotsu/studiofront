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

public struct IconButton: View {
    @Environment(\.studioTheme) private var theme
    var systemName: String
    var accessibilityLabel: String
    var action: () -> Void

    public init(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    public var body: some View {
        let metrics = theme.metrics
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
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
            GlassSurface(cornerRadius: 0, blendingMode: .withinWindow, preferSimpleMaterial: true)
                .allowsHitTesting(false)
        } else {
            theme.colors.panelFill
        }
    }
}

public struct AvatarStack: View {
    @Environment(\.studioTheme) private var theme

    public struct Item: Identifiable, Sendable {
        public var id: String
        public var initials: String
        public var color: Color
        public var imageURL: URL?
        public var deepLinkURL: URL?

        public init(id: String, initials: String, color: Color, imageURL: URL? = nil, deepLinkURL: URL? = nil) {
            self.id = id
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
                    .onHover { isHovered in
                        hoveredID = isHovered ? item.id : (hoveredID == item.id ? nil : hoveredID)
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
        }
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
