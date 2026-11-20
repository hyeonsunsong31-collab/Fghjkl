import Photos
import UIKit

/// iOS does not let apps change the system wallpaper, so the 3D workspace is
/// saved as an image into the "Jarvis Space" album. A Shortcuts personal
/// automation ("Find Photos in album Jarvis Space → Set Wallpaper") applies it
/// automatically (see docs/SETUP.ko.md). The image is also kept as an artefact.
enum WallpaperService {
    static let albumName = "Jarvis Space"

    enum WallpaperError: LocalizedError {
        case permission, noImage
        var errorDescription: String? {
            switch self {
            case .permission: return "Photo library permission was denied."
            case .noImage: return "The 3D space could not be captured."
            }
        }
    }

    /// Returns the URL of the saved PNG artefact.
    @MainActor
    static func save(_ image: UIImage, runID: String?) async throws -> URL? {
        let url = image.pngData().flatMap { data in
            RecordKeeper.shared.saveArtifact(data: data, filename: "wallpaper-\(Int(Date().timeIntervalSince1970)).png",
                                             runID: runID, description: "3D space wallpaper snapshot")
        }
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else { throw WallpaperError.permission }
        let existing: PHAssetCollection? = {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "title = %@", albumName)
            return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
        }()
        try await PHPhotoLibrary.shared().performChanges {
            let asset = PHAssetChangeRequest.creationRequestForAsset(from: image)
            guard let placeholder = asset.placeholderForCreatedAsset else { return }
            if let album = existing, let change = PHAssetCollectionChangeRequest(for: album) {
                change.addAssets([placeholder] as NSArray)
            } else {
                let create = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumName)
                create.addAssets([placeholder] as NSArray)
            }
        }
        return url
    }
}
