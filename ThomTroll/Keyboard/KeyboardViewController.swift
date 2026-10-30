import UIKit

final class KeyboardViewController: UIInputViewController {
    private let root = UIStackView()
    private let content = UIStackView()
    private let status = UILabel()
    private let glow = CAGradientLayer()
    private let red = UIColor(red: 1, green: 0.25, blue: 0.37, alpha: 1)
    private var library = TemplateLibrary.initial
    private var page = 0
    private var english = false
    private var symbols = false
    private var shift = false
    private var favoritesOnly = false
    private var prefixDraft: String?
    private var pendingImport: TemplateLibrary?
    private var queue: RowQueue?
    private var timer: Timer?
    private var deleteTimer: Timer?
    private var running = false
    private var waitingForCycle = false
    private var countdown = 0
    private var randomOrder = false
    private var repeatOn = false
    private var interval: TimeInterval = 1
    private var editorID: UUID?
    private var heightConstraint: NSLayoutConstraint?
    private var logs: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        do { library = try LibraryStore().load() }
        catch { record("E_READ: \(error.localizedDescription)") }
        view.backgroundColor = UIColor(red: 0.035, green: 0.025, blue: 0.04, alpha: 1)
        glow.colors = [UIColor(red: 0.22, green: 0.02, blue: 0.065, alpha: 1).cgColor,
                       UIColor(red: 0.045, green: 0.03, blue: 0.055, alpha: 1).cgColor]
        glow.startPoint = CGPoint(x: 0, y: 0); glow.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(glow, at: 0)
        root.axis = .vertical; root.spacing = 7; root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 7),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -7),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            root.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)
        ])
        heightConstraint = view.heightAnchor.constraint(equalToConstant: 350)
        heightConstraint?.priority = .defaultHigh
        heightConstraint?.isActive = true
        content.axis = .vertical; content.spacing = 7
        status.font = .systemFont(ofSize: 11, weight: .medium)
        status.textColor = .lightGray; status.numberOfLines = 2
        status.setContentCompressionResistancePriority(.required, for: .vertical)
        refresh()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        glow.frame = view.bounds
        heightConstraint?.constant = view.bounds.width > 600 ? 285 : 350
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stop(); deleteTimer?.invalidate(); deleteTimer = nil
        prefixDraft = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        if let id = editorID, id != textDocumentProxy.documentIdentifier {
            stop(); refresh(); notice("Поле сменилось — набор остановлен.")
        }
    }

    private func button(_ title: String, accent: Bool = false, action: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system)
        b.setTitle(title, for: .normal)
        b.setTitleColor(.white, for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.7
        b.backgroundColor = accent ? red.withAlphaComponent(0.8) : UIColor(white: 0.13, alpha: 0.95)
        b.layer.cornerRadius = 11; b.layer.borderWidth = 0.5
        b.layer.borderColor = red.withAlphaComponent(0.20).cgColor
        b.addAction(UIAction { _ in action() }, for: .touchUpInside)
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        return b
    }

    private func row(_ buttons: [UIView]) -> UIStackView {
        let s = UIStackView(arrangedSubviews: buttons); s.axis = .horizontal
        s.spacing = 5; s.distribution = .fillEqually
        return s
    }

    private func refresh() {
        guard isViewLoaded else { return }
        root.arrangedSubviews.forEach { root.removeArrangedSubview($0); $0.removeFromSuperview() }
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        root.addArrangedSubview(row([
            button("АБВ", accent: page == 0) { [weak self] in self?.page = 0; self?.refresh() },
            button("Шаблоны", accent: page == 1) { [weak self] in self?.prefixDraft = nil; self?.page = 1; self?.refresh() },
            button("Префикс", accent: prefixDraft != nil) { [weak self] in
                guard let self = self else { return }; self.pause()
                self.prefixDraft = self.library.prefix; self.page = 0; self.refresh()
            },
            button("⚙", accent: page == 2) { [weak self] in self?.pause(); self?.prefixDraft = nil; self?.page = 2; self?.refresh() }
        ]))
        root.addArrangedSubview(content)
        if page == 0 { makeKeys() }
        else if page == 1 { makeTemplates() }
        else { makeSettings() }
        root.addArrangedSubview(status)
        if prefixDraft != nil { notice("Префикс редактируется здесь. В чат он пока не вводится.") }
        else if running { updateProgress() }
        else { notice(queue == nil ? "Ввод ↵: поведение отправки зависит от приложения." : "Пауза. Продолжить — со следующей целой строки.") }
    }

    private func makeKeys() {
        if let draft = prefixDraft {
            let preview = UILabel(); preview.text = "Префикс: \(draft)▏"; preview.textColor = .white
            preview.font = .systemFont(ofSize: 15); preview.lineBreakMode = .byTruncatingHead
            content.addArrangedSubview(preview)
            content.addArrangedSubview(row([
                button("Вставить") { [weak self] in self?.pastePrefix() },
                button("Очистить") { [weak self] in self?.prefixDraft = ""; self?.refresh() },
                button("Готово", accent: true) { [weak self] in
                    guard let self = self else { return }
                    self.library.prefix = self.prefixDraft ?? ""; self.prefixDraft = nil; self.persist(); self.refresh()
                },
                button("Отмена") { [weak self] in self?.prefixDraft = nil; self?.refresh() }
            ]))
        }
        let lines: [String]
        if symbols { lines = ["1234567890", "@#₽_&-+()/", "?!.,:;\"'="] }
        else if english { lines = ["qwertyuiop", "asdfghjkl", "zxcvbnm"] }
        else { lines = ["йцукенгшщзхъ", "фывапролджэ", "ячсмитьбюё"] }
        for letters in lines {
            var buttons: [UIView] = letters.map { letter in
                let value = shift ? String(letter).uppercased() : String(letter)
                return button(value) { [weak self] in self?.insert(value) }
            }
            if letters == lines.last {
                buttons.insert(button("⇧", accent: shift) { [weak self] in self?.shift.toggle(); self?.refresh() }, at: 0)
                let delete = button("⌫") { [weak self] in self?.backspace() }
                delete.accessibilityLabel = "Удалить символ"
                delete.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(heldDelete(_:))))
                buttons.append(delete)
            }
            content.addArrangedSubview(row(buttons))
        }
        let globe = button("🌐") { }
        globe.accessibilityLabel = "Другая клавиатура"
        globe.addTarget(self, action: #selector(nextKeyboard(_:event:)), for: .allTouchEvents)
        content.addArrangedSubview(row([
            globe,
            button(symbols ? "АБВ" : "123") { [weak self] in self?.symbols.toggle(); self?.refresh() },
            button(english ? "EN" : "РУ") { [weak self] in self?.english.toggle(); self?.refresh() },
            button("Пробел") { [weak self] in self?.insert(" ") },
            button("Ввод ↵", accent: true) { [weak self] in self?.insert("\n") }
        ]))
    }

    private func makeTemplates() {
        content.addArrangedSubview(row([
            button(favoritesOnly ? "Все шаблоны" : "☆ Избранные") { [weak self] in self?.favoritesOnly.toggle(); self?.refresh() },
            button(pendingImport == nil ? "Импорт" : "Заменить?", accent: pendingImport != nil) { [weak self] in self?.importClipboard() }
        ]))
        let scroll = UIScrollView()
        let list = UIStackView(); list.axis = .vertical; list.spacing = 5
        list.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(list)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            list.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            list.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            list.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
        for template in library.templates where !favoritesOnly || template.favorite {
            list.addArrangedSubview(button("\(template.id == library.selectedID ? "●" : "○")  \(template.name)", accent: template.id == library.selectedID) { [weak self] in
                guard let self = self else { return }; self.stop()
                self.library.selectedID = template.id; self.persist(); self.refresh()
            })
        }
        content.addArrangedSubview(scroll)
        content.addArrangedSubview(row([
            button("Строка") { [weak self] in self?.pause(); self?.refresh(); self?.insertNext(newline: false) },
            button(running ? "Пауза" : (queue == nil ? "Старт" : "Продолжить"), accent: true) { [weak self] in
                guard let self = self else { return }; self.running ? self.pause() : self.start(); self.refresh()
            },
            button("Стоп") { [weak self] in self?.stop(); self?.refresh() },
            button("Ввод ↵") { [weak self] in self?.insert("\n") }
        ]))
    }

    private func makeSettings() {
        content.addArrangedSubview(button(randomOrder ? "Порядок: рандом" : "Порядок: с начала") { [weak self] in
            guard let self = self else { return }; self.stop(); self.randomOrder.toggle(); self.refresh()
        })
        content.addArrangedSubview(row([0.5, 1.0, 3.0].map { delay in
            button("\(delay) с", accent: interval == delay) { [weak self] in self?.interval = delay; self?.refresh() }
        }))
        content.addArrangedSubview(button(repeatOn ? "Повтор: включён • перерыв 5 с" : "Повтор: выключен") { [weak self] in
            self?.repeatOn.toggle(); self?.refresh()
        })
        content.addArrangedSubview(button("Журнал • \(logs.count)") { [weak self] in
            guard let self = self else { return }
            self.notice(self.logs.suffix(2).joined(separator: "\n").isEmpty ? "Ошибок пока нет." : self.logs.suffix(2).joined(separator: "\n"))
        })
        let label = UILabel(); label.numberOfLines = 0; label.textColor = .lightGray
        label.font = .systemFont(ofSize: 12)
        label.text = "Старт вставляет целые строки и ↵. Это не нажатие кнопки отправки. Для импорта нужен полный доступ. Звук и видео в эту первую версию не включены."
        content.addArrangedSubview(label)
    }

    private func insert(_ text: String) {
        if var draft = prefixDraft {
            guard text != "\n", draft.utf8.count + text.utf8.count <= 65_536 else { return }
            draft += text; prefixDraft = draft; refresh()
        } else {
            let wasRunning = running
            pause(); textDocumentProxy.insertText(text)
            if wasRunning { refresh() }
        }
    }
    private func backspace() {
        if var draft = prefixDraft {
            if !draft.isEmpty { draft.removeLast() }; prefixDraft = draft; refresh()
        } else {
            let wasRunning = running
            pause(); textDocumentProxy.deleteBackward()
            if wasRunning { refresh() }
        }
    }
    @objc private func heldDelete(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            backspace()
            deleteTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in self?.backspace() }
        } else if gesture.state != .changed { deleteTimer?.invalidate(); deleteTimer = nil }
    }
    @objc private func nextKeyboard(_ sender: UIButton, event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }
    private func pastePrefix() {
        guard hasFullAccess else { notice("Включи полный доступ в настройках клавиатуры для вставки."); return }
        guard let value = UIPasteboard.general.string, value.utf8.count <= 65_536 else { notice("Буфер пуст или префикс слишком большой."); return }
        prefixDraft = value.replacingOccurrences(of: "\n", with: " "); refresh()
    }
    private func importClipboard() {
        pause()
        if let incoming = pendingImport {
            library = incoming; pendingImport = nil; queue = nil; persist(); refresh()
            notice("Коллекция обновлена."); return
        }
        guard hasFullAccess else { notice("Для импорта включи полный доступ у ThomTroll в настройках iPhone."); return }
        guard let text = UIPasteboard.general.string else { notice("Буфер пуст. Скопируй коллекцию в приложении."); return }
        do {
            pendingImport = try TemplateLibrary.decode(Data(text.utf8)); refresh()
            notice("Нажми «Заменить?» ещё раз: текущая коллекция клавиатуры будет заменена.")
        } catch { record("E_IMPORT: \(error.localizedDescription)") }
    }
    private func ensureQueue() -> Bool {
        if queue == nil, let template = library.templates.first(where: { $0.id == library.selectedID }) {
            queue = RowQueue(text: template.text, random: randomOrder)
            editorID = textDocumentProxy.documentIdentifier
        }
        guard queue?.current != nil else { notice("Шаблон пуст или закончился. Стоп сбрасывает позицию."); return false }
        return true
    }
    private func insertNext(newline: Bool) {
        guard ensureQueue(), let line = queue?.current else { return }
        let prefix = library.prefix.isEmpty ? "" : library.prefix + " "
        textDocumentProxy.insertText(prefix + line + (newline ? "\n" : ""))
        queue?.advance(); updateProgress()
    }
    private func start() {
        if queue?.isFinished == true, repeatOn {
            waitingForCycle = true; countdown = max(countdown, 5)
        } else {
            guard ensureQueue() else { return }
            if !waitingForCycle { countdown = 3 }
        }
        running = true
        schedule(after: 0.01)
    }
    private func schedule(after delay: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in self?.tick() }
    }
    private func tick() {
        guard running, view.window != nil, editorID == textDocumentProxy.documentIdentifier else { stop(); return }
        if countdown > 0 {
            notice(waitingForCycle ? "Шаблон закончился. Повтор через \(countdown) с." : "Начало через \(countdown) с.")
            countdown -= 1; schedule(after: 1); return
        }
        if waitingForCycle { queue?.restart(); waitingForCycle = false }
        if queue?.isFinished == true {
            if repeatOn { waitingForCycle = true; countdown = 5; schedule(after: 0.01) }
            else { pause(); refresh(); notice("Шаблон закончился. Стоп — начать сначала.") }
            return
        }
        insertNext(newline: true)
        schedule(after: interval)
    }
    private func pause() {
        timer?.invalidate(); timer = nil; running = false
        // Each row is inserted in one call: there is no half-written phrase to resume.
    }
    private func stop() {
        pause(); queue = nil; editorID = nil; waitingForCycle = false; countdown = 0
    }
    private func updateProgress() {
        if let q = queue { notice("Цикл \(q.cycle) • вставлено строк: \(q.position)/\(q.rows.count). Отправку проверь в игре.") }
    }
    private func persist() {
        do { try LibraryStore().save(library) }
        catch { record("E_SAVE: \(error.localizedDescription)") }
    }
    private func notice(_ text: String) { status.text = text }
    private func record(_ text: String) {
        logs.append(text); if logs.count > 100 { logs.removeFirst(logs.count - 100) }; notice(text)
    }
}
