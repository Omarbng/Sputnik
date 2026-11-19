import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

/// On-device image work for the actions menu: read the text in an image (English, Russian,
/// French), make a smaller copy, convert to JPEG, and cut out the subject. Nothing leaves the Mac.
enum ImageTools {
    enum Failure: Error {
        case unreadable
        case noText
        case noSubject
    }

    /// Longest side of "Paste Smaller Image".
    static let smallerMaxPixels = 1_600
    static let jpegQuality = 0.8

    // MARK: Text

    /// The text in the image, top to bottom, with its line breaks.
    static func recognizeText(in data: Data) async throws -> String {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US", "ru-RU", "fr-FR"].map { Locale.Language(identifier: $0) }
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: data)
        let lines = observations.map(\.transcript).filter { !$0.allSatisfy(\.isWhitespace) }
        guard !lines.isEmpty else { throw Failure.noText }
        return lines.joined(separator: "\n")
    }

    // MARK: Size and format

    /// A copy whose longest side is at most `smallerMaxPixels`, as JPEG and PNG.
    static func smaller(_ data: Data) throws -> (jpeg: Data, png: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: smallerMaxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw Failure.unreadable }
        return (try encode(image, as: .jpeg), try encode(image, as: .png))
    }

    /// The image as JPEG (for HEIC photos and screenshots that need to be JPEG).
    static func jpeg(_ data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
        else { throw Failure.unreadable }
        return try encode(image, as: .jpeg)
    }

    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func encode(_ image: CGImage, as type: UTType) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, type.identifier as CFString, 1, nil)
        else { throw Failure.unreadable }
        let properties: [CFString: Any] = type == .jpeg ? [kCGImageDestinationLossyCompressionQuality: jpegQuality] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return output as Data
    }

    // MARK: Background

    /// The subject cut out on a transparent background, as PNG (like "Copy Subject" in Photos).
    static func removeBackground(_ data: Data) async throws -> Data {
        let handler = ImageRequestHandler(data)
        guard let observation = try await handler.perform(GenerateForegroundInstanceMaskRequest()),
              !observation.allInstances.isEmpty
        else { throw Failure.noSubject }
        let buffer = try observation.generateMaskedImage(for: observation.allInstances, imageFrom: handler, croppedToInstancesExtent: true)
        let image = CIImage(cvPixelBuffer: buffer)
        let context = CIContext()
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let png = context.pngRepresentation(of: image, format: .RGBA8, colorSpace: colorSpace)
        else { throw Failure.unreadable }
        return png
    }
}
