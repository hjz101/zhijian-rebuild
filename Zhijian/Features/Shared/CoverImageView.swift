// CoverImageView.swift — 封面图片（复用 ReaderImageStore 磁盘缓存 + AsyncImage 兜底）
import SwiftUI

struct CoverImageView: View {
    let urlString: String
    let placeholder: String
    var width: CGFloat = 64
    var height: CGFloat = 88
    var cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ZJ.bgElev2)
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Text(String(placeholder.prefix(1)))
                        .font(.system(size: max(width * 0.4, 22), design: .serif))
                        .foregroundStyle(ZJ.textSecondary)
                default:
                    ProgressView().controlSize(.small)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}
