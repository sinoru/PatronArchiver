import Foundation

enum XattrHelper {
    nonisolated static func setWhereFroms(_ urls: [URL], on path: String) throws {
        let strings = urls.map(\.absoluteString)
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: strings,
            format: .binary,
            options: 0
        )
        let result = plistData.withUnsafeBytes { buffer in
            setxattr(path, "com.apple.metadata:kMDItemWhereFroms", buffer.baseAddress, buffer.count, 0, 0)
        }
        if result != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    nonisolated static func setContentDates(
        createdAt: Date,
        modifiedAt: Date?,
        on path: String
    ) throws {
        let creationData = try PropertyListSerialization.data(
            fromPropertyList: createdAt,
            format: .binary,
            options: 0
        )
        let creationResult = creationData.withUnsafeBytes { buffer in
            setxattr(
                path,
                "com.apple.metadata:kMDItemContentCreationDate",
                buffer.baseAddress,
                buffer.count,
                0,
                0
            )
        }
        if creationResult != 0 {
            throw CocoaError(.fileWriteUnknown)
        }

        if let modifiedAt {
            let modificationData = try PropertyListSerialization.data(
                fromPropertyList: modifiedAt,
                format: .binary,
                options: 0
            )
            let modificationResult = modificationData.withUnsafeBytes { buffer in
                setxattr(
                    path,
                    "com.apple.metadata:kMDItemContentModificationDate",
                    buffer.baseAddress,
                    buffer.count,
                    0,
                    0
                )
            }
            if modificationResult != 0 {
                throw CocoaError(.fileWriteUnknown)
            }
        }
    }

    nonisolated static func setUserTags(_ tags: [String], on path: String) throws {
        guard !tags.isEmpty else { return }
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: tags,
            format: .binary,
            options: 0
        )
        let result = plistData.withUnsafeBytes { buffer in
            setxattr(path, "com.apple.metadata:_kMDItemUserTags", buffer.baseAddress, buffer.count, 0, 0)
        }
        if result != 0 {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
