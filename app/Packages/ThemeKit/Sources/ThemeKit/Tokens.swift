import SwiftUI

public struct ColorTokens: @unchecked Sendable {
    public var text: Color
    public var sub: Color
    public var faint: Color
    public var tagBackground: Color
    public var chipBackground: Color
    public var chipBorder: Color
    public var fieldBackground: Color
    public var fieldBorder: Color
    public var divider: Color
    public var segmentBackground: Color
    public var segmentOn: Color
    public var segmentOnText: Color
    public var segmentText: Color
    public var buttonBackground: Color
    public var buttonText: Color
    public var primaryBackground: Color
    public var primaryText: Color
    public var ring: Color
    public var star: Color
    public var copied: Color
    public var hover: Color
    public var selection: Color
    public var panelFill: Color
    public var panelBorder: Color

    public init(
        text: Color,
        sub: Color,
        faint: Color,
        tagBackground: Color,
        chipBackground: Color,
        chipBorder: Color,
        fieldBackground: Color,
        fieldBorder: Color,
        divider: Color,
        segmentBackground: Color,
        segmentOn: Color,
        segmentOnText: Color,
        segmentText: Color,
        buttonBackground: Color,
        buttonText: Color,
        primaryBackground: Color,
        primaryText: Color,
        ring: Color,
        star: Color,
        copied: Color,
        hover: Color,
        selection: Color,
        panelFill: Color,
        panelBorder: Color
    ) {
        self.text = text
        self.sub = sub
        self.faint = faint
        self.tagBackground = tagBackground
        self.chipBackground = chipBackground
        self.chipBorder = chipBorder
        self.fieldBackground = fieldBackground
        self.fieldBorder = fieldBorder
        self.divider = divider
        self.segmentBackground = segmentBackground
        self.segmentOn = segmentOn
        self.segmentOnText = segmentOnText
        self.segmentText = segmentText
        self.buttonBackground = buttonBackground
        self.buttonText = buttonText
        self.primaryBackground = primaryBackground
        self.primaryText = primaryText
        self.ring = ring
        self.star = star
        self.copied = copied
        self.hover = hover
        self.selection = selection
        self.panelFill = panelFill
        self.panelBorder = panelBorder
    }
}

public struct TypographyTokens: @unchecked Sendable {
    public var search: Font
    public var projectName: Font
    public var projectID: Font
    public var meta: Font
    public var timestamp: Font
    public var section: Font
    public var footer: Font
    public var chip: Font
    public var button: Font
    public var avatar: Font
    public var typeBadge: Font
    public var presence: Font
    public var shortcut: Font

    public init(
        search: Font = .system(size: 11.5),
        projectName: Font = .system(size: 12.5, weight: .semibold),
        projectID: Font = .system(size: 9, weight: .medium, design: .monospaced),
        meta: Font = .system(size: 10.5),
        timestamp: Font = .system(size: 10),
        section: Font = .system(size: 9.5, weight: .bold),
        footer: Font = .system(size: 9.5),
        chip: Font = .system(size: 9, weight: .medium, design: .monospaced),
        button: Font = .system(size: 10, weight: .semibold),
        avatar: Font = .system(size: 10, weight: .bold),
        typeBadge: Font = .system(size: 7.5, weight: .bold, design: .monospaced),
        presence: Font = .system(size: 7.5, weight: .bold),
        shortcut: Font = .system(size: 9, weight: .semibold, design: .monospaced)
    ) {
        self.search = search
        self.projectName = projectName
        self.projectID = projectID
        self.meta = meta
        self.timestamp = timestamp
        self.section = section
        self.footer = footer
        self.chip = chip
        self.button = button
        self.avatar = avatar
        self.typeBadge = typeBadge
        self.presence = presence
        self.shortcut = shortcut
    }
}

public struct MetricTokens: @unchecked Sendable {
    public var popoverWidth: CGFloat
    public var popoverMaxHeight: CGFloat
    public var listMaxHeight: CGFloat
    public var panelCornerRadius: CGFloat
    public var rowPadding: CGFloat
    public var rowCornerRadius: CGFloat
    public var rowGap: CGFloat
    public var avatarSize: CGFloat
    public var avatarCornerRadius: CGFloat
    public var starColumnWidth: CGFloat
    public var iconButtonSize: CGSize
    public var iconButtonCornerRadius: CGFloat
    public var typeBadgeSize: CGFloat
    public var typeBadgeCornerRadius: CGFloat
    public var presenceSize: CGFloat
    public var searchFieldCornerRadius: CGFloat
    public var headerPadding: EdgeInsets
    public var footerPadding: EdgeInsets
    public var listPadding: EdgeInsets

    public init(
        popoverWidth: CGFloat = 516,
        popoverMaxHeight: CGFloat = 700,
        listMaxHeight: CGFloat = 640,
        panelCornerRadius: CGFloat = 12,
        rowPadding: CGFloat = 8,
        rowCornerRadius: CGFloat = 8,
        rowGap: CGFloat = 9,
        avatarSize: CGFloat = 26,
        avatarCornerRadius: CGFloat = 7,
        starColumnWidth: CGFloat = 15,
        iconButtonSize: CGSize = CGSize(width: 24, height: 23),
        iconButtonCornerRadius: CGFloat = 6,
        typeBadgeSize: CGFloat = 13,
        typeBadgeCornerRadius: CGFloat = 3,
        presenceSize: CGFloat = 16,
        searchFieldCornerRadius: CGFloat = 8,
        headerPadding: EdgeInsets = EdgeInsets(top: 11, leading: 12, bottom: 10, trailing: 12),
        footerPadding: EdgeInsets = EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12),
        listPadding: EdgeInsets = EdgeInsets(top: 6, leading: 6, bottom: 8, trailing: 6)
    ) {
        self.popoverWidth = popoverWidth
        self.popoverMaxHeight = popoverMaxHeight
        self.listMaxHeight = listMaxHeight
        self.panelCornerRadius = panelCornerRadius
        self.rowPadding = rowPadding
        self.rowCornerRadius = rowCornerRadius
        self.rowGap = rowGap
        self.avatarSize = avatarSize
        self.avatarCornerRadius = avatarCornerRadius
        self.starColumnWidth = starColumnWidth
        self.iconButtonSize = iconButtonSize
        self.iconButtonCornerRadius = iconButtonCornerRadius
        self.typeBadgeSize = typeBadgeSize
        self.typeBadgeCornerRadius = typeBadgeCornerRadius
        self.presenceSize = presenceSize
        self.searchFieldCornerRadius = searchFieldCornerRadius
        self.headerPadding = headerPadding
        self.footerPadding = footerPadding
        self.listPadding = listPadding
    }
}

public struct SurfaceStyle: Sendable {
    public enum Kind: Sendable {
        case glass
        case flat
    }

    public var kind: Kind
    public var cornerRadius: CGFloat

    public init(kind: Kind, cornerRadius: CGFloat) {
        self.kind = kind
        self.cornerRadius = cornerRadius
    }
}
