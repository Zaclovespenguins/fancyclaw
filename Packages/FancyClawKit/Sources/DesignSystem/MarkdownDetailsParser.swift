import Foundation

/// Recognizes only details/summary boundaries. Textual still parses all Markdown within each segment.
enum MarkdownDetailsParser {
    static func segments(in source: String) -> [MarkdownSegment] {
        let bytes = Array(source.utf8)
        let tags = tags(in: bytes)
        var stack: [Int] = []
        var pairs: [Int: Int] = [:]
        for index in tags.indices {
            if !tags[index].closing { stack.append(index) }
            else if let start = stack.last, tags[start].name == tags[index].name {
                pairs[start] = index
                stack.removeLast()
            }
        }
        return segments(bytes, range: 0..<bytes.count, tags: tags, indices: tags.indices, pairs: pairs, depth: 0)
    }

    private static func segments(_ bytes: [UInt8], range: Range<Int>, tags: [Tag], indices: Range<Int>,
                                 pairs: [Int: Int], depth: Int) -> [MarkdownSegment] {
        // Bound recursive view construction for unusually deeply nested model output.
        guard depth < 32 else { return markdown(bytes, range: range).map { [$0] } ?? [] }
        var result: [MarkdownSegment] = []
        var cursor = range.lowerBound
        var index = indices.lowerBound
        while index < indices.upperBound {
            let tag = tags[index]
            guard tag.name == "details", !tag.closing else { index += 1; continue }
            // Leave incomplete streamed sections untouched until their matching close arrives.
            guard let end = pairs[index], end < indices.upperBound else { break }
            var bodyStart = tag.end
            var bodyIndex = index + 1
            var summary = "Details"
            if bodyIndex < end, tags[bodyIndex].name == "summary", !tags[bodyIndex].closing,
               text(bytes, tag.end..<tags[bodyIndex].start).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                guard let summaryEnd = pairs[bodyIndex], summaryEnd < end else { index = end + 1; continue }
                let label = text(bytes, tags[bodyIndex].end..<tags[summaryEnd].start)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty { summary = label }
                bodyStart = tags[summaryEnd].end
                bodyIndex = summaryEnd + 1
            }
            if let before = markdown(bytes, range: cursor..<tag.start) { result.append(before) }
            let children = segments(bytes, range: bodyStart..<tags[end].start, tags: tags,
                indices: bodyIndex..<end, pairs: pairs, depth: depth + 1)
            result.append(.init(id: tag.start,
                content: .details(summary: summary, segments: children, initiallyExpanded: tag.open)))
            cursor = tags[end].end
            index = end + 1
        }
        if let tail = markdown(bytes, range: cursor..<range.upperBound) { result.append(tail) }
        return result
    }

    private static func markdown(_ bytes: [UInt8], range: Range<Int>) -> MarkdownSegment? {
        let source = text(bytes, range)
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .init(id: range.lowerBound, content: .markdown(source))
    }

    private static func text(_ bytes: [UInt8], _ range: Range<Int>) -> String {
        String(decoding: bytes[range], as: UTF8.self)
    }

    private struct Tag {
        let name: String
        let closing: Bool
        let open: Bool
        let start: Int
        let end: Int
    }

    private static func tags(in bytes: [UInt8]) -> [Tag] {
        var result: [Tag] = []
        var index = 0
        var lineStart = true
        var fence: (marker: UInt8, length: Int)?
        while index < bytes.count {
            if lineStart {
                let lineEnd = bytes[index...].firstIndex(of: 10) ?? bytes.count
                var marker = index
                while marker < lineEnd, bytes[marker] == 32 { marker += 1 }
                let indentation = marker - index
                if let active = fence {
                    let end = runEnd(bytes, from: marker, marker: active.marker)
                    if indentation <= 3, end - marker >= active.length,
                       bytes[end..<lineEnd].allSatisfy(isWhitespace) { fence = nil }
                    index = lineEnd < bytes.count ? lineEnd + 1 : lineEnd
                    continue
                }
                if indentation >= 4 || (marker < lineEnd && bytes[marker] == 9) {
                    index = lineEnd < bytes.count ? lineEnd + 1 : lineEnd
                    continue
                }
                if marker < lineEnd, bytes[marker] == 96 || bytes[marker] == 126 {
                    let end = runEnd(bytes, from: marker, marker: bytes[marker])
                    if end - marker >= 3,
                       bytes[marker] != 96 || !bytes[end..<lineEnd].contains(96) {
                        fence = (bytes[marker], end - marker)
                        index = lineEnd < bytes.count ? lineEnd + 1 : lineEnd
                        continue
                    }
                }
                lineStart = false
            }
            if bytes[index] == 10 { lineStart = true; index += 1 }
            else if bytes[index] == 92 { index = min(index + 2, bytes.count) }
            else if bytes[index] == 96 {
                let end = runEnd(bytes, from: index, marker: 96)
                index = codeSpanEnd(bytes, from: end, length: end - index) ?? end
            } else if bytes[index] == 60 {
                if bytes[index...].starts(with: [60, 33, 45, 45]) {
                    index += 4
                    while index < bytes.count, !bytes[index...].starts(with: [45, 45, 62]) { index += 1 }
                    index = min(index + 3, bytes.count)
                } else if let tag = tag(in: bytes, from: index) {
                    result.append(tag)
                    index = tag.end
                } else { index += 1 }
            } else { index += 1 }
        }
        return result
    }

    private static func runEnd(_ bytes: [UInt8], from start: Int, marker: UInt8) -> Int {
        var end = start
        while end < bytes.count, bytes[end] == marker { end += 1 }
        return end
    }

    private static func codeSpanEnd(_ bytes: [UInt8], from start: Int, length: Int) -> Int? {
        var index = start
        while index < bytes.count {
            if bytes[index] == 96 {
                let end = runEnd(bytes, from: index, marker: 96)
                if end - index == length { return end }
                index = end
            } else { index += 1 }
        }
        return nil
    }

    private static func tag(in bytes: [UInt8], from start: Int) -> Tag? {
        var index = start + 1
        guard index < bytes.count else { return nil }
        let closing = bytes[index] == 47
        if closing { index += 1 }
        let nameStart = index
        while index < bytes.count, isLetter(bytes[index]) { index += 1 }
        let name = text(bytes, nameStart..<index).lowercased()
        guard name == "details" || name == "summary", index < bytes.count,
              isWhitespace(bytes[index]) || bytes[index] == 62 else { return nil }
        var open = false
        while index < bytes.count {
            while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
            guard index < bytes.count else { return nil }
            if bytes[index] == 62 { return Tag(name: name, closing: closing, open: open, start: start, end: index + 1) }
            let attributeStart = index
            while index < bytes.count, !isWhitespace(bytes[index]), ![61, 62, 47].contains(bytes[index]) { index += 1 }
            guard index > attributeStart else { return nil }
            if text(bytes, attributeStart..<index).lowercased() == "open" { open = true }
            while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
            if index < bytes.count, bytes[index] == 61 {
                index += 1
                while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
                guard index < bytes.count else { return nil }
                if bytes[index] == 34 || bytes[index] == 39 {
                    let quote = bytes[index]
                    index += 1
                    while index < bytes.count, bytes[index] != quote { index += 1 }
                    guard index < bytes.count else { return nil }
                    index += 1
                } else {
                    while index < bytes.count, !isWhitespace(bytes[index]), bytes[index] != 62 { index += 1 }
                }
            }
        }
        return nil
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool { [9, 10, 13, 32].contains(byte) }
    private static func isLetter(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) }
}
