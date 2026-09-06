import Foundation

/// UTF-16 line boundaries of a text, for the line ↔ offset math the editor needs.
nonisolated struct LineIndex {
    private let lineStarts: [Int]
    private let contentEnds: [Int]
    let length: Int

    init(text: String) {
        let units = Array(text.utf16)
        length = units.count
        var starts = [0]
        var ends: [Int] = []
        var index = 0
        while index < units.count {
            let unit = units[index]
            if unit == 0x0A {
                ends.append(index)
                starts.append(index + 1)
            } else if unit == 0x0D {
                ends.append(index)
                if index + 1 < units.count, units[index + 1] == 0x0A { index += 1 }
                starts.append(index + 1)
            }
            index += 1
        }
        ends.append(units.count)
        lineStarts = starts
        contentEnds = ends
    }

    var count: Int { lineStarts.count }

    /// 0-based line containing `offset` (clamped to the text).
    func line(at offset: Int) -> Int {
        let target = min(max(offset, 0), length)
        var low = 0
        var high = lineStarts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStarts[mid] <= target { low = mid } else { high = mid - 1 }
        }
        return low
    }

    /// The line's characters without its line break (clamped to an existing line).
    func range(ofLine line: Int) -> NSRange {
        let index = min(max(line, 0), lineStarts.count - 1)
        return NSRange(location: lineStarts[index], length: contentEnds[index] - lineStarts[index])
    }
}
