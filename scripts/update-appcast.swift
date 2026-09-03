#!/usr/bin/env swift

import Foundation

enum AppcastError: Error, CustomStringConvertible {
    case invalidArguments
    case invalidValue(name: String)
    case invalidTemplate

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: update-appcast.swift <appcast> <version> <build> <signature> <length>"
        case let .invalidValue(name):
            return "invalid \(name)"
        case .invalidTemplate:
            return "appcast is missing the release insertion marker"
        }
    }
}

func updateAppcast(arguments: [String]) throws {
    guard arguments.count == 6 else {
        throw AppcastError.invalidArguments
    }

    let appcastURL = URL(fileURLWithPath: arguments[1])
    let version = arguments[2]
    let build = arguments[3]
    let signature = arguments[4]
    let length = arguments[5]
    guard version.range(of: #"^[0-9]+(?:\.[0-9]+)*$"#, options: .regularExpression) != nil else {
        throw AppcastError.invalidValue(name: "version")
    }
    guard let buildNumber = Int(build), buildNumber >= 0 else {
        throw AppcastError.invalidValue(name: "build")
    }
    guard let signatureData = Data(base64Encoded: signature), signatureData.count == 64 else {
        throw AppcastError.invalidValue(name: "signature")
    }
    guard let archiveLength = Int(length), archiveLength > 0 else {
        throw AppcastError.invalidValue(name: "length")
    }
    let marker = "    <!-- Releases are inserted below this line. -->"
    var appcast = try String(contentsOf: appcastURL, encoding: .utf8)

    guard appcast.contains(marker) else {
        throw AppcastError.invalidTemplate
    }
    let buildElement = "<sparkle:version>\(build)</sparkle:version>"
    let itemPattern = #"(?s)\n    <item>.*?</item>"#
    let itemExpression = try NSRegularExpression(pattern: itemPattern)
    let appcastRange = NSRange(appcast.startIndex..., in: appcast)
    if let existingItem = itemExpression.matches(in: appcast, range: appcastRange).first(where: { match in
        guard let range = Range(match.range, in: appcast) else { return false }
        return appcast[range].contains(buildElement)
    }), let range = Range(existingItem.range, in: appcast) {
        appcast.removeSubrange(range)
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    let publicationDate = formatter.string(from: Date())
    let releaseURL = "https://github.com/jamesqquick/QuickTab/releases/tag/v\(version)"
    let downloadURL = "https://github.com/jamesqquick/QuickTab/releases/download/v\(version)/QuickTab.dmg"
    let item = """

        <item>
          <title>QuickTab \(version)</title>
          <link>\(releaseURL)</link>
          <sparkle:version>\(build)</sparkle:version>
          <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
          <pubDate>\(publicationDate)</pubDate>
          <description sparkle:format="plain-text">See the GitHub release for details.</description>
          <enclosure
            url="\(downloadURL)"
            type="application/octet-stream"
            sparkle:edSignature="\(signature)"
            length="\(length)"
          />
        </item>
    """

    appcast.replace(marker, with: marker + item)
    try appcast.write(to: appcastURL, atomically: true, encoding: .utf8)
}

do {
    try updateAppcast(arguments: CommandLine.arguments)
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
