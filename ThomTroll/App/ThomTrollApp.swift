import SwiftUI
import UniformTypeIdentifiers

@main
struct ThomTrollApp: App {
    var body: some Scene {
        WindowGroup { LibraryScreen().preferredColorScheme(.dark).tint(Color(red: 1, green: 0.22, blue: 0.36)) }
    }
}

final class LibraryModel: ObservableObject {
    @Published var library = TemplateLibrary.initial
    @Published var error: String?
    init() {
        do { library = try LibraryStore().load() }
        catch { self.error = "E_READ: \(error.localizedDescription)" }
    }
    func commit(_ value: TemplateLibrary) {
        do { try LibraryStore().save(value); library = value }
        catch { self.error = "E_SAVE: \(error.localizedDescription)" }
    }
    func copyForKeyboard() -> Bool {
        do {
            UIPasteboard.general.string = String(decoding: try JSONEncoder().encode(library), as: UTF8.self)
            return true
        } catch { self.error = "E_EXPORT: \(error.localizedDescription)"; return false }
    }
}

struct LibraryScreen: View {
    @StateObject private var model = LibraryModel()
    @State private var editing: TextTemplate?
    @State private var importer = false
    @State private var favorites = false
    @State private var copied = false
    private let accent = Color(red: 0.94, green: 0.13, blue: 0.28)
    private var visible: [TextTemplate] { model.library.templates.filter { !favorites || $0.favorite } }

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Твои тексты. Один тап.").font(.title2.bold())
                            Text("Выбери шаблон и передай коллекцию в клавиатуру.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(panel)
                        action("Создать шаблон", icon: "plus") { editing = TextTemplate(name: "", text: "") }
                        action("Загрузить шаблон TXT", icon: "doc.badge.plus") { importer = true }
                        action(favorites ? "Показать все шаблоны" : "Избранные шаблоны", icon: "star") { favorites.toggle() }
                        ForEach(visible) { template in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Button {
                                        var value = model.library; value.selectedID = template.id; model.commit(value)
                                    } label: {
                                        Image(systemName: model.library.selectedID == template.id ? "largecircle.fill.circle" : "circle")
                                            .font(.title2)
                                        Text(template.name).font(.headline).foregroundStyle(.white)
                                    }
                                    Spacer()
                                    Button {
                                        var value = model.library
                                        if let index = value.templates.firstIndex(where: { $0.id == template.id }) {
                                            value.templates[index].favorite.toggle(); model.commit(value)
                                        }
                                    } label: { Image(systemName: template.favorite ? "star.fill" : "star") }
                                        .accessibilityLabel("Избранное")
                                }
                                Text(template.text).lineLimit(3).font(.subheadline).foregroundStyle(.secondary)
                                HStack {
                                    Text("\(template.text.count) символов").font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Изменить") { editing = template }
                                }
                            }.padding(18).background(panel)
                        }
                        if visible.isEmpty { Text("Шаблонов пока нет").foregroundStyle(.secondary).padding() }
                        Button {
                            copied = model.copyForKeyboard()
                        } label: {
                            Label("Передать коллекцию в клавиатуру", systemImage: "keyboard")
                                .font(.headline).frame(maxWidth: .infinity).padding(16)
                        }.buttonStyle(.borderedProminent)
                        Text("После копирования открой чат → нашу клавиатуру → «Импорт». Это заменит её коллекцию.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.padding(16)
                }.background(Color(red: 0.035, green: 0.025, blue: 0.04))
                    .navigationTitle("Шаблоны")
            }.tabItem { Label("Шаблоны", systemImage: "text.alignleft") }
            NavigationStack {
                Form {
                    Section("Включение клавиатуры") {
                        Text("Настройки iPhone → Основные → Клавиатура → Клавиатуры → Новые клавиатуры → ThomTroll.")
                        Text("Для импорта из буфера включи «Разрешить полный доступ» у ThomTroll. Интернет приложение не использует.")
                        Text("В чате удерживай 🌐 и выбери ThomTroll.")
                    }
                    Section("Префикс") {
                        TextField("Например: Привет,", text: Binding(get: { model.library.prefix }, set: {
                            var value = model.library; value.prefix = $0; model.commit(value)
                        }))
                        Text("Можно менять и прямо в клавиатуре.")
                    }
                    Section("Как работает «Ввод»") {
                        Text("Клавиша вставляет символ новой строки. Отправку определяет игра или приложение. Автоматическое нажатие чужой кнопки отправки на iOS недоступно.")
                        Text("Совместимость с «Целуй и знакомься» на iPhone пока не проверена.")
                    }
                    Section("Хранение") {
                        Text("Приложение и клавиатура хранят коллекции отдельно. Передавай изменения кнопкой на странице шаблонов. Общий контейнер не используется, чтобы не требовать App Groups при бесплатной подписи.")
                    }
                }.navigationTitle("Настройки")
            }.tabItem { Label("Настройки", systemImage: "gearshape") }
        }
        .sheet(item: $editing) { template in
            TemplateEditor(template: template, onSave: { changed in
                var value = model.library
                if let i = value.templates.firstIndex(where: { $0.id == changed.id }) { value.templates[i] = changed }
                else { value.templates.append(changed) }
                value.selectedID = changed.id; model.commit(value)
            }, onDelete: {
                var value = model.library; value.templates.removeAll { $0.id == template.id }
                if value.selectedID == template.id { value.selectedID = value.templates.first?.id }
                model.commit(value)
            })
        }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.plainText], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 5 * 1024 * 1024 else { throw LibraryError.tooLarge }
                let text = try LibraryStore.readTXT(Data(contentsOf: url, options: .mappedIfSafe))
                editing = TextTemplate(name: String(url.deletingPathExtension().lastPathComponent.prefix(200)), text: text)
            } catch { model.error = "E_IMPORT: \(error.localizedDescription)" }
        }
        .alert("Коллекция скопирована", isPresented: $copied) {
            Button("Понятно", role: .cancel) {}
        } message: { Text("Открой нашу клавиатуру в чате и нажми «Импорт».") }
        .alert("Не получилось", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 20).fill(Color(red: 0.10, green: 0.075, blue: 0.09))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.23)))
    }
    private func action(_ title: String, icon: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(16)
        }.background(panel)
    }
}

struct TemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var template: TextTemplate
    var onSave: (TextTemplate) -> Void
    var onDelete: () -> Void
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Название шаблона", text: $template.name)
                TextEditor(text: $template.text).frame(minHeight: 240)
                Text("TXT до 5 МБ. Одна строка — одна фраза.").font(.footnote).foregroundStyle(.secondary)
                Button("Удалить шаблон", role: .destructive) { confirmDelete = true }
            }.navigationTitle("Шаблон")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Сохранить") { onSave(template); dismiss() }
                            .disabled(template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                      template.name.count > 200 || template.text.utf8.count > 5 * 1024 * 1024 || template.text.contains("\0"))
                    }
                }
                .confirmationDialog("Удалить шаблон?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Удалить", role: .destructive) { onDelete(); dismiss() }
                }
        }.preferredColorScheme(.dark)
    }
}
