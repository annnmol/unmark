import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

nonisolated struct ImageOutputFormat {
    let fileExtension: String
    let type: UTType
    var fallbackReason: String?
}

nonisolated enum ImageFormats {
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "tif", "tiff", "bmp", "heic", "webp"]

    static let maximumFileBytes = 10_000_000
    static let maximumPixels = 25_000_000

    static func validateImport(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= maximumFileBytes else {
            throw CleanupFailure(message: "Each image must be 10 MB or smaller.")
        }
        guard supportedExtensions.contains(url.pathExtension.lowercased()),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else {
            throw CleanupFailure(message: "Choose a supported still image.")
        }
        guard width <= maximumPixels / height else {
            throw CleanupFailure(message: "Images must be 25 megapixels or smaller to keep memory use bounded.")
        }
    }

    static func output(original: URL, preference: String) -> ImageOutputFormat {
        guard preference == "original" else { return ImageOutputFormat(fileExtension: "png", type: .png) }
        let ext = original.pathExtension.lowercased()
        let type: UTType?
        switch ext {
        case "png": type = .png
        case "jpg", "jpeg": type = .jpeg
        case "tif", "tiff": type = .tiff
        case "bmp": type = .bmp
        case "heic": type = .heic
        case "webp": type = .webP
        default: type = nil
        }
        let writable = CGImageDestinationCopyTypeIdentifiers() as? [String] ?? []
        if let type, writable.contains(type.identifier) {
            return ImageOutputFormat(fileExtension: ext, type: type)
        }
        return ImageOutputFormat(fileExtension: "png", type: .png,
                                 fallbackReason: "\(ext.uppercased()) export is unavailable on this Mac; those images were saved as PNG.")
    }

    static func encodedData(from png: URL, format: ImageOutputFormat) throws -> Data {
        if format.type == .png { return try Data(contentsOf: png) }
        guard let source = CGImageSourceCreateWithURL(png as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CleanupFailure(message: "Could not read the cleaned image for export.")
        }
        return try encode(image, type: format.type)
    }

    private static func encode(_ image: CGImage, type: UTType) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else {
            throw CleanupFailure(message: "This Mac cannot write \(type.preferredFilenameExtension ?? type.identifier) images.")
        }
        let properties: [CFString: Any] = (type == .jpeg || type == .heic)
            ? [kCGImageDestinationLossyCompressionQuality: 0.95] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CleanupFailure(message: "Could not encode the export. Try PNG in Settings.")
        }
        return data as Data
    }

    struct Raster {
        var bytes: [UInt8]
        let width: Int
        let height: Int
        func image() throws -> CGImage {
            guard let provider = CGDataProvider(data: Data(bytes) as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
                                        .union(.byteOrder32Big), provider: provider, decode: nil,
                                      shouldInterpolate: false, intent: .defaultIntent) else {
                throw CleanupFailure(message: "Could not create an image buffer.")
            }
            return image
        }
    }

    static func raster(_ url: URL) throws -> Raster {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CleanupFailure(message: "Could not read image pixels.")
        }
        return try raster(image)
    }

    private static func raster(_ image: CGImage) throws -> Raster {
        guard image.width > 0, image.height > 0, image.width <= maximumPixels / image.height else {
            throw CleanupFailure(message: "Image exceeds the 25-megapixel working limit.")
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw CleanupFailure(message: "Could not allocate an image buffer.")
            }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Raster(bytes: bytes, width: image.width, height: image.height)
    }

    /// Copies only the selected pixel rows. FFmpeg's whole-frame RGB/YUV conversion
    /// never replaces pixels outside this rectangle in our 8-bit sRGB working image.
    static func composite(original: URL, filtered: URL, box: CGRect, output: URL) throws {
        var base = try raster(original)
        let patch = try raster(filtered)
        guard base.width == patch.width, base.height == patch.height else {
            throw CleanupFailure(message: "Cleanup changed the image dimensions unexpectedly.")
        }
        let x = Int(box.minX), y = Int(box.minY), width = Int(box.width), height = Int(box.height)
        guard x >= 0, y >= 0, width > 0, height > 0, x + width <= base.width, y + height <= base.height else {
            throw CleanupFailure(message: "Cleanup area is outside the image.")
        }
        for row in y..<(y + height) {
            let start = (row * base.width + x) * 4
            base.bytes.replaceSubrange(start..<(start + width * 4), with: patch.bytes[start..<(start + width * 4)])
        }
        try encode(base.image(), type: .png).write(to: output, options: .atomic)
    }

    static func normalize(_ input: URL, to output: URL) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw CleanupFailure(message: "Could not read this image. Use PNG, JPG/JPEG, TIFF, BMP, HEIC or WebP.")
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw CleanupFailure(message: "This image could not be decoded by macOS.")
        }
        try encode(raster(image).image(), type: .png).write(to: output, options: .atomic)
    }
}
