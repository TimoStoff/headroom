import AppKit
import SwiftUI

final class HoverModel: ObservableObject {
    @Published var kind: SegmentKind = .cpu
    @Published var consumers: [Consumer] = []
}

/// Small floating panel under the menu bar showing top consumers (or plan limits) for the hovered item.
final class HoverController: NSResponder {
    private let store: Store
    private let sampler = ConsumerSampler()
    private let model = HoverModel()
    private weak var button: NSStatusBarButton?
    private var panel: NSPanel?
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    private var current: SegmentKind?
    var suppressed: () -> Bool = { false }
    private var monitors: [Any] = []

    init(store: Store, button: NSStatusBarButton) {
        self.store = store
        self.button = button
        super.init()
        // Status items can be hosted outside the app on recent macOS, where tracking areas inside the
        // button never fire. Mouse-move monitors (no permission needed) plus a frame hit test work everywhere.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in self?.update() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] e in self?.update(); return e }) {
            monitors.append(m)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { monitors.forEach(NSEvent.removeMonitor) }

    private func update() {
        guard let button, let window = button.window, let image = button.image else { return }
        let mouse = NSEvent.mouseLocation
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard frame.contains(mouse), !suppressed() else {
            if current != nil { hide() }
            return
        }
        let x = mouse.x - frame.minX - (frame.width - image.size.width) / 2
        let kind = StatusRenderer.lastSegments.first { $0.range.contains(x) }?.kind
        guard kind != current else { return }
        current = kind
        pending?.cancel()
        guard let kind else { hidePanel(); return }
        let work = DispatchWorkItem { [weak self] in self?.show(kind) }
        pending = work
        // Short dwell so sweeping across the bar does not flash panels.
        DispatchQueue.main.asyncAfter(deadline: .now() + (panel?.isVisible == true ? 0.05 : 0.35), execute: work)
    }

    func hide() {
        pending?.cancel()
        current = nil
        hidePanel()
    }

    private func hidePanel() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        // Drop the SwiftUI tree so a hidden panel does not keep re-rendering on every Store update.
        panel?.contentView = nil
    }

    private func show(_ kind: SegmentKind) {
        model.kind = kind
        sampler.reset()
        model.consumers = sampler.top(kind)
        timer?.invalidate()
        if [.cpu, .gpu, .battery, .memory].contains(kind) {
            // First rate sample after 0.5s, then refresh every second while visible.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.current == kind else { return }
                self.model.consumers = self.sampler.top(kind)
            }
            timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.model.consumers = self.sampler.top(kind)
            }
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.contentView == nil {
            let host = NSHostingView(rootView: HoverView(model: model, store: store))
            host.sizingOptions = .preferredContentSize
            panel.contentView = host
        }
        position(panel, for: kind)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 100),
                        styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .transient]
        return p
    }

    private func position(_ panel: NSPanel, for kind: SegmentKind) {
        guard let button, let window = button.window, let image = button.image,
              let range = StatusRenderer.lastSegments.first(where: { $0.kind == kind })?.range else { return }
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? NSSize(width: 240, height: 120)
        let originX = (button.bounds.width - image.size.width) / 2 + range.lowerBound
        let inWindow = button.convert(NSPoint(x: originX, y: 0), to: nil)
        let screenPoint = window.convertPoint(toScreen: inWindow)
        let screen = window.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let x = min(max(screenPoint.x - 8, screen.minX + 6), screen.maxX - size.width - 6)
        panel.setFrame(NSRect(x: x, y: window.frame.minY - size.height - 6, width: size.width, height: size.height), display: true)
    }
}

struct HoverView: View {
    @ObservedObject var model: HoverModel
    @ObservedObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(0.5).foregroundStyle(.secondary)
            switch model.kind {
            case .claude: limits(store.claudeLimits?.all ?? [], error: store.claudeError)
            case .grok:
                if let g = store.grokPlan {
                    limits([LimitEntry(id: "g", name: "Credits used", percent: g.percent, resetsAt: g.periodEnd)], error: nil)
                } else {
                    Text(store.grokError ?? "Loading").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            default: consumers
            }
        }
        .padding(10)
        .frame(width: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
    }

    private var title: String {
        switch model.kind {
        case .cpu: return "TOP CPU"
        case .gpu: return "TOP GPU"
        case .memory: return "TOP MEMORY"
        case .battery: return "ENERGY SHARE"
        case .claude: return "CLAUDE LIMITS"
        case .grok: return "GROK CREDITS"
        }
    }

    @ViewBuilder private var consumers: some View {
        if model.consumers.isEmpty {
            Text("Sampling...").font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            let maxValue = model.consumers.map(\.value).max() ?? 1
            ForEach(model.consumers) { c in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(c.name).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(c.label).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                    GeometryReader { g in
                        Capsule().fill(Color.primary.opacity(0.35))
                            .frame(width: max(2, g.size.width * c.value / max(maxValue, 0.0001)))
                    }
                    .frame(height: 2)
                }
            }
        }
    }

    private func limits(_ entries: [LimitEntry], error: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entries) { e in
                HStack {
                    Text(e.name)
                    Spacer()
                    Text(Fmt.pct(e.percent)).monospacedDigit().fontWeight(.semibold)
                    Text(Fmt.until(e.resetsAt)).monospacedDigit().foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                }
                .font(.system(size: 11))
            }
            if let error { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
        }
    }
}
