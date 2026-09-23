import SwiftUI
import UIKit

/// Pinch-to-zoom; default scale fits the full image inside the view bounds.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage
    /// Bumps `updateUIView` when the same bitmap is reloaded as a new `UIImage` instance.
    var contentKey: String = ""
    var maximumZoomFactor: CGFloat = 8

    func makeUIView(context: Context) -> ZoomableScrollView {
        let view = ZoomableScrollView()
        view.apply(image: image, contentKey: contentKey, maximumZoomFactor: maximumZoomFactor)
        return view
    }

    func updateUIView(_ uiView: ZoomableScrollView, context: Context) {
        uiView.apply(image: image, contentKey: contentKey, maximumZoomFactor: maximumZoomFactor)
    }
}

final class ZoomableScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()
    private var contentKey: String = ""
    private var maximumZoomFactor: CGFloat = 8
    private var userAdjustedZoom = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .black
        showsHorizontalScrollIndicator = true
        showsVerticalScrollIndicator = true
        bouncesZoom = true
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(image: UIImage, contentKey: String, maximumZoomFactor: CGFloat) {
        let key = "\(contentKey)|\(image.size.width)x\(image.size.height)"
        let imageChanged = self.contentKey != key
        self.contentKey = key
        self.maximumZoomFactor = maximumZoomFactor
        if imageChanged {
            userAdjustedZoom = false
            imageView.image = image
            imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
            setNeedsLayout()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        zoomToFitIfNeeded()
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        userAdjustedZoom = abs(zoomScale - minimumZoomScale) > 0.02
        centerImage()
    }

    private func zoomToFitIfNeeded() {
        guard let image = imageView.image else { return }
        let boundsSize = bounds.size
        guard boundsSize.width > 1, boundsSize.height > 1 else { return }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let fitScale = min(boundsSize.width / imageSize.width, boundsSize.height / imageSize.height)
        minimumZoomScale = fitScale
        maximumZoomScale = max(fitScale * maximumZoomFactor, fitScale * 1.01)

        if !userAdjustedZoom {
            zoomScale = fitScale
        } else if zoomScale < minimumZoomScale {
            zoomScale = minimumZoomScale
        } else if zoomScale > maximumZoomScale {
            zoomScale = maximumZoomScale
        }
    }

    private func centerImage() {
        let boundsSize = bounds.size
        var frameToCenter = imageView.frame
        if frameToCenter.size.width < boundsSize.width {
            frameToCenter.origin.x = (boundsSize.width - frameToCenter.size.width) / 2
        } else {
            frameToCenter.origin.x = 0
        }
        if frameToCenter.size.height < boundsSize.height {
            frameToCenter.origin.y = (boundsSize.height - frameToCenter.size.height) / 2
        } else {
            frameToCenter.origin.y = 0
        }
        imageView.frame = frameToCenter
    }
}
