import SwiftUI

struct ReceiptImagePreviewView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    init(image: UIImage) {
        self.image = image
    }

    init?(fileName: String) {
        guard let loaded = ReceiptImageStore.loadImage(fileName: fileName) else {
            return nil
        }
        self.image = loaded
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: geometry.size.width * scale,
                            height: geometry.size.height * scale
                        )
                        .frame(
                            minWidth: geometry.size.width,
                            minHeight: geometry.size.height
                        )
                }
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newScale = lastScale * value.magnification
                        scale = min(max(newScale, 1.0), 5.0)
                    }
                    .onEnded { _ in
                        lastScale = scale
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    if scale > 1.0 {
                        scale = 1.0
                        lastScale = 1.0
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
            .navigationTitle("添付画像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .background(Color.black)
        }
    }
}
