import SwiftUI
import UIKit

struct StreamPreviewView: UIViewRepresentable {
    let receiver: GStreamerWhipReceiver
    let detections: [ScanFinding]

    func makeUIView(context: Context) -> StreamPreviewContainer {
        let view = StreamPreviewContainer()
        view.embed(receiver.videoView)
        return view
    }

    func updateUIView(_ uiView: StreamPreviewContainer, context: Context) {
        uiView.embed(receiver.videoView)
        uiView.updateOverlays(detections)
    }
}

final class StreamPreviewContainer: UIView {
    private let overlayLayer = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        overlayLayer.strokeColor = UIColor.systemGreen.cgColor
        overlayLayer.fillColor = UIColor.clear.cgColor
        overlayLayer.lineWidth = 2
        layer.addSublayer(overlayLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private weak var embeddedChild: UIView?

    func embed(_ child: UIView) {
        if embeddedChild !== child {
            embeddedChild?.removeFromSuperview()
            embeddedChild = child
            child.frame = bounds
            child.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            insertSubview(child, at: 0)
        }
        child.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        embeddedChild?.frame = bounds
        overlayLayer.frame = bounds
    }

    func updateOverlays(_ detections: [ScanFinding]) {
        let path = UIBezierPath()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else {
            overlayLayer.path = nil
            return
        }

        for detection in detections {
            guard let box = detection.boundingBox else { continue }
            // Vision: origin bottom-left → UIKit top-left, aspect-fit inside bounds.
            let videoAspect = 16.0 / 9.0
            let viewAspect = size.width / size.height
            var drawRect = CGRect.zero
            if viewAspect > videoAspect {
                let drawHeight = size.height
                let drawWidth = drawHeight * videoAspect
                let xOffset = (size.width - drawWidth) / 2
                drawRect = CGRect(x: xOffset, y: 0, width: drawWidth, height: drawHeight)
            } else {
                let drawWidth = size.width
                let drawHeight = drawWidth / videoAspect
                let yOffset = (size.height - drawHeight) / 2
                drawRect = CGRect(x: 0, y: yOffset, width: drawWidth, height: drawHeight)
            }

            let x = drawRect.minX + box.minX * drawRect.width
            let y = drawRect.maxY - (box.minY + box.height) * drawRect.height
            let width = box.width * drawRect.width
            let height = box.height * drawRect.height
            path.append(UIBezierPath(rect: CGRect(x: x, y: y, width: width, height: height)))
        }

        overlayLayer.path = path.cgPath
    }
}
