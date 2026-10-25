import Foundation
import TimetableCore

// テキスト形式の時刻表を、アプリで読み込める JSON に変換する。書式は scripts/README.md を参照
// 使い方: timetable-convert <入力.txt> [-o <出力.json>]

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var outputPath: String?
if let index = arguments.firstIndex(of: "-o") {
    guard index + 1 < arguments.count else { fail("-o の後に出力先を指定してください") }
    outputPath = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
}
guard arguments.count == 1 else {
    fail("使い方: timetable-convert <入力.txt> [-o <出力.json>]")
}

let inputURL = URL(fileURLWithPath: arguments[0])
guard let text = try? String(contentsOf: inputURL, encoding: .utf8) else {
    fail("\(inputURL.path) を UTF-8 のテキストとして読み込めません")
}

let timetable: Timetable
do {
    timetable = try TimetableTextParser.parse(text)
} catch {
    fail("\(inputURL.lastPathComponent): \(error)")
}

let json: Data
do {
    json = try timetable.encoded()
    // アプリと同じ読み込み処理で検証する
    guard try Timetable.decode(from: json) == timetable else { fail("変換結果の検証に失敗しました") }
} catch {
    fail("変換結果の検証に失敗しました: \(error.localizedDescription)")
}

if let outputPath {
    do {
        try (json + Data("\n".utf8)).write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    } catch {
        fail("\(outputPath) に書き込めません: \(error.localizedDescription)")
    }
    let counts = CalendarKind.allCases
        .compactMap { kind in timetable.calendars[kind].map { "\(kind.displayName) \($0.count) 本" } }
        .joined(separator: "、")
    print("\(outputPath) を作成しました（\(timetable.station.name) \(timetable.line.name) \(timetable.direction.name): \(counts)）")
} else {
    FileHandle.standardOutput.write(json + Data("\n".utf8))
}
