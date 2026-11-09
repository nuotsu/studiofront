#if BENCHMARK
import AppKit
import StudioStore
import SwiftUI

/// Scripted popover benchmark, compiled only with the `BENCHMARK` flag:
///
///     xcodebuild … -configuration Release \
///         SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) BENCHMARK'
///     open -n -W --stdout out.txt Studiofront.app --args --benchmark
///
/// Hosts the real popover view off-screen, drives the store through typing,
/// arrow keys, scrolling, grouping, presence and refresh steps, and prints
/// the main-thread time each step costs. `--benchmark-synthetic=N` swaps the
/// cached account for N generated projects (no network, letter avatars).
@MainActor
enum PerformanceBenchmark {
    static var isRequested: Bool {
        CommandLine.arguments.contains { $0.hasPrefix("--benchmark") }
    }

    private static var syntheticCount: Int? {
        for argument in CommandLine.arguments {
            if let value = argument.split(separator: "=").last, argument.hasPrefix("--benchmark-synthetic="),
               let count = Int(value)
            {
                return count
            }
        }
        return nil
    }

    static func run(delegate: AppDelegate) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            if let count = syntheticCount {
                let fixture = syntheticFixture(count: count)
                delegate.store.replaceRows(fixture.rows, organizations: fixture.organizations)
                emit("fixture\tsynthetic\t\(count) projects")
            } else {
                await delegate.auth.restoreOnLaunch()
                await delegate.sync.loadCache()
                emit("fixture\tcache\t\(delegate.store.rows.count) projects")
            }
            await runScenarios(delegate: delegate)
            fflush(stdout)
            exit(0)
        }
    }

    /// Experiment switches: `--perf=nopills,nomenu,…` turns parts of a row
    /// off so their cost can be measured by difference.
    private static let perfFlags: Set<String> = {
        for argument in CommandLine.arguments where argument.hasPrefix("--perf=") {
            return Set(argument.dropFirst("--perf=".count).split(separator: ",").map(String.init))
        }
        return []
    }()

    static func flag(_ name: String) -> Bool {
        perfFlags.contains(name)
    }

    /// Row bodies evaluated since the last step, to show how many rows a
    /// step built or rebuilt.
    private static var rowBodies = 0

    static func countRowBody() {
        rowBodies += 1
    }

    /// With `--snapshots`, prints a PNG of the off-screen view (base64) so
    /// layout changes can be compared before and after.
    private static func snapshot(_ view: NSView?, name: String) {
        guard CommandLine.arguments.contains("--snapshots"), let view,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        print("SNAP\t\(name)\t\(data.base64EncodedString())")
    }

    /// With `--snapshots`, rows report their sizes once so fixed heights can
    /// be checked against what the content naturally measures.
    static func reportRowSize(_ kind: String, _ size: CGSize) {
        guard CommandLine.arguments.contains("--snapshots") else { return }
        print("ROWSIZE\t\(kind)\t\(size.width)\t\(size.height)")
    }

    private static func emit(_ line: String) {
        print("BENCH\t\(line)")
    }

    // MARK: - Main-thread busy time

    /// Total time the main run loop spent awake (closed busy periods only).
    private static var busyTotal: CFAbsoluteTime = 0
    private static var busyStart: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()

    private static func installBusyObserver() {
        let observer = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            0
        ) { _, activity in
            MainActor.assumeIsolated {
                if activity == .afterWaiting {
                    busyStart = CFAbsoluteTimeGetCurrent()
                } else {
                    busyTotal += CFAbsoluteTimeGetCurrent() - busyStart
                }
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    // MARK: - Scenarios

    private static func runScenarios(delegate: AppDelegate) async {
        let store = delegate.store
        let metrics = delegate.settings.themePreference.theme.metrics
        let size = NSSize(width: metrics.popoverWidth, height: metrics.popoverContentHeight)

        installBusyObserver()
        NSApp.appearance = delegate.settings.appearancePreference.nsAppearance

        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -30000, y: -30000), size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        var hosting: NSHostingView<AnyView>!

        /// Runs `action`, forces layout and display, lets follow-up work
        /// settle, and reports `sync` (action through display) and `total`
        /// (all main-thread time until things went idle).
        func step(_ label: String, settle: Duration = .milliseconds(120), _ action: () -> Void) async {
            let base = busyTotal
            rowBodies = 0
            let start = CFAbsoluteTimeGetCurrent()
            action()
            let afterAction = CFAbsoluteTimeGetCurrent()
            hosting?.layoutSubtreeIfNeeded()
            let afterLayout = CFAbsoluteTimeGetCurrent()
            if !flag("nodisplay") {
                hosting?.displayIfNeeded()
                CATransaction.flush()
            }
            let sync = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let storeMS = (afterAction - start) * 1000
            let layoutMS = (afterLayout - afterAction) * 1000
            try? await Task.sleep(for: settle)
            let total = (busyTotal - base) * 1000
            emit(String(format: "%@\t%.2f\t%.2f\trows=%d\tstore=%.2f\tlayout=%.2f", label, sync, max(total, sync), rowBodies, storeMS, layoutMS))
        }

        await step("mount", settle: .milliseconds(1500)) {
            let root = PopoverRootView()
                .environment(store)
                .environment(delegate.settings)
                .environment(delegate.auth)
            hosting = NSHostingView(rootView: AnyView(root))
            hosting.frame = NSRect(origin: .zero, size: size)
            window.contentView = hosting
            window.orderFrontRegardless()
        }
        snapshot(hosting, name: "browse")

        // Typing: a project-name prefix, then a common document word.
        let nameQuery = String((store.rows.first?.displayTitle ?? "sanity").lowercased().prefix(5))
        for query in [nameQuery, "home"] {
            var typed = ""
            for character in query {
                typed.append(character)
                let value = typed
                await step("type \"\(value)\"") { store.query = value }
                if typed.count == 2 || typed == query { snapshot(hosting, name: "search-\(value)") }
            }
            while !typed.isEmpty {
                typed.removeLast()
                let value = typed
                await step("delete to \"\(value)\"") { store.query = value }
            }
        }

        for index in 1...12 {
            await step("arrow down \(index)") { store.selectNext() }
        }
        for index in 1...4 {
            await step("arrow up \(index)") { store.selectPrevious() }
        }
        await step("click row") { store.select(store.flatVisibleIDs.first ?? "") }

        if let scrollView = largestScrollView(in: hosting) {
            let clip = scrollView.contentView
            let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
            var offset: CGFloat = 0
            var index = 0
            while offset < maxY, index < 24 {
                offset = min(maxY, offset + 220)
                index += 1
                let target = offset
                await step("scroll \(index)", settle: .milliseconds(60)) {
                    clip.scroll(to: NSPoint(x: 0, y: target))
                    scrollView.reflectScrolledClipView(clip)
                }
            }
            await step("scroll to top") {
                clip.scroll(to: .zero)
                scrollView.reflectScrolledClipView(clip)
            }
        } else {
            emit("scroll\tskipped\tno scroll view found")
        }

        await step("group by date") { store.groupBy = .lastEdited }
        snapshot(hosting, name: "date")
        await step("group by org") { store.groupBy = .organization }

        if let organizationID = store.organizations.first?.id {
            await step("isolate org") { store.revealedOrganizationID = organizationID }
            await step("exit isolation") { store.isolation = nil }
        }

        let presenceIDs = Array(store.browseRows.prefix(6).map(\.id))
        let members = [
            Member(id: "bench-1", displayName: "Ada Lovelace"),
            Member(id: "bench-2", displayName: "Grace Hopper"),
        ]
        await step("presence on (6 projects)") {
            for id in presenceIDs { store.setActiveUsers(members, forProjectID: id) }
        }
        await step("presence off") {
            for id in presenceIDs { store.setActiveUsers([], forProjectID: id) }
        }

        await step("refresh, nothing changed") {
            store.replaceRows(store.rows, organizations: store.organizations)
        }
    }

    private static func largestScrollView(in view: NSView) -> NSScrollView? {
        var best: NSScrollView?
        func visit(_ view: NSView) {
            if let scrollView = view as? NSScrollView {
                let area: CGFloat = scrollView.frame.width * scrollView.frame.height
                let bestArea: CGFloat = best.map { $0.frame.width * $0.frame.height } ?? 0
                if area > bestArea { best = scrollView }
            }
            view.subviews.forEach(visit)
        }
        visit(view)
        return best
    }

    // MARK: - Synthetic fixture

    private static func syntheticFixture(count: Int) -> (rows: [ProjectRow], organizations: [OrganizationRecord]) {
        let words = ["Home", "About", "Pricing", "Blog", "Contact", "Careers", "Press", "Docs", "Changelog", "Team"]
        let now = Date()
        let organizationCount = max(1, count / 6)
        var organizations: [OrganizationRecord] = []
        for index in 0..<organizationCount {
            organizations.append(OrganizationRecord(id: "org\(index)", name: "Organization \(index)", isFavorite: index < 2))
        }
        var rows: [ProjectRow] = []
        for index in 0..<count {
            let id = "proj\(index)"
            var documents: [EditedDocument] = []
            for doc in 0..<20 {
                let isDraft = doc % 4 == 0
                let documentID: String = isDraft ? "drafts.\(id)-\(doc)" : "\(id)-\(doc)"
                let word: String = words[(index + doc) % words.count]
                let typeName: String = doc % 3 == 0 ? "post" : "page"
                let age: TimeInterval = Double(index * 3600 + doc * 420)
                documents.append(EditedDocument(
                    id: documentID,
                    title: "\(word) \(doc)",
                    typeName: typeName,
                    editedAt: now.addingTimeInterval(-age),
                    deepLinkURL: URL(string: "https://example.com/\(id)/\(doc)")
                ))
            }
            let organization = organizations[index % organizationCount]
            var studioApps: [StudioApp] = []
            if index % 5 == 0 {
                studioApps = [StudioApp(host: "one-\(id)", isExternal: false), StudioApp(host: "two-\(id)", isExternal: false)]
            }
            let isGrowth = index % 7 == 0
            let plan = ProjectPlan(name: isGrowth ? "Growth" : "Free", typeID: isGrowth ? "growth" : "free")
            let name: String = "\(words[index % words.count]) Project \(index)"
            let project = SanityProject(
                id: id,
                displayName: name,
                organizationId: organization.id,
                organizationName: organization.name,
                datasets: [Dataset(name: "production")],
                studioApps: studioApps,
                plan: plan
            )
            rows.append(ProjectRow(
                project: project,
                curation: ProjectCuration(projectId: id, isFavorite: index % 10 == 0),
                activity: ProjectActivity(lastEditedDocument: documents.first, recentDocuments: documents)
            ))
        }
        return (rows, organizations)
    }
}
#endif
