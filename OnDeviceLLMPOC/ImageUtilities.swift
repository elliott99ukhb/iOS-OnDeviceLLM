import UIKit
import CoreImage

extension UIImage {
    /// A `CGImage` suitable for handing to the model. Most picked photos are
    /// already CGImage-backed; if not (e.g. a filter output), render the
    /// `CIImage` into one.
    var modelCGImage: CGImage? {
        if let cgImage { return cgImage }
        if let ciImage {
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        }
        return nil
    }

    /// Proportionally shrinks the image so its longest side is at most
    /// `maxDimension`. Keeps attachments small enough to stay fast and within
    /// the model's input limits. Returns `self` if already small enough.
    func downscaled(maxDimension: CGFloat = 1024) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
