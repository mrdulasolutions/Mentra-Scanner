import SwiftUI

/// Dashed label guide / tracked ROI on top of the 16:9 camera preview.
struct LabelGuideOverlay: View {
    /// Vision normalized rect (bottom-left origin).
    let normalizedROI: CGRect
    var tracksContent: Bool = false
    var videoAspect: CGFloat = 16 / 9

    var body: some View {
        GeometryReader { geo in
            let drawRect = aspectFitVideoRect(in: geo.size, videoAspect: videoAspect)
            let path = roiPath(in: drawRect, roi: normalizedROI)
            ZStack {
                path
                    .stroke(
                        tracksContent ? Color.green.opacity(0.95) : Color.yellow.opacity(0.85),
                        style: StrokeStyle(lineWidth: tracksContent ? 2.5 : 2, dash: tracksContent ? [] : [8, 6])
                    )
                path
                    .fill((tracksContent ? Color.green : Color.yellow).opacity(0.08))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func roiPath(in drawRect: CGRect, roi: CGRect) -> Path {
        var path = Path()
        let x = drawRect.minX + roi.minX * drawRect.width
        let y = drawRect.maxY - (roi.minY + roi.height) * drawRect.height
        let width = roi.width * drawRect.width
        let height = roi.height * drawRect.height
        path.addRect(CGRect(x: x, y: y, width: width, height: height))
        return path
    }

    private func aspectFitVideoRect(in size: CGSize, videoAspect: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let viewAspect = size.width / size.height
        if viewAspect > videoAspect {
            let drawHeight = size.height
            let drawWidth = drawHeight * videoAspect
            let xOffset = (size.width - drawWidth) / 2
            return CGRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
        }
        let drawWidth = size.width
        let drawHeight = drawWidth / videoAspect
        let yOffset = (size.height - drawHeight) / 2
        return CGRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
    }
}

/// ROI overlay on a still capture (unit aspect from image).
struct CaptureLabelROIOverlay: View {
    let normalizedROI: CGRect
    let imageSize: CGSize

    var body: some View {
        GeometryReader { geo in
            let drawRect = aspectFitRect(contentSize: imageSize, in: geo.size)
            let x = drawRect.minX + normalizedROI.minX * drawRect.width
            let y = drawRect.maxY - (normalizedROI.minY + normalizedROI.height) * drawRect.height
            let width = normalizedROI.width * drawRect.width
            let height = normalizedROI.height * drawRect.height
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.cyan.opacity(0.9), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.cyan.opacity(0.06))
                )
                .frame(width: width, height: height)
                .position(x: x + width / 2, y: y + height / 2)
        }
        .allowsHitTesting(false)
    }

    private func aspectFitRect(contentSize: CGSize, in bounds: CGSize) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return .zero }
        let scale = min(bounds.width / contentSize.width, bounds.height / contentSize.height)
        let w = contentSize.width * scale
        let h = contentSize.height * scale
        return CGRect(
            x: (bounds.width - w) / 2,
            y: (bounds.height - h) / 2,
            width: w,
            height: h
        )
    }
}
