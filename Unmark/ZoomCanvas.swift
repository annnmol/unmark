import SwiftUI
import AppKit

struct ImageCanvas: View {
    let item: ImageItem
    let showOriginal: Bool
    let enabled: Bool
    let onZoom: (CGFloat) -> Void
    let onSelect: (CGRect) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZoomViewport(zoom: item.zoom, viewport: geometry.size, onZoom: onZoom) {
                CanvasContent(item: item, showOriginal: showOriginal, enabled: enabled, onSelect: onSelect)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .clipped()
        .id(item.id)
    }
}

private struct CanvasContent: View {
    let item: ImageItem
    let showOriginal: Bool
    let enabled: Bool
    let onSelect: (CGRect) -> Void
    @State private var drawing: CGRect?
    @State private var selectionVisible = true

    private var showingResult: Bool { item.resultImage != nil && !showOriginal }
    private var canEdit: Bool { enabled && !(showOriginal && item.result != nil) }
    private var normalizedBox: CGRect? {
        if item.mode == "Custom" { return item.region }
        let size = item.image.size
        let k = min(size.width, size.height) / 1536
        let offset: CGFloat = item.mode == "Large" ? 256 : 146
        let offsetY: CGFloat = item.mode == "Large" ? 257 : 146
        let side: CGFloat = item.mode == "Large" ? 124 : 66
        return CGRect(x: 1 - offset * k / size.width, y: 1 - offsetY * k / size.height, width: side * k / size.width, height: side * k / size.height)
    }

    var body: some View {
        GeometryReader { geometry in
            let size = item.image.size
            let scale = min(max(1, geometry.size.width - 48) / size.width, max(1, geometry.size.height - 48) / size.height)
            let fitted = CGSize(width: size.width * scale, height: size.height * scale)
            ZStack(alignment: .topLeading) {
                Image(nsImage: showingResult ? (item.resultImage ?? item.image) : item.image)
                    .resizable().frame(width: fitted.width, height: fitted.height)
                if canEdit, selectionVisible, let box = drawing ?? normalizedBox {
                    Rectangle().fill(Color.mint.opacity(0.12))
                        .overlay { Rectangle().stroke(Color.mint, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])) }
                        .frame(width: box.width * fitted.width, height: box.height * fitted.height)
                        .offset(x: box.minX * fitted.width, y: box.minY * fitted.height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: fitted.width, height: fitted.height)
            .contentShape(Rectangle())
            .onTapGesture { selectionVisible = true }
            // AppKit magnifies the entire document. Gesture locations remain in the
            // unscaled image view, so selections stay accurate at every zoom level.
            .gesture(DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard item.mode == "Custom", canEdit else { return }
                    selectionVisible = true
                    drawing = rect(value, size: fitted)
                }
                .onEnded { value in
                    guard item.mode == "Custom", canEdit else { drawing = nil; return }
                    let box = rect(value, size: fitted)
                    drawing = nil
                    if box.width * fitted.width >= 4 && box.height * fitted.height >= 4 { onSelect(box) }
                })
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .background {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectionVisible = false
                        drawing = nil
                    }
            }
        }
        .onChange(of: item.mode) {
            drawing = nil
            selectionVisible = true
        }
        .onChange(of: item.region) { selectionVisible = true }
    }

    private func rect(_ value: DragGesture.Value, size: CGSize) -> CGRect {
        let x1 = min(1, max(0, value.startLocation.x / size.width))
        let y1 = min(1, max(0, value.startLocation.y / size.height))
        let x2 = min(1, max(0, value.location.x / size.width))
        let y2 = min(1, max(0, value.location.y / size.height))
        return CGRect(x: min(x1, x2), y: min(y1, y2), width: abs(x2 - x1), height: abs(y2 - y1))
    }
}

private struct ZoomViewport<Content: View>: NSViewRepresentable {
    let zoom: CGFloat
    let viewport: CGSize
    let onZoom: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> CanvasScrollView {
        let scroll = CanvasScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.allowsMagnification = true
        scroll.minMagnification = 1
        scroll.maxMagnification = 8
        let host = NSHostingView(rootView: content())
        host.sizingOptions = []
        scroll.documentView = host
        return scroll
    }

    func updateNSView(_ scroll: CanvasScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<Content> else { return }
        scroll.onZoom = onZoom
        host.rootView = content()
        host.setFrameSize(NSSize(width: max(1, viewport.width), height: max(1, viewport.height)))
        if abs(scroll.magnification - zoom) > 0.001 {
            let center = CGPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
            scroll.setMagnification(zoom, centeredAt: center)
        }
    }
}

private final class CanvasScrollView: NSScrollView {
    var onZoom: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 0.12
        let next = min(maxMagnification, max(minMagnification, magnification * exp(event.scrollingDeltaY * sensitivity)))
        let anchor = documentView?.convert(event.locationInWindow, from: nil) ?? .zero
        setMagnification(next, centeredAt: anchor)
        onZoom?(magnification)
    }

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        onZoom?(magnification)
    }
}
