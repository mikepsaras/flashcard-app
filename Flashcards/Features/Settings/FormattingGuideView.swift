import SwiftUI

/// A reference for the markdown + LaTeX a card supports. Every example is rendered through the real
/// engine (`MarkdownText`/`MathDisplayView`), so it doubles as a live demo. Reached from the macOS
/// Help menu (⌘?) and from Settings on iOS.
struct FormattingGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                intro

                group("Text styling") {
                    example("**bold**, *italic*, ~~strikethrough~~, and `inline code`.")
                    example("A [link](https://apple.com) to somewhere.")
                }
                group("Headings") {
                    example("# Heading one\n## Heading two\n### Heading three")
                }
                group("Lists") {
                    example("- a bullet\n- another\n  - nested bullet")
                    example("1. first\n2. second\n3. third")
                }
                group("Quotes, code & dividers") {
                    example("> A blockquote for emphasis.")
                    example("```\nlet x = 42\nprint(x)\n```")
                    example("Above\n\n---\n\nBelow")
                }
                group("Math — inline") {
                    example("Mass–energy: $E = mc^2$, and Euler's identity $e^{i\\pi} + 1 = 0$.")
                }
                group("Math — display") {
                    example("$$\\int_0^{\\infty} e^{-x^2}\\,dx = \\frac{\\sqrt{\\pi}}{2}$$")
                }

                latexCheatSheet
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.groupedBackground)
        #if os(iOS)
        .navigationTitle("Formatting")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Formatting")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Card fronts and backs support Markdown and LaTeX math. Type the syntax on the left; "
                 + "it renders as shown on the right. Wrap math in $…$ to flow inline, or $$…$$ for a "
                 + "centered equation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func group(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(.headline, design: .rounded)).foregroundStyle(.secondary)
            content()
        }
    }

    /// One example: the literal source above the live render.
    private func example(_ source: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(source)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            MarkdownText(text: source, baseSize: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.fieldSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private var latexCheatSheet: some View {
        let items: [(latex: String, label: String)] = [
            ("x^{2}", "superscript"),
            ("x_{i}", "subscript"),
            ("\\frac{a}{b}", "fraction"),
            ("\\sqrt{x}", "square root"),
            ("\\sqrt[3]{x}", "nth root"),
            ("\\sum_{i=1}^{n} i", "sum"),
            ("\\int_{a}^{b} f", "integral"),
            ("\\lim_{x \\to 0}", "limit"),
            ("\\alpha\\ \\beta\\ \\pi", "Greek letters"),
            ("\\times\\ \\div\\ \\pm", "operators"),
            ("\\leq\\ \\geq\\ \\neq", "relations"),
            ("\\vec{v}\\ \\hat{x}\\ \\bar{y}", "accents"),
            ("\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", "matrix"),
        ]
        return group("Common LaTeX") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    if index > 0 { Divider() }
                    HStack(alignment: .center, spacing: 14) {
                        Text(item.latex)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(width: 190, alignment: .leading)
                        MathDisplayView(latex: item.latex, fontSize: 19)
                        Spacer(minLength: 8)
                        Text(item.label).font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 9)
                }
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fieldSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
        }
    }
}
