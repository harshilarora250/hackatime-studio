import SwiftUI

private nonisolated struct SpanKey: LayoutValueKey {
    static let defaultValue: Int = 1
}

extension View {
    func gridSpan(_ span: Int) -> some View { layoutValue(key: SpanKey.self, value: span) }
}

/// Packs widgets into rows of `columns` units. Items in a row share the tallest item's height,
/// so tiles line up without fixed heights.
struct WidgetGrid: Layout {
    var spacing: CGFloat = 16
    var minColumnWidth: CGFloat = 200

    private func columns(for width: CGFloat) -> Int { width >= minColumnWidth * 4 + spacing * 3 ? 4 : 2 }

    private func rows(_ subviews: Subviews, columns: Int) -> [[(Int, Int)]] {
        var rows: [[(Int, Int)]] = [[]]
        var used = 0
        for (i, sub) in subviews.enumerated() {
            let span = min(max(sub[SpanKey.self], 1), columns)
            if used + span > columns { rows.append([]); used = 0 }
            rows[rows.count - 1].append((i, span))
            used += span
        }
        return rows.filter { !$0.isEmpty }
    }

    private func itemWidth(_ span: Int, unit: CGFloat) -> CGFloat { unit * CGFloat(span) + spacing * CGFloat(span - 1) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 900
        let cols = columns(for: width)
        let unit = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        var height: CGFloat = 0
        for row in rows(subviews, columns: cols) {
            let h = row.map { subviews[$0.0].sizeThatFits(.init(width: itemWidth($0.1, unit: unit), height: nil)).height }.max() ?? 0
            height += h + spacing
        }
        return CGSize(width: width, height: max(0, height - spacing))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columns(for: bounds.width)
        let unit = (bounds.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
        var y = bounds.minY
        for row in rows(subviews, columns: cols) {
            let h = row.map { subviews[$0.0].sizeThatFits(.init(width: itemWidth($0.1, unit: unit), height: nil)).height }.max() ?? 0
            var x = bounds.minX
            for (index, span) in row {
                let w = itemWidth(span, unit: unit)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: .init(width: w, height: h))
                x += w + spacing
            }
            y += h + spacing
        }
    }
}
