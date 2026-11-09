import SwiftUI

/// Example scripts to look at and copy into the library under an own name.
struct TemplateGallery: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selection = ScriptTemplate.all[0].id
    @State private var name = ScriptTemplate.all[0].title
    @State private var creating = false

    private var template: ScriptTemplate { ScriptTemplate.all.first { $0.id == selection } ?? ScriptTemplate.all[0] }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vorlagen").font(.system(size: 22, weight: .semibold))
                Text("Sieh dir ein Beispiel an und übernimm es als eigenes Skript. Die Vorlage selbst bleibt unverändert.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(ScriptTemplate.all) { item in card(item) }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("VORSCHAU").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                ScrollView {
                    Text(AttributedString(ScriptStyle.attributed(template.preview, font: .systemFont(ofSize: 13), spacing: 4, color: NSColor(white: 0.85, alpha: 1))))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .textSelection(.enabled)
                }
                .frame(height: 170)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack(spacing: 12) {
                TextField("Name des neuen Skripts", text: $name).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                    .onSubmit(create)
                Spacer()
                if creating { ProgressView().controlSize(.small) }
                Button("Abbrechen", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Als Skript anlegen", action: create).keyboardShortcut(.defaultAction).disabled(creating)
            }
        }
        .padding(26)
        .frame(width: 760)
        .background(Design.canvas)
        .tint(Design.accent)
    }

    private func card(_ item: ScriptTemplate) -> some View {
        let selected = item.id == selection
        return Button {
            selection = item.id; name = item.title
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: item.symbol).font(.system(size: 20)).foregroundStyle(Design.accent)
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.summary).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineLimit(4)
                Spacer(minLength: 0)
                Text(item.details).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(selected ? Design.accent.opacity(0.12) : Design.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Design.accent.opacity(0.7) : Design.border))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.title). \(item.summary)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func create() {
        guard !creating else { return }
        creating = true
        Task {
            await model.createScript(from: template, title: name)
            creating = false
            dismiss()
        }
    }
}
