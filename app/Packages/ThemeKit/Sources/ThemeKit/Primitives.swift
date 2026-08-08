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
                RoundedRectangle(cornerRadius: metrics.rowCornerRadius, style: .continuous)
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
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
                    RoundedRectangle(cornerRadius: metrics.iconButtonCornerRadius, style: .continuous)
                        .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: metrics.iconButtonCornerRadius, style: .continuous))
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

        public init(id: String, initials: String, color: Color) {
            self.id = id
            self.initials = initials
            self.color = color
        }
    }

    var items: [Item]
    var maxVisible: Int

    public init(items: [Item], maxVisible: Int = 3) {
        self.items = items
        self.maxVisible = maxVisible
    }

    public var body: some View {
        if items.isEmpty {
            EmptyView()
        } else {
            let visible = Array(items.prefix(maxVisible))
            let overflow = items.count - visible.count
            HStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                    Text(item.initials)
                        .font(theme.typography.presence)
                        .foregroundStyle(.white)
                        .frame(width: theme.metrics.presenceSize, height: theme.metrics.presenceSize)
                        .background(Circle().fill(item.color))
                        .overlay(Circle().stroke(theme.colors.ring, lineWidth: 1.5))
                        .padding(.leading, index == 0 ? 0 : -4)
                        .accessibilityLabel("\(item.initials) is editing now")
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
                RoundedRectangle(cornerRadius: theme.metrics.typeBadgeCornerRadius, style: .continuous)
                    .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: theme.metrics.typeBadgeCornerRadius, style: .continuous))
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
            Text("⌘K")
                .font(theme.typography.shortcut)
                .foregroundStyle(theme.colors.faint)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(theme.colors.chipBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(theme.colors.fieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.searchFieldCornerRadius, style: .continuous)
                .strokeBorder(theme.colors.fieldBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.searchFieldCornerRadius, style: .continuous))
    }
}

public struct GroupByControl<Value: Hashable>: View {
    @Environment(\.studioTheme) private var theme
    var selection: Binding<Value>
    var options: [(Value, String)]

    public init(selection: Binding<Value>, options: [(Value, String)]) {
        self.selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let on = selection.wrappedValue == value
                Button {
                    selection.wrappedValue = value
                } label: {
                    Text(title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(on ? theme.colors.segmentOnText : theme.colors.segmentText)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(on ? theme.colors.segmentOn : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(theme.colors.segmentBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
        .clipShape(RoundedRectangle(cornerRadius: theme.metrics.avatarCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: theme.metrics.avatarCornerRadius, style: .continuous)
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
