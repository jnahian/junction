import Foundation

/// Converts JSONC (JSON with `//` and `/* */` comments and trailing commas) to strict JSON.
/// String literals are preserved verbatim, including escape sequences.
public enum JSONC {
    public static func toStrictJSON(_ input: String) -> String {
        var out = String.UnicodeScalarView()
        out.reserveCapacity(input.unicodeScalars.count)
        let scalars = Array(input.unicodeScalars)
        var i = 0
        var inString = false

        while i < scalars.count {
            let c = scalars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < scalars.count {
                    out.append(scalars[i + 1])
                    i += 2
                    continue
                }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            switch c {
            case "\"":
                inString = true
                out.append(c)
                i += 1
            case "/":
                if i + 1 < scalars.count, scalars[i + 1] == "/" {
                    while i < scalars.count, scalars[i] != "\n" { i += 1 }
                } else if i + 1 < scalars.count, scalars[i + 1] == "*" {
                    i += 2
                    while i + 1 < scalars.count, !(scalars[i] == "*" && scalars[i + 1] == "/") { i += 1 }
                    i = min(i + 2, scalars.count)
                } else {
                    out.append(c)
                    i += 1
                }
            case ",":
                // Trailing comma: look ahead past whitespace for `}` or `]`.
                var j = i + 1
                while j < scalars.count, CharacterSet.whitespacesAndNewlines.contains(scalars[j]) { j += 1 }
                if j < scalars.count, scalars[j] == "}" || scalars[j] == "]" {
                    i += 1 // drop the comma
                } else {
                    out.append(c)
                    i += 1
                }
            default:
                out.append(c)
                i += 1
            }
        }
        return String(String.UnicodeScalarView(out))
    }

    public static func data(from jsoncData: Data) -> Data {
        guard let text = String(data: jsoncData, encoding: .utf8) else { return jsoncData }
        return Data(toStrictJSON(text).utf8)
    }
}
