import Foundation

public struct CatalogEntry: Codable, Equatable {
    public var id: String
    public var description: String
    public var aliases: [String]
    public var mapsTo: String
    public var reference: String
    public var host: String

    public init(id: String, description: String, aliases: [String], mapsTo: String, host: String) {
        self.id = id
        self.description = description
        self.aliases = aliases
        self.mapsTo = mapsTo
        self.reference = "keylock://\(id)"
        self.host = host
    }
}

public struct Catalog: Codable, Equatable {
    public var keys: [CatalogEntry]

    public init(keys: [CatalogEntry] = []) {
        self.keys = keys
    }
}

public enum CatalogStore {
    public static let directory: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/api-key-lock", isDirectory: true)
    }()

    public static let fileURL = directory.appendingPathComponent("catalog.json")

    public static func load() throws -> Catalog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Catalog()
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    public static func save(_ catalog: Catalog) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(catalog)
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
    }
}

extension JSONEncoder {
    public static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public enum KeyID {
    public static func validate(_ id: String) throws {
        let pattern = #"^[a-z0-9][a-z0-9-]{0,31}$"#
        guard id.range(of: pattern, options: .regularExpression) != nil else {
            throw KeyIDError.invalid
        }
    }
}

public enum KeyIDError: Error, CustomStringConvertible {
    case invalid
    public var description: String { "key id must match [a-z0-9][a-z0-9-]{0,31}" }
}
