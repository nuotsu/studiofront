import SwiftUI
import ThemeKit
import StudioStore

// Performance notes for everything in this file:
//
// Each list row is built from scratch whenever it scrolls into view or a
// search changes the results, so the cost of a row is roughly the number of
// SwiftUI views and modifiers in it. Three rules follow from profiling:
//
// - Small controls use `onTapGesture`, not `Button`. Every `Button` carries
//   focus, keyboard-shortcut and window-activation wrappers.
// - A view that owns `@State` (hover, loaded image) is kept as small as
//   possible, so a state change re-runs a tiny body, not the whole row.
// - Views that read the store read it as low in the tree as possible, so a
//   store change redraws one chip, not every visible row.

enum ProjectRowChrome {
    static func faviconHost(for row: ProjectRow) -> String? {
        if let frontendHost = row.curation.primaryFrontendURL?.host, !frontendHost.isEmpty {
            return frontendHost
        }
        if let externalHost = row.project.externalStudioHost?.host, !externalHost.isEmpty {
            return externalHost
        }
        if let studioHost = row.project.studioHost, !studioHost.isEmpty {
            return "\(studioHost).sanity.studio"
        }
        return nil
    }

    /// How many Studio URLs a project has. More than one puts the count
    /// badge on the row's favicon.
    static func studioCount(for row: ProjectRow) -> Int {
        row.project.studioApps.reduce(0) { $1.resolvedURL == nil ? $0 : $0 + 1 }
    }

    /// Every registered Studio URL for a project, as menu items. Only built
    /// when a menu actually opens.
    @MainActor
    static func studioMenuItems(for row: ProjectRow) -> [SplitPrimaryButton.MenuItem] {
        row.project.studioApps.compactMap { app in
            guard let url = app.resolvedURL else { return nil }
            let label = app.title ?? (app.isExternal ? (url.host ?? app.host) : "\(app.host).sanity.studio")
            return SplitPrimaryButton.MenuItem(id: app.id, title: label) {
                AppDelegate.shared?.openURL(url)
            }
        }
    }
}

/// Supplies a host's favicon to `content`. A favicon that's already cached
/// is read synchronously, so the first render shows it and there is no
/// state, task, or second render. Only a cache miss starts a fetch.
struct FaviconSource<Content: View>: View {
    var host: String?
    @ViewBuilder var content: (Image?) -> Content

    @State private var loaded: Image?
    @State private var loadedHost: String?

    var body: some View {
        if let host, let cached = FaviconCache.peekCached(forHost: host) {
            content(Image(nsImage: cached))
        } else {
            content(loadedHost == host ? loaded : nil)
                .task(id: host) {
                    guard let host else { return }
                    if let image = await FaviconCache.shared.favicon(forHost: host) {
                        loaded = Image(nsImage: image)
                        loadedHost = host
                    }
                }
        }
    }
}

/// Row background, hover, keyboard selection and click-to-select, kept apart
/// from the row's content. An arrow key re-runs this small body for each
/// visible row and redraws two backgrounds; the content is left untouched.
struct SelectableRow<Content: View>: View {
    @Environment(StudioStore.self) private var store
    var itemID: String
    let content: Content

    init(itemID: String, @ViewBuilder content: () -> Content) {
        self.itemID = itemID
        self.content = content()
    }

    var body: some View {
        // The selected row is only highlighted after the arrow keys move it.
        let isSelected = store.isKeyboardNavigating && store.selectedID == itemID
        RowContainer(isSelected: isSelected) { content }
            .onTapGesture { store.select(itemID) }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ProjectRowFavoriteButton: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store

    var projectID: String
    var isFavorite: Bool

    var body: some View {
        Image(systemName: isFavorite ? "pin.fill" : "pin")
            .font(.system(size: 10))
            .foregroundStyle(isFavorite ? theme.colors.star : theme.colors.faint)
            .frame(width: theme.metrics.starColumnWidth)
            .contentShape(Rectangle())
            .onTapGesture { store.toggleFavorite(projectID) }
            .help(isFavorite ? "Unpin" : "Pin")
            .accessibilityLabel(isFavorite ? "Unpin" : "Pin")
            .accessibilityAddTraits(.isButton)
    }
}

/// The row's favicon doubles as the Open Studio button. Hovering it shows an
/// arrow overlay; projects with more than one Studio URL get a count badge
/// that opens a picker (the same list is in the row's right-click menu).
struct StudioFaviconButton<Overlay: View>: View {
    @Environment(\.studioTheme) private var theme

    var row: ProjectRow
    let overlay: Overlay

    @State private var isHovered = false

    /// Matches the two text lines beside it (name line + pill line).
    static var size: CGFloat { 38 }

    init(row: ProjectRow, @ViewBuilder overlay: () -> Overlay) {
        self.row = row
        self.overlay = overlay()
    }

    var body: some View {
        let studioCount = ProjectRowChrome.studioCount(for: row)
        let size = Self.size
        FaviconSource(host: ProjectRowChrome.faviconHost(for: row)) { favicon in
            ProjectAvatar(name: row.displayTitle, brandHex: row.project.brandColorHex, favicon: favicon, size: size)
        }
        .overlay {
            if isHovered {
                let radius = theme.cornerRadius(theme.metrics.avatarCornerRadius * size / theme.metrics.avatarSize)
                RoundedRectangle(cornerRadius: radius, style: theme.cornerStyle)
                    .fill(Color.black.opacity(0.5))
                    .overlay(
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    )
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { AppDelegate.shared?.openStudio(for: row) }
        .onHover { isHovered = $0 }
        .help("Open Studio")
        .accessibilityLabel("Open Studio, \(row.displayTitle)")
        .accessibilityAddTraits(.isButton)
        .overlay { overlay }
        .overlay(alignment: .bottomTrailing) {
            if studioCount > 1 {
                NativeMenuButton(
                    header: "Studio URLs",
                    makeItems: { ProjectRowChrome.studioMenuItems(for: row) },
                    accessibilityLabel: "Choose Studio URL, \(studioCount) available",
                    labelHeight: 15
                ) {
                    Text("\(studioCount)")
                        .font(.system(size: 8.5, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(theme.colors.text)
                        .padding(.horizontal, 3.5)
                        .frame(minWidth: 15, minHeight: 15)
                        .background(Capsule().fill(theme.colors.panelFill))
                        .overlay(Capsule().fill(theme.colors.chipBackground))
                        .overlay(Capsule().strokeBorder(theme.colors.chipBorder, lineWidth: 1))
                }
                .help("Choose a Studio URL")
                .offset(x: 5, y: 5)
            }
        }
        .frame(width: size, height: size)
    }
}

/// ⌘1–9 keycap drawn over a pinned project's favicon while Command is held.
/// Only pinned rows create this view, so only they watch the Command key.
struct FavoriteShortcutLegend: View {
    @Environment(\.studioTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(StudioStore.self) private var store

    var index: Int

    var body: some View {
        let isDark = colorScheme == .dark
        let isShown = store.showFavoriteShortcutLegends
        ZStack {
            if isShown {
                KeycapLegend(
                    [.symbol("command"), .text("\(index)")],
                    compact: true,
                    foreground: isDark ? theme.colors.sub : theme.colors.text
                )
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius(4), style: theme.cornerStyle)
                        .fill(theme.colors.panelFill)
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.cornerRadius(4), style: theme.cornerStyle)
                                .fill(isDark ? Color.black.opacity(0.18) : Color.white.opacity(0.72))
                        )
                )
                .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.12), value: isShown)
    }
}

/// The project name: opens the Studio, underlined on hover. Owns its hover
/// state so hovering the name doesn't re-run the row.
struct ProjectNameLink: View {
    @Environment(\.studioTheme) private var theme
    var row: ProjectRow

    @State private var isHovered = false

    var body: some View {
        Text(row.displayTitle)
            .font(theme.typography.projectName)
            .foregroundStyle(theme.colors.text)
            .underline(isHovered)
            .lineLimit(1)
            .contentShape(Rectangle())
            .onTapGesture { AppDelegate.shared?.openStudio(for: row) }
            .onHover { isHovered = $0 }
            .accessibilityLabel("Open Studio, \(row.displayTitle)")
            .accessibilityAddTraits(.isButton)
    }
}

/// "<projectId> in <orgId>" at the end of the name line. Each id copies on
/// its own, and only the chip that was clicked shows "copied". Reading the
/// copy feedback here (not in the row) means a copy redraws just the chips.
struct ProjectIDChips: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store

    var projectID: String
    /// Shown where the row sits outside its organization's section.
    var organizationID: String?
    var itemID: String

    var body: some View {
        HStack(spacing: 4) {
            let projectKey = StudioStore.projectIDCopyKey(listItemID: itemID)
            CopyChip(
                text: projectID,
                copied: store.isShowingCopied(projectKey),
                accessibilityName: "Copy project ID \(projectID)"
            ) {
                store.copy(projectID, feedbackKey: projectKey)
            }
            if let organizationID {
                let orgKey = "item-org:\(itemID)"
                Text("in")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.colors.faint.opacity(0.6))
                    .accessibilityHidden(true)
                CopyChip(
                    text: organizationID,
                    copied: store.isShowingCopied(orgKey),
                    accessibilityName: "Copy organization ID \(organizationID)"
                ) {
                    store.copy(organizationID, feedbackKey: orgKey)
                }
            }
        }
        .fixedSize()
    }
}

/// Sizes for the recent document pills, and the arithmetic that decides how
/// many fit.
///
/// This replaces `ViewThatFits`, which built and measured three complete
/// candidate rows of pills for every project row and was the largest single
/// layout cost in the list (about a quarter of all layout time). Text widths
/// are measured once per string with the same fonts the pills use, and the
/// row's real width comes from `onGeometryChange`.
@MainActor
enum PillMetrics {
    static let maxPills = 3
    static let maxTitleLength = 26
    /// `theme.typography.meta` and `.timestamp` in both themes.
    private static let titleFont = NSFont.systemFont(ofSize: 10.5)
    private static let timeFont = NSFont.systemFont(ofSize: 10)
    private static let spacing: CGFloat = 4
    /// Horizontal padding (7 + 7), status dot (7), and the two gaps (4 + 4).
    private static let pillChrome: CGFloat = 29
    private static let moreChrome: CGFloat = 14

    /// The widest pill area any row has reported. New rows start from it, so
    /// their first layout already shows the right number of pills. (Rows
    /// with presence avatars are narrower and correct themselves once.)
    static var widestSeen: CGFloat = 374

    private static var widthCache: [String: CGFloat] = [:]

    private static func textWidth(_ text: String, font: NSFont, kind: String) -> CGFloat {
        let key = kind + text
        if let cached = widthCache[key] { return cached }
        if widthCache.count > 4000 { widthCache.removeAll(keepingCapacity: true) }
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        widthCache[key] = width
        return width
    }

    /// Truncated by hand: the pills sit in a `fixedSize` row, where `Text`
    /// would never truncate.
    static func truncatedTitle(_ title: String) -> String {
        guard title.count > maxTitleLength else { return title }
        return String(title.prefix(maxTitleLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func pillWidth(_ document: EditedDocument, now: Date) -> CGFloat {
        pillChrome
            + textWidth(truncatedTitle(document.displayTitle), font: titleFont, kind: "t")
            + textWidth(RelativeTimestamp.string(from: document.editedAt, now: now), font: timeFont, kind: "s")
    }

    /// How many leading pills (1 to 3) fit in `width`, leaving room for the
    /// "+N" pill when documents are left over. One pill always shows, even
    /// if it doesn't fit, which matches the old behavior.
    static func fittingCount(_ documents: [EditedDocument], width: CGFloat) -> Int {
        let limit = min(maxPills, documents.count)
        guard limit > 1 else { return limit }
        let now = Date()
        var widths: [CGFloat] = []
        widths.reserveCapacity(limit)
        for document in documents.prefix(limit) {
            widths.append(pillWidth(document, now: now))
        }
        var count = limit
        while count > 1 {
            var total = spacing * CGFloat(count - 1)
            for index in 0..<count { total += widths[index] }
            let rest = documents.count - count
            if rest > 0 {
                total += spacing + moreChrome + textWidth("+\(rest)", font: timeFont, kind: "s")
            }
            if total <= width { return count }
            count -= 1
        }
        return 1
    }
}

/// Up to three recent documents as pills, then a "+N" pill whose menu lists
/// the rest. Fewer pills show when the row is too narrow for three.
struct RecentDocumentPills: View {
    @Environment(\.studioTheme) private var theme

    var documents: [EditedDocument]

    @State private var availableWidth = PillMetrics.widestSeen

    private static let maxMenuItems = 15

    var body: some View {
        let shownCount = PillMetrics.fittingCount(documents, width: availableWidth)
        HStack(spacing: 4) {
            ForEach(documents.prefix(shownCount), id: \.listItemID) { document in
                DocumentPill(document: document)
            }
            if documents.count > shownCount {
                morePill(Array(documents.dropFirst(shownCount)))
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            if width > PillMetrics.widestSeen { PillMetrics.widestSeen = width }
            if width != availableWidth { availableWidth = width }
        }
    }

    private func morePill(_ rest: [EditedDocument]) -> some View {
        NativeMenuButton(
            header: "Recent documents",
            makeItems: {
                rest.prefix(Self.maxMenuItems).compactMap { document -> SplitPrimaryButton.MenuItem? in
                    guard let url = document.deepLinkURL else { return nil }
                    return SplitPrimaryButton.MenuItem(
                        id: document.listItemID,
                        title: "\(document.displayTitle)  ·  \(RelativeTimestamp.string(from: document.editedAt))",
                        image: DocumentStatusDot.menuImage(isDraft: document.isDraft)
                    ) {
                        AppDelegate.shared?.openURL(url)
                    }
                }
            },
            accessibilityLabel: "\(rest.count) more recent documents"
        ) {
            PillChrome(isHovered: false) {
                Text("+\(rest.count)")
                    .font(theme.typography.timestamp)
                    .foregroundStyle(theme.colors.faint)
            }
        }
    }
}

private struct DocumentPill: View {
    @Environment(\.studioTheme) private var theme

    var document: EditedDocument

    @State private var isHovered = false

    var body: some View {
        let edited = RelativeTimestamp.string(from: document.editedAt)
        PillChrome(isHovered: isHovered) {
            HStack(spacing: 4) {
                DocumentStatusDot(isDraft: document.isDraft)
                Text(PillMetrics.truncatedTitle(document.displayTitle))
                    .font(theme.typography.meta)
                    .foregroundStyle(isHovered ? theme.colors.text : theme.colors.sub)
                    .lineLimit(1)
                Text(edited)
                    .font(theme.typography.timestamp)
                    .foregroundStyle(theme.colors.faint)
            }
        }
        .onTapGesture {
            if let url = document.deepLinkURL {
                AppDelegate.shared?.openURL(url)
            }
        }
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Open document, \(document.displayTitle), \(document.isDraft ? "draft" : "published"), edited \(edited)")
        .accessibilityAddTraits(.isButton)
    }

    private var helpText: String {
        let state = document.isDraft ? "Draft" : "Published"
        return document.typeName.isEmpty
            ? "\(document.displayTitle) (\(state))"
            : "\(document.displayTitle) (\(document.typeName), \(state))"
    }
}

/// Studio's document status mark: a hollow yellow ring for an unpublished
/// draft, a filled green dot for published.
struct DocumentStatusDot: View {
    var isDraft: Bool

    static let draftColor = NSColor(srgbRed: 0.84, green: 0.56, blue: 0.16, alpha: 1)
    static let publishedColor = NSColor(srgbRed: 0.27, green: 0.70, blue: 0.47, alpha: 1)
    private static let draftFill = Color(nsColor: draftColor)
    private static let publishedFill = Color(nsColor: publishedColor)
    private static let diameter: CGFloat = 7

    var body: some View {
        Group {
            if isDraft {
                Circle().strokeBorder(Self.draftFill, lineWidth: 1.5)
            } else {
                Circle().fill(Self.publishedFill)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityHidden(true)
    }

    /// The same mark as an `NSImage`, for native menus.
    static func menuImage(isDraft: Bool) -> NSImage {
        NSImage(size: NSSize(width: 9, height: 9), flipped: false) { rect in
            let inset = rect.insetBy(dx: 1, dy: 1)
            if isDraft {
                draftColor.setStroke()
                let path = NSBezierPath(ovalIn: inset.insetBy(dx: 0.75, dy: 0.75))
                path.lineWidth = 1.5
                path.stroke()
            } else {
                publishedColor.setFill()
                NSBezierPath(ovalIn: inset).fill()
            }
            return true
        }
    }
}

private struct PillChrome<Content: View>: View {
    @Environment(\.studioTheme) private var theme
    var isHovered: Bool
    let content: Content

    init(isHovered: Bool, @ViewBuilder content: () -> Content) {
        self.isHovered = isHovered
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(
                Capsule().fill(isHovered ? theme.colors.hover : theme.colors.chipBackground)
            )
            .overlay(Capsule().strokeBorder(theme.colors.chipBorder, lineWidth: 1))
            .contentShape(Capsule())
    }
}

/// Live editors on a project.
struct ProjectPresenceStack: View {
    @Environment(StudioStore.self) private var store
    var projectID: String

    var body: some View {
        let members = store.presenceSlice(for: projectID).members
        AvatarStack(
            items: members.map { member in
                AvatarStack.Item(
                    id: member.id,
                    name: member.displayName,
                    initials: member.initials,
                    color: PresenceSwatch.color(for: member.id),
                    imageURL: member.imageURL,
                    deepLinkURL: member.deepLinkURL
                )
            },
            onSelect: { item in
                if let url = item.deepLinkURL {
                    AppDelegate.shared?.openURL(url)
                }
            }
        )
    }
}

/// Site and Sanity Dashboard links as bare icons: faint, full text color on
/// hover.
struct ProjectLinkButtons: View {
    var row: ProjectRow
    var showsSite = true
    var showsManage = true

    var body: some View {
        HStack(spacing: 2) {
            if showsSite, let site = row.curation.primaryFrontendURL {
                PlainIconLink(image: Image(systemName: "globe"), size: 11, label: "Open site") {
                    AppDelegate.shared?.openURL(site)
                }
            }
            if showsManage, let manage = row.project.manageURL {
                PlainIconLink(image: Image("SanityDashboard"), size: 15, label: "Manage project") {
                    AppDelegate.shared?.openURL(manage)
                }
            }
        }
        .fixedSize()
    }
}

private struct PlainIconLink: View {
    @Environment(\.studioTheme) private var theme
    var image: Image
    var size: CGFloat
    var label: String
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        image
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(isHovered ? theme.colors.text : theme.colors.faint)
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { isHovered = $0 }
            .help(label)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
    }
}

/// The project's Sanity plan ("Free", "Growth", "Enterprise", …) as small
/// text, tinted by plan type. The full plan name is in the tooltip.
struct PlanBadge: View {
    @Environment(\.studioTheme) private var theme
    var plan: ProjectPlan

    private static let enterpriseTint = Color(red: 0.62, green: 0.45, blue: 0.95)
    private static let trialTint = Color(red: 0.85, green: 0.58, blue: 0.20)
    private static let paidTint = Color(red: 0.25, green: 0.55, blue: 0.98)

    var body: some View {
        Text(plan.shortName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Self.tint(for: plan) ?? theme.colors.faint)
            .lineLimit(1)
            .fixedSize()
            .help("\(plan.name) plan")
            .accessibilityLabel("\(plan.name) plan")
    }

    /// Free and legacy plans stay neutral; paid tiers get a color.
    private static func tint(for plan: ProjectPlan) -> Color? {
        let type = plan.typeID.lowercased()
        let name = plan.name.lowercased()
        if type.contains("enterprise") || name.hasPrefix("enterprise") {
            return enterpriseTint
        }
        if name.contains("trial") {
            return trialTint
        }
        if type.contains("growth") || name.hasPrefix("growth") || type.contains("team") || type.contains("business") {
            return paidTint
        }
        return nil
    }
}

/// Trailing links for document search rows: shown while the row is hovered
/// or is the keyboard selection.
struct DocumentRowLinks: View {
    @Environment(StudioStore.self) private var store
    var row: ProjectRow
    var itemID: String
    var isHovered: Bool

    var body: some View {
        let isRevealed = isHovered || (store.isKeyboardNavigating && store.selectedID == itemID)
        ProjectLinkButtons(row: row)
            .opacity(isRevealed ? 1 : 0)
            .allowsHitTesting(isRevealed)
            .accessibilityHidden(!isRevealed)
    }
}

/// A project row's right-click menu. A separate view so its body, which
/// asks the store about pin order, only runs when the menu opens and not on
/// every row redraw.
struct ProjectContextMenu: View {
    @Environment(StudioStore.self) private var store
    var row: ProjectRow
    var listItemID: String

    var body: some View {
        Button("Open Studio") {
            AppDelegate.shared?.openStudio(for: row)
        }
        let studios = ProjectRowChrome.studioMenuItems(for: row)
        if studios.count > 1 {
            Menu("Open Studio URL") {
                ForEach(studios) { item in
                    Button(item.title, action: item.action)
                }
            }
        }
        if let site = row.curation.primaryFrontendURL {
            Button("Open Site") {
                AppDelegate.shared?.openURL(site)
            }
        }
        if let manage = row.project.manageURL {
            Button("Manage Project") {
                AppDelegate.shared?.openURL(manage)
            }
        }
        Button("Copy Project ID") {
            store.copy(row.project.id, feedbackKey: StudioStore.projectIDCopyKey(listItemID: listItemID))
        }
        Divider()
        Button(row.curation.isFavorite ? "Unpin" : "Pin") {
            store.toggleFavorite(row.id)
        }
        if row.curation.isFavorite {
            Button {
                store.movePinnedProject(row.id, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up").labelStyle(.titleAndIcon)
            }
            .disabled(!store.canMovePinnedProject(row.id, by: -1))
            Button {
                store.movePinnedProject(row.id, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down").labelStyle(.titleAndIcon)
            }
            .disabled(!store.canMovePinnedProject(row.id, by: 1))
        }
        Divider()
        Button("Hide Project", systemImage: "eye.slash") {
            store.setProjectHidden(row.id, hidden: true)
        }
    }
}
