import Foundation

enum FileSystemError: LocalizedError {
    case outsideWorkspace
    case unsupportedEncoding

    var errorDescription: String? {
        switch self {
        case .outsideWorkspace: "该文件不在当前工作目录中。"
        case .unsupportedEncoding: "无法识别这个文件的文本编码。"
        }
    }
}

enum FileSystemService {
    static func entries(at directoryURL: URL, inside rootURL: URL) async throws -> [FileEntry] {
        try await CancellableWorker.run(priority: .userInitiated) {
            try entriesSynchronously(at: directoryURL, inside: rootURL)
        }
    }

    static func entriesSynchronously(at directoryURL: URL, inside rootURL: URL) throws -> [FileEntry] {
        try Task.checkCancellation()
        try validate(directoryURL, inside: rootURL)

        // Foundation 可以读取目录符号链接的资源属性，但不能直接用该 URL
        // 枚举内容。读取解析后的真实目录，再把子项映射回用户看到的逻辑路径。
        let resolvedDirectoryURL = directoryURL.resolvingSymlinksInPath().standardizedFileURL
        try validate(resolvedDirectoryURL, inside: rootURL)

        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        try Task.checkCancellation()
        let resolvedURLs = try FileManager.default.contentsOfDirectory(
            at: resolvedDirectoryURL,
            includingPropertiesForKeys: keys,
            options: []
        )

        var entries: [FileEntry] = []
        entries.reserveCapacity(resolvedURLs.count)

        for resolvedURL in resolvedURLs {
            try Task.checkCancellation()
            let name = resolvedURL.lastPathComponent
            guard !isIgnoredAppleMetadata(named: name) else { continue }

            let logicalURL = directoryURL
                .standardizedFileURL
                .appendingPathComponent(name)
            entries.append(FileEntry(
                url: logicalURL,
                kind: try kind(of: logicalURL, inside: rootURL)
            ))
        }

        return entries.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .directory }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    static func isIgnoredAppleMetadata(named name: String) -> Bool {
        name == ".DS_Store" || name.hasPrefix("._")
    }

    static func kind(of url: URL, inside rootURL: URL) throws -> FileNodeKind {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink == true else {
            return values.isDirectory == true ? .directory : .file
        }

        let resolvedTarget = url.resolvingSymlinksInPath().standardizedFileURL
        let targetValues = try? resolvedTarget.resourceValues(forKeys: [.isDirectoryKey])
        guard
            (try? validate(resolvedTarget, inside: rootURL)) != nil,
            targetValues?.isDirectory == true
        else {
            return .file
        }
        return .directory
    }

    static func readText(at fileURL: URL, inside rootURL: URL) async throws -> (String, Int64, Date?) {
        try await CancellableWorker.run(priority: .userInitiated) {
            try validate(fileURL, inside: rootURL)
            try Task.checkCancellation()

            let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
            try Task.checkCancellation()

            let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]
            guard let content = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first else {
                throw FileSystemError.unsupportedEncoding
            }

            return (content, Int64(values.fileSize ?? data.count), values.contentModificationDate)
        }
    }

    static func validate(_ candidateURL: URL, inside rootURL: URL) throws {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let candidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard candidate == root || candidate.hasPrefix(root + "/") else {
            throw FileSystemError.outsideWorkspace
        }
    }
}
