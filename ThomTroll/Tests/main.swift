import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

var ordered = RowQueue(text: "привет\r\n\nчто делаешь\rпока", random: false)
check(ordered.current == "привет", "CRLF normalization")
ordered.advance()
check(ordered.current == "что делаешь", "Pause resumes next whole line")
ordered.advance(); ordered.advance()
check(ordered.isFinished, "Finite pass ends")
ordered.restart()
check(ordered.cycle == 2 && ordered.current == "привет", "Cycle reset")
var shuffled = RowQueue(text: "а\nб\nа\nв\n ", random: true)
for _ in 0..<100 {
    check(shuffled.rows.count == 3 && Set(shuffled.rows).count == 3, "No duplicate random rows")
    let last = shuffled.rows.last
    shuffled.restart()
    check(shuffled.rows.first != last, "No adjacent duplicate across cycles")
}
var single = RowQueue(text: "одна", random: true)
single.advance(); single.restart()
check(single.current == "одна", "Single-row repetition works")
check(RowQueue(text: "\n \r\n", random: true).isFinished, "Empty template stops")
var library = TemplateLibrary.initial
let encoded = try JSONEncoder().encode(library)
let decoded = try TemplateLibrary.decode(encoded)
check(decoded.templates == library.templates && decoded.selectedID == library.selectedID, "Clipboard collection roundtrip")
library.selectedID = UUID()
try library.validate()
check(library.selectedID == library.templates.first?.id, "Missing selected template falls back")
library.templates.append(library.templates[0])
do { try library.validate(); fatalError("Duplicate IDs accepted") } catch LibraryError.invalid { }
var invalid = TemplateLibrary.initial
invalid.templates[0].text = "bad\0text"
do { try invalid.validate(); fatalError("NUL accepted") } catch LibraryError.invalid { }
let limit = Data(repeating: 65, count: 5 * 1024 * 1024)
let decodedLimit = try LibraryStore.readTXT(limit)
check(decodedLimit.count == limit.count, "5 MiB accepted")
do { _ = try LibraryStore.readTXT(limit + Data([65])); fatalError("Oversize TXT accepted") } catch LibraryError.tooLarge { }
let unicode = "Привет 👋\n東京"
let decodedUnicode = try LibraryStore.readTXT(Data(unicode.utf8))
check(decodedUnicode == unicode, "UTF-8 survives import")
print("PASS: row ordering, pause position, random cycles, collection validation, limits, Unicode")
