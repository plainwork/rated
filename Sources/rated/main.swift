import Cocoa
import Carbon.HIToolbox

struct RatingEntry {
    let date: Date
    let value: Int
}

struct RatingItem: Identifiable {
    let id: String
    var name: String
    var ratings: [RatingEntry]

    var lastRated: Date {
        ratings.last?.date ?? Date.distantPast
    }

    var averageRating: Double {
        guard !ratings.isEmpty else { return 0 }
        let total = ratings.reduce(0) { $0 + $1.value }
        return Double(total) / Double(ratings.count)
    }
}

final class RatingStore {
    private let baseURL: URL
    private let formatter = ISO8601DateFormatter()

    private(set) var items: [RatingItem] = []

    init() {
        baseURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".rated", isDirectory: true)
            .appendingPathComponent("ratings", isDirectory: true)
        ensureBaseDirectory()
        load()
    }

    func addRating(name: String, value: Int) -> Bool {
        let safeName = sanitizeName(name)
        let now = Date()
        if let index = items.firstIndex(where: { $0.id == safeName }) {
            var item = items[index]
            if item.ratings.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: now) }) {
                return false
            }
            item.ratings.append(RatingEntry(date: now, value: value))
            item.ratings.sort { $0.date < $1.date }
            items[index] = item
            write(item: item)
        } else {
            let item = RatingItem(
                id: safeName,
                name: safeName,
                ratings: [RatingEntry(date: now, value: value)]
            )
            items.append(item)
            write(item: item)
        }
        items.sort { $0.lastRated > $1.lastRated }
        return true
    }

    func deleteItem(name: String) {
        let safeName = sanitizeName(name)
        let url = baseURL.appendingPathComponent(safeName)
        try? FileManager.default.removeItem(at: url)
        items.removeAll { $0.id == safeName }
    }

    private func ensureBaseDirectory() {
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    private func load() {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: baseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var loadedItems: [RatingItem] = []
        for url in urls where !url.hasDirectoryPath {
            let name = url.lastPathComponent
            let ratings = parseRatings(from: url)
            if ratings.isEmpty { continue }
            let item = RatingItem(id: name, name: name, ratings: ratings.sorted { $0.date < $1.date })
            loadedItems.append(item)
        }
        items = loadedItems.sorted { $0.lastRated > $1.lastRated }
    }

    private func parseRatings(from url: URL) -> [RatingEntry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = contents.split(separator: "\n")
        var entries: [RatingEntry] = []
        for line in lines {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            guard let date = formatter.date(from: String(parts[0])) else { continue }
            guard let value = Int(parts[1]) else { continue }
            entries.append(RatingEntry(date: date, value: value))
        }
        return entries
    }

    private func write(item: RatingItem) {
        let url = baseURL.appendingPathComponent(item.id)
        let lines = item.ratings
            .sorted { $0.date < $1.date }
            .map { "\(formatter.string(from: $0.date))\t\($0.value)" }
            .joined(separator: "\n")
        try? lines.write(to: url, atomically: true, encoding: .utf8)
    }

    private func sanitizeName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "untitled" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.,")
        let sanitizedScalars = trimmed.unicodeScalars.map { scalar -> String in
            if allowed.contains(scalar) {
                return String(scalar)
            }
            return "-"
        }
        let sanitized = sanitizedScalars.joined()
        return sanitized.isEmpty ? "untitled" : sanitized
    }
}

final class ToggleCircleButton: NSButton {
    var isExpanded: Bool = false {
        didSet { updateAppearance() }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 20, height: 20)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        isBordered = false
        title = ""
        setButtonType(.momentaryChange)
        focusRingType = .none
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        layer?.cornerCurve = .continuous
    }

    private func updateAppearance() {
        let symbolName = isExpanded ? "xmark" : "plus"
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .light)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        contentTintColor = .white
        layer?.backgroundColor = (isExpanded ? NSColor.darkGray : NSColor.systemBlue).cgColor
    }
}

final class CircleRatingView: NSView {
    var rating: Double = 0 {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 94, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let circleCount = 5
        let diameter: CGFloat = 12
        let spacing: CGFloat = 7
        let totalWidth = CGFloat(circleCount) * diameter + CGFloat(circleCount - 1) * spacing
        let originX = (bounds.width - totalWidth) / 2
        let originY = (bounds.height - diameter) / 2

        let strokeColor = NSColor.quaternaryLabelColor
        let fillColor = NSColor.systemBlue
        let emptyFill = NSColor.white

        for index in 0..<circleCount {
            let x = originX + CGFloat(index) * (diameter + spacing)
            let rect = NSRect(x: x, y: originY, width: diameter, height: diameter)
            let path = NSBezierPath(ovalIn: rect)
            emptyFill.setFill()
            path.fill()
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            let fillAmount = max(0, min(1, rating - Double(index)))
            guard fillAmount > 0 else { continue }

            NSGraphicsContext.current?.saveGraphicsState()
            path.addClip()
            let fillRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width * fillAmount, height: rect.height)
            fillColor.setFill()
            fillRect.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }
    }
}

final class RatingRowView: NSView {
    var onSelect: (() -> Void)?
    var deleteButton: NSButton?
    private var trackingArea: NSTrackingArea?
    private var deleteTrackingArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) {
        if let deleteButton = deleteButton {
            let location = convert(event.locationInWindow, from: nil)
            if deleteButton.frame.contains(location) {
                return
            }
        }
        super.mouseDown(with: event)
        onSelect?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        if let deleteTrackingArea = deleteTrackingArea {
            removeTrackingArea(deleteTrackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        if let deleteButton = deleteButton {
            let deleteArea = NSTrackingArea(
                rect: deleteButton.frame,
                options: options,
                owner: self,
                userInfo: ["delete": true]
            )
            addTrackingArea(deleteArea)
            deleteTrackingArea = deleteArea
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if event.trackingArea?.userInfo?["delete"] != nil {
            deleteButton?.contentTintColor = NSColor.secondaryLabelColor
            return
        }
        if let deleteButton = deleteButton {
            deleteButton.isHidden = false
            deleteButton.contentTintColor = NSColor.tertiaryLabelColor
        }
    }

    override func mouseExited(with event: NSEvent) {
        if event.trackingArea?.userInfo?["delete"] != nil {
            deleteButton?.contentTintColor = NSColor.tertiaryLabelColor
            return
        }
        if let deleteButton = deleteButton {
            deleteButton.isHidden = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let deleteButton = deleteButton else { return }
        let location = convert(event.locationInWindow, from: nil)
        if deleteButton.frame.contains(location) {
            deleteButton.contentTintColor = NSColor.secondaryLabelColor
        } else {
            deleteButton.contentTintColor = NSColor.tertiaryLabelColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let deleteButton = deleteButton, deleteButton.frame.contains(point) {
            return deleteButton
        }
        return super.hitTest(point)
    }
}

final class RatingDeleteButton: NSButton {
    var itemName: String?
}

final class RatingInputView: NSView {
    var rating: Int = 3 {
        didSet { needsDisplay = true }
    }
    var onSelection: ((Int) -> Void)?
    private var hoverRating: Int? {
        didSet { needsDisplay = true }
    }
    private var trackingArea: NSTrackingArea?

    override var intrinsicContentSize: NSSize {
        NSSize(width: 94, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let circleCount = 5
        let diameter: CGFloat = 12
        let spacing: CGFloat = 7
        let totalWidth = CGFloat(circleCount) * diameter + CGFloat(circleCount - 1) * spacing
        let originX = (bounds.width - totalWidth) / 2
        let originY = (bounds.height - diameter) / 2

        let strokeColor = NSColor.quaternaryLabelColor
        let fillColor = NSColor.systemBlue
        let emptyFill = NSColor.white
        let displayRating = hoverRating ?? rating

        for index in 0..<circleCount {
            let x = originX + CGFloat(index) * (diameter + spacing)
            let rect = NSRect(x: x, y: originY, width: diameter, height: diameter)
            let path = NSBezierPath(ovalIn: rect)
            emptyFill.setFill()
            path.fill()
            strokeColor.setStroke()
            path.lineWidth = 1
            path.stroke()

            if displayRating > index {
                fillColor.setFill()
                path.fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        rating = ratingForPoint(convert(event.locationInWindow, from: nil))
        hoverRating = rating
        onSelection?(rating)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        hoverRating = ratingForPoint(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverRating = nil
    }

    private func ratingForPoint(_ point: NSPoint) -> Int {
        let circleCount = 5
        let diameter: CGFloat = 12
        let spacing: CGFloat = 7
        let totalWidth = CGFloat(circleCount) * diameter + CGFloat(circleCount - 1) * spacing
        let originX = (bounds.width - totalWidth) / 2

        if point.x < originX {
            return 0
        }

        let relativeX = min(max(point.x - originX, 0), totalWidth)
        let index = Int(relativeX / (diameter + spacing))
        return max(1, min(5, index + 1))
    }
}

final class RatedViewController: NSViewController, NSTextFieldDelegate {
    private let store = RatingStore()

    private let baseWidth: CGFloat = 380
    private let containerInset: CGFloat = 8
    private let stackSpacing: CGFloat = 10
    private let headerSpacing: CGFloat = 4
    private let nameField = NSTextField(string: "")
    private let ratingInput = RatingInputView()
    private let listScrollView = NSScrollView()
    private let listStack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "No ratings yet.")
    private let quitButton = NSButton(title: "Quit", target: nil, action: nil)
    private let addToggleButton = ToggleCircleButton()
    private let formStack = NSStackView()
    private let mainStack = NSStackView()
    private let headerBar = NSView()
    private let headerMessageLabel = NSTextField(labelWithString: "")
    private let formContainer = NSView()
    private var formHeightConstraint: NSLayoutConstraint?
    private var listHeightConstraint: NSLayoutConstraint?
    private var quitTrackingArea: NSTrackingArea?
    private let footerBar = NSView()

    override func loadView() {
        let containerSize = NSSize(width: baseWidth, height: 360)
        let container = NSView(frame: NSRect(origin: .zero, size: containerSize))
        preferredContentSize = containerSize

        nameField.placeholderString = "Thing you are rating"
        nameField.font = NSFont.systemFont(ofSize: 13)
        nameField.delegate = self

        ratingInput.onSelection = { [weak self] value in
            self?.addRating(value: value)
        }

        addToggleButton.translatesAutoresizingMaskIntoConstraints = false
        addToggleButton.target = self
        addToggleButton.action = #selector(toggleForm)
        addToggleButton.setContentHuggingPriority(.required, for: .horizontal)
        addToggleButton.setContentHuggingPriority(.required, for: .vertical)

        quitButton.attributedTitle = makeQuitTitle(isHovered: false)
        quitButton.isBordered = false
        quitButton.target = self
        quitButton.action = #selector(quitApp)

        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        ratingInput.setContentHuggingPriority(.required, for: .horizontal)
        ratingInput.widthAnchor.constraint(equalToConstant: 94).isActive = true

        let formSpacer = NSView()
        formSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let formRow = NSStackView(views: [nameField, formSpacer, ratingInput])
        formRow.orientation = .horizontal
        formRow.spacing = 12
        formRow.alignment = .centerY
        formRow.translatesAutoresizingMaskIntoConstraints = false

        formStack.orientation = .vertical
        formStack.alignment = .leading
        formStack.distribution = .fill
        formStack.spacing = 8
        formStack.addArrangedSubview(formRow)
        formRow.widthAnchor.constraint(equalTo: formStack.widthAnchor).isActive = true

        formContainer.translatesAutoresizingMaskIntoConstraints = false
        formContainer.clipsToBounds = true
        formContainer.addSubview(formStack)
        formStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            formStack.topAnchor.constraint(equalTo: formContainer.topAnchor),
            formStack.leadingAnchor.constraint(equalTo: formContainer.leadingAnchor),
            formStack.trailingAnchor.constraint(equalTo: formContainer.trailingAnchor),
            formStack.bottomAnchor.constraint(equalTo: formContainer.bottomAnchor)
        ])
        formHeightConstraint = formContainer.heightAnchor.constraint(equalToConstant: 0)
        formHeightConstraint?.isActive = true

        setupListView()

        listScrollView.documentView = listStack
        listScrollView.hasVerticalScroller = true
        listScrollView.borderType = .noBorder
        listScrollView.drawsBackground = false
        listScrollView.translatesAutoresizingMaskIntoConstraints = false
        listHeightConstraint = listScrollView.heightAnchor.constraint(equalToConstant: 1)
        listHeightConstraint?.isActive = true
        NSLayoutConstraint.activate([
            listStack.leadingAnchor.constraint(equalTo: listScrollView.contentView.leadingAnchor),
            listStack.trailingAnchor.constraint(equalTo: listScrollView.contentView.trailingAnchor),
            listStack.topAnchor.constraint(equalTo: listScrollView.contentView.topAnchor),
            listStack.widthAnchor.constraint(equalTo: listScrollView.contentView.widthAnchor)
        ])

        footerBar.wantsLayer = true
        footerBar.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        footerBar.heightAnchor.constraint(equalToConstant: 30).isActive = true

        let footerSeparator = NSBox()
        footerSeparator.boxType = .separator
        footerSeparator.translatesAutoresizingMaskIntoConstraints = false

        let footerRow = NSStackView(views: [NSView(), quitButton])
        footerRow.orientation = .horizontal
        footerRow.alignment = .centerY
        footerRow.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(footerRow)
        footerBar.addSubview(footerSeparator)
        NSLayoutConstraint.activate([
            footerSeparator.topAnchor.constraint(equalTo: footerBar.topAnchor),
            footerSeparator.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor),
            footerSeparator.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor),

            footerRow.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor, constant: 10),
            footerRow.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -10),
            footerRow.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor)
        ])

        headerBar.translatesAutoresizingMaskIntoConstraints = false
        headerBar.heightAnchor.constraint(equalToConstant: 28).isActive = true
        headerBar.addSubview(addToggleButton)
        headerBar.addSubview(headerMessageLabel)
        headerMessageLabel.alphaValue = 0
        headerMessageLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        headerMessageLabel.textColor = .secondaryLabelColor
        headerMessageLabel.lineBreakMode = .byTruncatingTail
        headerMessageLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            headerMessageLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 8),
            headerMessageLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            headerMessageLabel.trailingAnchor.constraint(lessThanOrEqualTo: addToggleButton.leadingAnchor, constant: -8),
            addToggleButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            addToggleButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            addToggleButton.widthAnchor.constraint(equalToConstant: 20),
            addToggleButton.heightAnchor.constraint(equalToConstant: 20)
        ])

        mainStack.setViews([formContainer, listScrollView], in: .top)
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.distribution = .fill
        mainStack.spacing = stackSpacing
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(headerBar)
        container.addSubview(mainStack)
        container.addSubview(footerBar)

        NSLayoutConstraint.activate([
            headerBar.topAnchor.constraint(equalTo: container.topAnchor),
            headerBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            mainStack.topAnchor.constraint(equalTo: headerBar.bottomAnchor, constant: headerSpacing),
            mainStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: containerInset),
            mainStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -containerInset),
            mainStack.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            formContainer.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            listScrollView.widthAnchor.constraint(equalTo: mainStack.widthAnchor),
            footerBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            footerBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            footerBar.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        view = container
        rebuildList()
        updateFormSpacing(isExpanded: false)
        updatePreferredSize(animated: false)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if (formHeightConstraint?.constant ?? 0) > 0 {
            view.window?.makeFirstResponder(nameField)
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateListHeight()
        updatePreferredSize(animated: false)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if let trackingArea = quitTrackingArea {
            quitButton.removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        quitButton.addTrackingArea(trackingArea)
        quitTrackingArea = trackingArea
        updateListHeight()
        updatePreferredSize(animated: false)
    }

    override func mouseEntered(with event: NSEvent) {
        quitButton.attributedTitle = makeQuitTitle(isHovered: true)
    }

    override func mouseExited(with event: NSEvent) {
        quitButton.attributedTitle = makeQuitTitle(isHovered: false)
    }

    private func setupListView() {
        listStack.orientation = .vertical
        listStack.alignment = .leading
        listStack.spacing = 8
        listStack.translatesAutoresizingMaskIntoConstraints = false
        listStack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)

        emptyLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
    }

    private func addRating(value: Int) {
        let rawName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawName.isEmpty else {
            NSSound.beep()
            return
        }
        if store.addRating(name: rawName, value: value) {
            rebuildList()
            nameField.selectText(nil)
        } else {
            showHeaderMessage("Already rated today.")
            NSSound.beep()
        }
    }

    @objc private func toggleForm() {
        guard let heightConstraint = formHeightConstraint else { return }
        let isCollapsed = heightConstraint.constant == 0
        let targetHeight = isCollapsed ? formStack.fittingSize.height : 0

        if isCollapsed {
            formStack.alphaValue = 0
        }

        updateToggleButton(isExpanded: isCollapsed)
        updateFormSpacing(isExpanded: isCollapsed)
        updatePreferredSize(animated: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            heightConstraint.animator().constant = targetHeight
            formStack.animator().alphaValue = isCollapsed ? 1 : 0
            view.layoutSubtreeIfNeeded()
        }

        if isCollapsed {
            view.window?.makeFirstResponder(nameField)
        } else {
            resetForm()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private var displayItems: [RatingItem] {
        store.items.sorted { $0.lastRated > $1.lastRated }
    }

    private func rebuildList() {
        listStack.arrangedSubviews.forEach { view in
            listStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let items = displayItems
        if items.isEmpty {
            listStack.addArrangedSubview(emptyLabel)
            return
        }

        for (index, item) in items.enumerated() {
            let row = makeRowView(for: item)
            listStack.addArrangedSubview(row)
            if index < items.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
                listStack.addArrangedSubview(separator)
            }
        }
        updateListHeight()
        updatePreferredSize(animated: false)
    }

    private func updatePreferredSize(animated: Bool) {
        view.layoutSubtreeIfNeeded()
        let headerHeight = headerBar.bounds.height > 0 ? headerBar.bounds.height : 28
        let footerHeight = footerBar.bounds.height > 0 ? footerBar.bounds.height : 30
        let contentHeight = headerHeight + headerSpacing + mainStack.fittingSize.height + footerHeight
        let targetSize = NSSize(width: baseWidth, height: contentHeight)
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                self.preferredContentSize = targetSize
            }
        } else {
            preferredContentSize = targetSize
        }
    }

    private func updateFormSpacing(isExpanded: Bool) {
        let spacing = isExpanded ? stackSpacing : 0
        guard mainStack.arrangedSubviews.count >= 1 else { return }
        mainStack.setCustomSpacing(spacing, after: mainStack.arrangedSubviews[0])
    }

    private func makeRowView(for item: RatingItem) -> NSView {
        let nameLabel = NSTextField(labelWithString: item.name)
        nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        nameLabel.lineBreakMode = .byTruncatingTail

        let ratingView = CircleRatingView()
        ratingView.rating = item.averageRating
        ratingView.setContentHuggingPriority(.required, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let deleteButton = RatingDeleteButton(title: "", target: nil, action: nil)
        let deleteConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        deleteButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)?
            .withSymbolConfiguration(deleteConfig)
        deleteButton.image?.isTemplate = true
        deleteButton.contentTintColor = NSColor.tertiaryLabelColor
        deleteButton.isBordered = false
        deleteButton.isHidden = true
        deleteButton.target = self
        deleteButton.action = #selector(deleteRatingItem(_:))
        deleteButton.itemName = item.name
        deleteButton.setButtonType(.momentaryChange)

        let rowStack = NSStackView(views: [deleteButton, nameLabel, spacer, ratingView])
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        let container = RatingRowView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.onSelect = { [weak self] in
            self?.openForm(for: item)
        }
        container.deleteButton = deleteButton
        container.addSubview(rowStack)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            rowStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4)
        ])
        return container
    }

    @objc private func deleteRatingItem(_ sender: RatingDeleteButton) {
        guard let name = sender.itemName else { return }
        store.deleteItem(name: name)
        rebuildList()
    }

    private func openForm(for item: RatingItem) {
        nameField.stringValue = item.name
        ratingInput.rating = 0
        if (formHeightConstraint?.constant ?? 0) == 0 {
            toggleForm()
        } else {
            view.window?.makeFirstResponder(nameField)
        }
    }

    private func resetForm() {
        nameField.stringValue = ""
        ratingInput.rating = 0
    }

    private func updateListHeight() {
        listStack.layoutSubtreeIfNeeded()
        let fittingHeight = listStack.fittingSize.height
        let minHeight: CGFloat = displayItems.isEmpty ? 28 : 0
        listHeightConstraint?.constant = max(fittingHeight, minHeight)
    }

    private func showHeaderMessage(_ text: String) {
        headerMessageLabel.stringValue = text
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            headerMessageLabel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self.headerMessageLabel.animator().alphaValue = 0
            }
        }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === nameField else { return }
        if field.stringValue.count > 15 {
            let endIndex = field.stringValue.index(field.stringValue.startIndex, offsetBy: 15)
            field.stringValue = String(field.stringValue[..<endIndex])
            showHeaderMessage("Limit is 15 characters.")
            NSSound.beep()
        }
    }

    private func makeQuitTitle(isHovered: Bool) -> NSAttributedString {
        let mainColor = isHovered ? NSColor.labelColor : NSColor.secondaryLabelColor
        let hintColor = isHovered ? NSColor.tertiaryLabelColor : NSColor.quaternaryLabelColor

        let quitTitle = NSMutableAttributedString(
            string: "Quit",
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: mainColor
            ]
        )
        let shortcutTitle = NSAttributedString(
            string: "  ⌘Q",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: hintColor
            ]
        )
        quitTitle.append(shortcutTitle)
        return quitTitle
    }

    private func updateToggleButton(isExpanded: Bool) {
        addToggleButton.isExpanded = isExpanded
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let ratedController = RatedViewController()
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandlerRef: EventHandlerRef?
    private var hotKeyHandlerUPP: EventHandlerUPP?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        configureMainMenu()
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(named: "MenuBarTemplate") {
            image.isTemplate = true
            image.size = NSSize(width: 18, height: 18)
            item.button?.image = image
            item.button?.imagePosition = .imageOnly
        } else {
            item.button?.title = "rated"
        }
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        popover.contentViewController = ratedController
        popover.behavior = .transient

        registerGlobalHotKey()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        popover.contentSize = NSSize(width: 380, height: 360)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: "Rated")
        let quitItem = NSMenuItem(title: "Quit Rated", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func registerGlobalHotKey() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x52415445), id: 1) // 'RATE'
        let modifiers: UInt32 = UInt32(controlKey | optionKey | cmdKey)
        let keyCode: UInt32 = 15 // R key

        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, _, _ in
            DispatchQueue.main.async {
                AppDelegate.shared?.togglePopover()
            }
            return noErr
        }
        hotKeyHandlerUPP = handler
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &hotKeyHandlerRef)
    }

    static weak var shared: AppDelegate?
}

let app = NSApplication.shared
let delegate = AppDelegate()
AppDelegate.shared = delegate
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
