import SwiftUI

/// What kind of thing a file is. Classified by extension (fast enough for millions of files),
/// with a context override for everything living inside an app bundle, ~/Library, or a build artefact.
enum FileCategory: String, CaseIterable, Identifiable, Sendable, Hashable {
    case apps, documents, images, video, audio, archives, developer, system, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apps: "Applications"
        case .documents: "Documents"
        case .images: "Photos & Images"
        case .video: "Video"
        case .audio: "Music & Audio"
        case .archives: "Archives & Installers"
        case .developer: "Developer"
        case .system: "Library & System"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .apps: "app.badge"
        case .documents: "doc.richtext"
        case .images: "photo.on.rectangle.angled"
        case .video: "film"
        case .audio: "waveform"
        case .archives: "archivebox"
        case .developer: "chevron.left.forwardslash.chevron.right"
        case .system: "gearshape.2"
        case .other: "square.grid.2x2"
        }
    }

    var color: Color {
        switch self {
        case .apps: .blue
        case .documents: .orange
        case .images: .pink
        case .video: .purple
        case .audio: .red
        case .archives: .yellow
        case .developer: .mint
        case .system: .gray
        case .other: .indigo
        }
    }

    static func classify(fileName: String) -> FileCategory {
        guard let dot = fileName.lastIndex(of: "."), dot != fileName.startIndex else { return .other }
        let ext = fileName[fileName.index(after: dot)...].lowercased()
        return extensionMap[ext] ?? .other
    }

    private static let extensionMap: [String: FileCategory] = {
        var m: [String: FileCategory] = [:]
        func put(_ c: FileCategory, _ exts: String) { for e in exts.split(separator: " ") { m[String(e)] = c } }
        put(.documents, "pdf doc docx pages key numbers xls xlsx ppt pptx txt rtf rtfd md markdown csv tsv epub odt ods odp tex")
        put(.images, "jpg jpeg png heic heif gif tif tiff raw cr2 cr3 nef arw orf rw2 dng psd psb ai svg webp bmp ico icns sketch fig afphoto afdesign xcf exr hdr")
        put(.video, "mp4 mov m4v avi mkv webm wmv flv mpg mpeg mts m2ts 3gp braw r3d prproj")
        put(.audio, "mp3 m4a m4b aac wav aiff aif flac ogg opus alac caf mid midi logicx band")
        put(.archives, "zip rar 7z tar gz tgz bz2 xz zst lz4 dmg iso pkg mpkg xip ipsw img sparseimage sparsebundle")
        put(.developer, "swift m mm h hpp c cc cpp cs js mjs cjs ts tsx jsx py pyc pyo rb go rs java kt kts scala json yml yaml toml xml html htm css scss less sql sh zsh bash lock o a dylib so class jar wasm map ipynb gradle dart php lua r vue svelte xcarchive dsym pdb")
        put(.system, "plist db sqlite sqlite3 sqlite-wal sqlite-shm log cache dat ldb kext bom nib car")
        put(.apps, "app appex")
        return m
    }()
}
