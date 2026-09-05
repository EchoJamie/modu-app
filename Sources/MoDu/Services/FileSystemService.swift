import Foundation

enum FileSystemError: LocalizedError {
    case outsideWorkspace
    case unsupportedEncoding
    case structuredDocumentTooLarge

    var errorDescription: String? {
        switch self {
        case .outsideWorkspace: L10n.string(.errorOutsideWorkspace)
        case .unsupportedEncoding: L10n.string(.errorUnsupportedEncoding)
        case .structuredDocumentTooLarge: L10n.string(.errorStructuredDocumentTooLarge)
        }
    }
}

enum FileSystemService {
    struct LoadedDirectory: Sendable {
        let url: URL
        let entries: [FileEntry]
    }

    /// Reads just one single-child chain, stopping at branches, files, or link cycles.
    static func directoryChain(at directoryURL: URL, inside rootURL: URL) async throws -> [LoadedDirectory] {
        try await CancellableWorker.run(priority: .userInitiated) {
            var result: [LoadedDirectory] = []
            var visited: Set<String> = []
            var current = directoryURL.standardizedFileURL
            while true {
                try Task.checkCancellation()
                let resolvedPath = current.resolvingSymlinksInPath().standardizedFileURL.path
                guard visited.insert(resolvedPath).inserted else { break }
                let entries: [FileEntry]
                do {
                    entries = try entriesSynchronously(at: current, inside: rootURL)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Keep the readable prefix; the failing child remains collapsed
                    // and can be retried explicitly using the normal expand action.
                    if result.isEmpty { throw error }
                    break
                }
                result.append(LoadedDirectory(url: current, entries: entries))
                guard entries.count == 1, let child = entries.first, child.kind == .directory else { break }
                current = child.url
            }
            return result
        }
    }

    static func previewKind(at url: URL) -> PreviewDocumentKind? {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return PreviewDocumentKind.resolve(
            fileName: url.lastPathComponent,
            isRegularFile: values?.isRegularFile == true
        )
    }

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

    static func readText(
        at fileURL: URL,
        inside rootURL: URL,
        maximumBytes: Int? = nil
    ) async throws -> (String, Int64, Date?) {
        try await CancellableWorker.run(priority: .userInitiated) {
            let readableURL = try validatedURL(fileURL, inside: rootURL)
            try Task.checkCancellation()

            let values = try readableURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            if let maximumBytes, let fileSize = values.fileSize, fileSize > maximumBytes {
                throw FileSystemError.structuredDocumentTooLarge
            }

            let handle = try FileHandle(forReadingFrom: readableURL)
            defer { try? handle.close() }
            let data: Data
            if let maximumBytes {
                var boundedData = Data()
                while boundedData.count <= maximumBytes {
                    try Task.checkCancellation()
                    let remainingBytes = maximumBytes + 1 - boundedData.count
                    guard
                        remainingBytes > 0,
                        let chunk = try handle.read(upToCount: remainingBytes),
                        !chunk.isEmpty
                    else { break }
                    boundedData.append(chunk)
                }
                guard boundedData.count <= maximumBytes else {
                    throw FileSystemError.structuredDocumentTooLarge
                }
                data = boundedData
            } else {
                data = try handle.readToEnd() ?? Data()
            }
            try Task.checkCancellation()

            let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian]
            guard let content = encodings.lazy.compactMap({ String(data: data, encoding: $0) }).first else {
                throw FileSystemError.unsupportedEncoding
            }

            return (content, Int64(data.count), values.contentModificationDate)
        }
    }

    static func validate(_ candidateURL: URL, inside rootURL: URL) throws {
        _ = try validatedURL(candidateURL, inside: rootURL)
    }

    static func readData(
        at fileURL: URL,
        inside rootURL: URL,
        maximumBytes: Int
    ) throws -> Data {
        let readableURL = try validatedURL(fileURL, inside: rootURL)
        let values = try readableURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard (values.fileSize ?? 0) <= maximumBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }

        let handle = try FileHandle(forReadingFrom: readableURL)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let remainingBytes = maximumBytes + 1 - data.count
            guard
                remainingBytes > 0,
                let chunk = try handle.read(upToCount: remainingBytes),
                !chunk.isEmpty
            else { break }
            data.append(chunk)
        }
        guard data.count <= maximumBytes else {
            throw URLError(.dataLengthExceedsMaximum)
        }
        return data
    }

    static func validatedURL(_ candidateURL: URL, inside rootURL: URL) throws -> URL {
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        let candidate = candidateURL.resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else {
            throw FileSystemError.outsideWorkspace
        }
        return candidate
    }
}
