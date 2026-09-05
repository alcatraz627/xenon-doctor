import Foundation

/// Valve's KeyValues text format, the shape of every Steam .vdf config file. Keys are
/// quoted strings; a value is either a quoted string or a brace block of more pairs.
/// Order is kept so a rewritten file reads like the one Steam wrote.
final class KVNode {
    var key: String
    var value: String?
    var children: [KVNode]

    init(key: String, value: String? = nil, children: [KVNode] = []) {
        self.key = key
        self.value = value
        self.children = children
    }

    func child(_ key: String) -> KVNode? {
        children.first { $0.key == key }
    }

    /// Walks a path of block keys, creating blocks that are missing, and sets the leaf.
    func set(path: [String], value: String) {
        guard let head = path.first else { return }
        if path.count == 1 {
            if let leaf = child(head) {
                leaf.value = value
                leaf.children = []
            } else {
                children.append(KVNode(key: head, value: value))
            }
            return
        }
        let block: KVNode
        if let existing = child(head), existing.value == nil {
            block = existing
        } else {
            block = KVNode(key: head)
            children.append(block)
        }
        block.set(path: Array(path.dropFirst()), value: value)
    }

    func get(path: [String]) -> String? {
        var node = self
        for k in path {
            guard let next = node.child(k) else { return nil }
            node = next
        }
        return node.value
    }
}

enum KeyValues {
    enum ParseError: Error { case unexpectedEnd, unexpectedToken(String) }

    private enum Token: Equatable { case open, close, string(String) }

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(text.unicodeScalars)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "{" { tokens.append(.open); i += 1; continue }
            if c == "}" { tokens.append(.close); i += 1; continue }
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "\"" {
                i += 1
                var s = String.UnicodeScalarView()
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        let n = chars[i + 1]
                        switch n {
                        case "n": s.append("\n")
                        case "t": s.append("\t")
                        case "\\": s.append("\\")
                        case "\"": s.append("\"")
                        default: s.append("\\"); s.append(n)
                        }
                        i += 2
                        continue
                    }
                    s.append(chars[i])
                    i += 1
                }
                i += 1
                tokens.append(.string(String(s)))
                continue
            }
            if CharacterSet.whitespacesAndNewlines.contains(c) { i += 1; continue }
            var s = String.UnicodeScalarView()
            while i < chars.count && !CharacterSet.whitespacesAndNewlines.contains(chars[i]) && chars[i] != "{" && chars[i] != "}" {
                s.append(chars[i]); i += 1
            }
            tokens.append(.string(String(s)))
        }
        return tokens
    }

    /// Parses a whole file into a synthetic root whose children are the top-level pairs.
    static func parse(_ text: String) throws -> KVNode {
        let tokens = tokenize(text)
        var i = 0
        func parseBlock(into node: KVNode) throws {
            while i < tokens.count {
                switch tokens[i] {
                case .close:
                    i += 1
                    return
                case .open:
                    throw ParseError.unexpectedToken("{")
                case .string(let key):
                    i += 1
                    guard i < tokens.count else { throw ParseError.unexpectedEnd }
                    switch tokens[i] {
                    case .open:
                        i += 1
                        let child = KVNode(key: key)
                        try parseBlock(into: child)
                        node.children.append(child)
                    case .string(let v):
                        i += 1
                        node.children.append(KVNode(key: key, value: v))
                    case .close:
                        throw ParseError.unexpectedToken("}")
                    }
                }
            }
        }
        let root = KVNode(key: "")
        try parseBlock(into: root)
        return root
    }

    private static func escape(_ s: String) -> String {
        var out = ""
        for ch in s {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Writes the tree back in Steam's own layout: tabs for depth, two tabs between key and value.
    static func serialize(_ root: KVNode) -> String {
        var out = ""
        func write(_ node: KVNode, depth: Int) {
            let indent = String(repeating: "\t", count: depth)
            if let v = node.value {
                out += "\(indent)\"\(escape(node.key))\"\t\t\"\(escape(v))\"\n"
            } else {
                out += "\(indent)\"\(escape(node.key))\"\n\(indent){\n"
                for c in node.children { write(c, depth: depth + 1) }
                out += "\(indent)}\n"
            }
        }
        for c in root.children { write(c, depth: 0) }
        return out
    }
}
