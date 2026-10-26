// QRCodeGenerator.swift — QR 码生成（书源导出分享）
import UIKit
import CoreImage

enum QRCodeGenerator {
    /// 生成 QR 码（文本过大返回 nil）
    static func generate(text: String, correctionLevel: String = "M") throws -> UIImage? {
        guard !text.isEmpty, text.count < 6000 else { return nil }
        let data = Data(text.utf8)
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw QRCodeError.filterUnavailable
        }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue(correctionLevel, forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    enum QRCodeError: Error {
        case filterUnavailable
    }
}
