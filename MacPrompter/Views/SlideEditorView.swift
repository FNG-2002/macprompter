import AppKit
import SwiftUI

/// Per-slide script editor. The prompter text is derived from these sections.
struct SlideEditorView: View {
    @Bindable var model: AppModel
    let script: Script
    let deck: PresentationDeck
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Label("FOLIEN", systemImage: "rectangle.on.rectangle").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                Spacer()
                if model.isUpdatingPresentation { ProgressView().controlSize(.small) }
                Label("\(deck.fileName) · \(deck.pages.count) Seiten", systemImage: "doc.richtext")
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                if deck.bookmark != nil {
                    Button { Task { await model.refreshPresentation(force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("PDF neu einlesen")
                }
            }.padding(.horizontal, 30).padding(.top, 28)
            TextField("Titel deiner Präsentation", text: Binding(get: { model.library.selected?.title ?? "" }, set: { model.updateScript(title: $0) }))
                .textFieldStyle(.plain).font(.system(size: 30, weight: .semibold)).padding(.horizontal, 30).padding(.top, 22).padding(.bottom, 12)
            if let change = model.presentationChange, change.scriptID == script.id {
                banner(change.change)
            } else if deck.hasFlags {
                banner(nil)
            }
            ScrollView {
                LazyVStack(spacing: 12) {
                    let numbers = slideNumbers
                    ForEach(Array(deck.sections.enumerated()), id: \.element.id) { index, section in
                        SectionCard(model: model, deck: deck, section: section, slide: numbers[index], isLast: index == deck.sections.count - 1)
                    }
                }.padding(.horizontal, 30).padding(.vertical, 8)
            }
            HStack(spacing: 7) {
                Image(systemName: "rectangle.stack")
                Text("Jede Folie endet mit [Nächste Folie]. Mehrere PDF-Seiten einer Folie (Aufdecken) wechseln bei [Weiter], sonst gleichmäßig nach Wörtern.")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 30).padding(.vertical, 18)
        }
        .task(id: script.id) { await model.refreshPresentation() }
    }

    /// Slides are numbered by section; sections without pages get no number.
    private var slideNumbers: [Int?] {
        var next = 0
        return deck.sections.map { section in
            guard !section.pageIDs.isEmpty else { return nil }
            defer { next += 1 }
            return next
        }
    }

    private func banner(_ change: PresentationChange?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Design.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(change == nil ? "Markierte Folien prüfen" : "PDF aktualisiert · \(change!.summary)").font(.system(size: 12, weight: .medium))
                Text("Texte bleiben ihren Folien zugeordnet. Neue Folien haben noch keinen Text.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Erledigt") { model.dismissPresentationChange() }.controlSize(.small)
        }
        .padding(12).background(Design.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 30).padding(.bottom, 10)
    }
}

private struct SectionCard: View {
    let model: AppModel
    let deck: PresentationDeck
    let section: SlideSection
    let slide: Int?
    let isLast: Bool
    var body: some View {
        let pages = deck.pageIndices(of: section)
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                thumbnails(pages)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label(pages)).font(.system(size: 12, weight: .semibold))
                    if let detail = pageDetail(pages) { Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary) }
                }
                ForEach(flags(pages), id: \.self) { flag in
                    Text(flag.title).font(.system(size: 10, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3)
                        .background(flag.color.opacity(0.18), in: Capsule()).foregroundStyle(flag.color)
                }
            }.frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                SectionTextEditor(text: Binding(get: { section.text }, set: { text in
                    model.editPresentation { $0.setText(text, section: section.id) }
                }), label: label(pages))
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                HStack(spacing: 14) {
                    Text(isLast ? PresentationComposer.endMarker : PresentationComposer.nextMarker)
                        .font(.system(size: 11).italic()).foregroundStyle(.tertiary)
                    if section.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !pages.isEmpty {
                        Text("Ohne Text wird die Folie im Sprachmodus übersprungen.").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if pages.count > 1 {
                        Button { model.editPresentation { $0.ungroup(section.id) } } label: { Label("Schritte trennen", systemImage: "square.split.2x1") }
                            .help("Jede PDF-Seite wird wieder eine eigene Folie")
                    }
                    if !isLast && !pages.isEmpty {
                        Button { model.editPresentation { $0.groupWithNext(section.id) } } label: { Label("Nächste Seite als Schritt", systemImage: "link") }
                            .help("Die nächste PDF-Seite gehört zu dieser Folie, z. B. beim schrittweisen Aufdecken")
                    }
                    if pages.isEmpty {
                        Button(role: .destructive) { model.editPresentation { $0.removeOrphan(section.id) } } label: { Label("Abschnitt löschen", systemImage: "trash") }
                    }
                }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Design.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Design.border))
    }

    private func label(_ pages: [Int]) -> String {
        guard let slide, !pages.isEmpty else { return "Ohne Folie" }
        return pages.count > 1 ? "Folie \(slide + 1) · \(pages.count) Schritte" : "Folie \(slide + 1)"
    }

    private func pageDetail(_ pages: [Int]) -> String? {
        guard let first = pages.first, let last = pages.last else { return nil }
        return first == last ? "PDF-Seite \(first + 1)" : "PDF-Seiten \(first + 1)–\(last + 1)"
    }

    @ViewBuilder private func thumbnails(_ pages: [Int]) -> some View {
        if let first = pages.first {
            ZStack(alignment: .topLeading) {
                ForEach(Array(pages.prefix(3).enumerated().reversed()), id: \.element) { offset, page in
                    thumbnail(page).offset(x: CGFloat(offset) * 6, y: CGFloat(offset) * 6)
                }
            }
            .padding(.trailing, CGFloat(min(pages.count, 3) - 1) * 6).padding(.bottom, CGFloat(min(pages.count, 3) - 1) * 6)
            .accessibilityLabel(label(pages))
            .id(first)
        } else {
            RoundedRectangle(cornerRadius: 6).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                .foregroundStyle(.tertiary).frame(width: 138, height: 78)
                .overlay(Image(systemName: "rectangle.slash").foregroundStyle(.tertiary))
        }
    }

    private func thumbnail(_ page: Int) -> some View {
        Group {
            if let image = model.presentationFiles.thumbnail(deck, page: page, width: 138) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else {
                Color.black
            }
        }
        .frame(width: 138, height: 78).background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Design.border))
    }

    private enum Flag: Hashable {
        case added, changed, removed
        var title: String {
            switch self { case .added: "Neu"; case .changed: "Geändert · prüfen"; case .removed: "Folie entfernt" }
        }
        var color: Color {
            switch self { case .added: Design.accent; case .changed: .orange; case .removed: .red }
        }
    }

    private func flags(_ pages: [Int]) -> [Flag] {
        if pages.isEmpty { return [.removed] }
        let marks = pages.compactMap { deck.pages[$0].flag }
        return (marks.contains(.added) ? [Flag.added] : []) + (marks.contains(.changed) ? [.changed] : [])
    }
}

/// Plain-text editor that grows with its content inside the section list.
struct SectionTextEditor: NSViewRepresentable {
    @Binding var text: String
    let label: String
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextView {
        let editor = NSTextView()
        editor.isRichText = false; editor.allowsUndo = true; editor.drawsBackground = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.textContainerInset = NSSize(width: 8, height: 10)
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = false
        editor.insertionPointColor = .white
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel("Text für \(label)")
        editor.string = text
        ScriptEditor.style(editor, size: 15)
        return editor
    }
    func updateNSView(_ editor: NSTextView, context: Context) {
        context.coordinator.parent = self
        if editor.string != text {
            editor.string = text
            ScriptEditor.style(editor, size: 15)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, let container = nsView.textContainer, let manager = nsView.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(1, width - nsView.textContainerInset.width * 2), height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height + nsView.textContainerInset.height * 2
        return CGSize(width: width, height: max(78, ceil(height)))
    }
    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SectionTextEditor
        init(_ parent: SectionTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
            if !editor.hasMarkedText() { ScriptEditor.style(editor, size: 15) }
        }
    }
}
