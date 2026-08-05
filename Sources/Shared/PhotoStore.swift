import SwiftUI
import UIKit

/// Job photos live on disk next to the store file; the job itself only keeps
/// filenames. Keeping bytes out of the JSON snapshot means a request with six
/// photos of a broken sink still saves in a few milliseconds.
@MainActor
final class PhotoStore {
    static let shared = PhotoStore()

    private var cache: [String: UIImage] = [:]

    private var directory: URL {
        let folder = Persistence.directory.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Stores a JPEG and hands back the name to put on the job.
    func save(_ image: UIImage) -> String? {
        // Full-resolution camera frames are far more than a job card needs.
        let resized = image.fitted(within: 1400)
        guard let data = resized.jpegData(compressionQuality: 0.72) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
            cache[name] = resized
            return name
        } catch {
            return nil
        }
    }

    func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              let image = UIImage(data: data) else { return nil }
        cache[name] = image
        return image
    }

    func delete(_ name: String) {
        cache[name] = nil
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    func wipe() {
        cache.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}

private extension UIImage {
    func fitted(within maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// Draws a stored job photo, falling back to a placeholder if the file went
/// missing (a reinstall keeps the JSON but not always the images).
struct JobPhotoView: View {
    let name: String
    var body: some View {
        if let image = PhotoStore.shared.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Palette.canvas
                Image(systemName: "photo")
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
