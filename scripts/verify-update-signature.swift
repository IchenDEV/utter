#!/usr/bin/env swift
// Independently verify a Sparkle EdDSA signature with CryptoKit.
//
// The release pipeline signs the DMG and the appcast feed with Sparkle's
// `sign_update` and then runs this verifier against the public key shipped
// inside the app. A wrong or rotated SPARKLE_ED_PRIVATE_KEY therefore fails
// before publish instead of stranding every installed copy.
//
//   verify-update-signature.swift --public-key KEY --dmg FILE --signature SIG
//   verify-update-signature.swift --public-key KEY --feed FILE
//
// A signed feed is the RSS payload followed by a trailing
// `<!-- sparkle-signatures: edSignature: … length: … -->` comment.

import CryptoKit
import Foundation

let usage = """
usage: verify-update-signature.swift --public-key BASE64 \\
         (--dmg FILE --signature BASE64 | --feed FILE)
"""

struct Options {
    var publicKey = ""
    var dmg: String?
    var signature: String?
    var feed: String?
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func parse(_ arguments: [String]) -> Options {
    var options = Options()
    var index = 0
    func value(for flag: String) -> String {
        index += 1
        guard index < arguments.count else { fail("missing value for \(flag)") }
        return arguments[index]
    }
    while index < arguments.count {
        let argument = arguments[index]
        switch argument {
        case "--public-key": options.publicKey = value(for: argument)
        case "--dmg": options.dmg = value(for: argument)
        case "--signature": options.signature = value(for: argument)
        case "--feed": options.feed = value(for: argument)
        case "--help", "-h":
            print(usage)
            exit(0)
        default:
            fail("unknown argument: \(argument)\n\(usage)")
        }
        index += 1
    }
    return options
}

func decodedBase64(_ text: String, name: String) -> Data {
    guard let data = Data(base64Encoded: text, options: []) else {
        fail("\(name) is not valid base64")
    }
    return data
}

func publicKey(_ text: String) -> Curve25519.Signing.PublicKey {
    let raw = decodedBase64(text, name: "the public key")
    guard raw.count == 32 else { fail("the public key must be 32 bytes, got \(raw.count)") }
    do {
        return try Curve25519.Signing.PublicKey(rawRepresentation: raw)
    } catch {
        fail("the public key is not a valid Ed25519 key: \(error)")
    }
}

func read(_ path: String) -> Data {
    guard let data = FileManager.default.contents(atPath: path) else {
        fail("cannot read \(path)")
    }
    return data
}

func verify(_ signature: Data, over payload: Data, with key: Curve25519.Signing.PublicKey,
            describedAs subject: String) {
    guard signature.count == 64 else {
        fail("the signature must be 64 bytes, got \(signature.count)")
    }
    guard key.isValidSignature(signature, for: payload) else {
        fail("the signature does not match \(subject)")
    }
    print("signature verified: \(subject) (\(payload.count) bytes)")
}

let options = parse(Array(CommandLine.arguments.dropFirst()))
guard !options.publicKey.isEmpty else { fail("--public-key is required\n\(usage)") }
guard (options.feed == nil) != (options.dmg == nil) else {
    fail("pass exactly one of --dmg or --feed\n\(usage)")
}
let key = publicKey(options.publicKey)

if let dmg = options.dmg {
    guard let signature = options.signature else { fail("--dmg requires --signature") }
    verify(decodedBase64(signature, name: "the signature"), over: read(dmg), with: key,
           describedAs: (dmg as NSString).lastPathComponent)
    exit(0)
}

guard let feed = options.feed else { fail("--feed is required") }
guard options.signature == nil else { fail("--signature only applies with --dmg\n\(usage)") }

let marker = "<!-- sparkle-signatures:".data(using: .utf8)!
let contents = read(feed)
guard let markerRange = contents.range(of: marker, options: .backwards) else {
    fail("\(feed) has no trailing sparkle-signatures comment")
}
let payload = contents[contents.startIndex..<markerRange.lowerBound]
let block = String(decoding: contents[markerRange.lowerBound...], as: UTF8.self)

func field(_ name: String) -> String? {
    for line in block.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\(name):") else { continue }
        return trimmed.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
    }
    return nil
}

guard let signatureText = field("edSignature") else {
    fail("\(feed) has no edSignature in its signature block")
}
guard let lengthText = field("length") else {
    fail("\(feed) has no length in its signature block")
}
guard let declared = Int(lengthText) else {
    fail("\(feed) declares a non-numeric length: \(lengthText)")
}
guard declared == payload.count else {
    fail("\(feed) declares length \(declared) but its signed payload is \(payload.count) bytes")
}

verify(decodedBase64(signatureText, name: "the feed signature"), over: Data(payload), with: key,
       describedAs: (feed as NSString).lastPathComponent)
