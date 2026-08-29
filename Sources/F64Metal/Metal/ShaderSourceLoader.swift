import Foundation

enum ShaderSourceLoader {
    static func load() throws -> String {
        guard let manifestURL = Bundle.module.url(
            forResource: "manifest", withExtension: "txt", subdirectory: "Shaders"
        ) else {
            throw HarnessError.resourceMissing("Shaders/manifest.txt")
        }

        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let names = manifest.split(whereSeparator: \.isNewline).map(String.init).filter {
            !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
        }
        var sections: [String] = []
        for name in names {
            let path = name.trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }
            let relative = "Shaders/\(path)"
            let url = manifestURL.deletingLastPathComponent().appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw HarnessError.resourceMissing(relative)
            }
            sections.append("#line 1 \"\(path)\"\n" +
                            (try String(contentsOf: url, encoding: .utf8)))
        }
        return sections.joined(separator: "\n")
    }
}
