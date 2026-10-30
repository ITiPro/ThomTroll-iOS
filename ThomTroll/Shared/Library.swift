import Foundation

struct TextTemplate: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var text: String
    var favorite: Bool = false
}

struct TemplateLibrary: Codable {
    var version = 1
    var templates: [TextTemplate] = []
    var prefix = ""
    var selectedID: UUID?

    static var initial: TemplateLibrary {
        let first = TextTemplate(name: "Приветствие", text: "Привет! 👋\nКак настроение?")
        return TemplateLibrary(templates: [first], selectedID: first.id)
    }

    mutating func validate() throws {
        guard version == 1, templates.count <= 500,
              Set(templates.map(\.id)).count == templates.count,
              prefix.utf8.count <= 65_536,
              templates.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  $0.name.count <= 200 && $0.text.utf8.count <= 5 * 1024 * 1024 && !$0.text.contains("\0") })
        else { throw LibraryError.invalid }
        if !templates.contains(where: { $0.id == selectedID }) { selectedID = templates.first?.id }
    }

    static func decode(_ data: Data) throws -> TemplateLibrary {
        guard data.count <= 32 * 1024 * 1024 else { throw LibraryError.tooLarge }
        var library = try JSONDecoder().decode(TemplateLibrary.self, from: data)
        try library.validate()
        return library
    }
}

enum LibraryError: LocalizedError {
    case invalid, tooLarge, encoding
    var errorDescription: String? {
        switch self {
        case .invalid: return "Некорректная коллекция шаблонов."
        case .tooLarge: return "TXT — до 5 МБ, коллекция — до 32 МБ."
        case .encoding: return "Не удалось прочитать текст. Сохраните TXT в UTF-8."
        }
    }
}

struct LibraryStore {
    private var file: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("templates.json")
    }
    func load() throws -> TemplateLibrary {
        guard FileManager.default.fileExists(atPath: file.path) else { return .initial }
        return try TemplateLibrary.decode(Data(contentsOf: file))
    }
    func save(_ value: TemplateLibrary) throws {
        var checked = value
        try checked.validate()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(checked).write(to: file, options: .atomic)
    }
    static func readTXT(_ data: Data) throws -> String {
        guard data.count <= 5 * 1024 * 1024 else { throw LibraryError.tooLarge }
        let text: String?
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            text = String(data: data, encoding: .utf16)
        } else {
            text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1251)
        }
        guard let result = text, !result.contains("\0") else { throw LibraryError.encoding }
        return result.replacingOccurrences(of: "\u{feff}", with: "")
    }
}

struct RowQueue {
    private(set) var rows: [String]
    private(set) var position = 0
    private(set) var cycle = 1
    let random: Bool

    init(text: String, random: Bool) {
        self.random = random
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let source = normalized.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if random {
            var seen = Set<String>()
            rows = source.filter { seen.insert($0).inserted }.shuffled()
        } else { rows = source }
    }
    var current: String? { position < rows.count ? rows[position] : nil }
    var isFinished: Bool { current == nil }
    mutating func advance() { if position < rows.count { position += 1 } }
    mutating func restart() {
        let last = rows.last
        if random {
            rows.shuffle()
            if rows.count > 1, rows.first == last { rows.swapAt(0, 1) }
        }
        position = 0
        cycle += 1
    }
}
