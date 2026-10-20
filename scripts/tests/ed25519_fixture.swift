#!/usr/bin/env swift
// Throwaway Ed25519 material for test_verify_update_signature.sh. A fresh key is
// generated on every run, so nothing in the test depends on a stored secret.
//
// usage: ed25519_fixture.swift OUTDIR
//
// Writes: public.txt, other-public.txt, payload.bin, payload.sig,
//         payload-tampered.bin, feed.xml, feed-tampered.xml, feed-unsigned.xml,
//         feed-bad-length.xml, short-signature.txt, malformed-signature.txt

import CryptoKit
import Foundation

let usage = "usage: ed25519_fixture.swift OUTDIR"

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("\(usage)\n".utf8))
    exit(1)
}

let outdir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outdir, withIntermediateDirectories: true)

func write(_ name: String, _ contents: Data) {
    do {
        try contents.write(to: outdir.appendingPathComponent(name))
    } catch {
        FileHandle.standardError.write(Data("cannot write \(name): \(error)\n".utf8))
        exit(1)
    }
}

func write(_ name: String, _ text: String) {
    write(name, Data(text.utf8))
}

let key = Curve25519.Signing.PrivateKey()
let otherKey = Curve25519.Signing.PrivateKey()

write("public.txt", key.publicKey.rawRepresentation.base64EncodedString())
write("seed.txt", key.rawRepresentation.base64EncodedString())
write("other-public.txt", otherKey.publicKey.rawRepresentation.base64EncodedString())
write("other-seed.txt", otherKey.rawRepresentation.base64EncodedString())

// The DMG fixture and its detached signature.
let payload = Data((0..<2048).map { UInt8($0 % 251) })
var tampered = payload
tampered[0] = tampered[0] &+ 1
write("payload.bin", payload)
write("payload-tampered.bin", tampered)
let signature = try key.signature(for: payload)
write("payload.sig", signature.base64EncodedString())
write("short-signature.txt", Data(repeating: 1, count: 8).base64EncodedString())
write("malformed-signature.txt", "not base64 at all!")

// The feed fixture: the RSS payload followed by Sparkle's trailing comment.
func feed(_ body: String, signedOver signed: Data, signature: Data, length: Int) -> String {
    """
    \(body)<!-- sparkle-signatures:
    edSignature: \(signature.base64EncodedString())
    length: \(length)
    -->

    """
}

let body = """
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Utter</title>
    <item>
      <sparkle:version>0.0.56</sparkle:version>
      <sparkle:shortVersionString>0.0.56</sparkle:shortVersionString>
      <enclosure url="https://example.invalid/Utter-0.0.56.dmg" length="2048" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
"""
let bodyData = Data(body.utf8)
let feedSignature = try key.signature(for: bodyData)

write("feed.xml", feed(body, signedOver: bodyData, signature: feedSignature, length: bodyData.count))
write("feed-unsigned.xml", body)
write("feed-tampered.xml",
      feed(body, signedOver: bodyData, signature: try otherKey.signature(for: bodyData),
           length: bodyData.count))
write("feed-bad-length.xml",
      feed(body, signedOver: bodyData, signature: feedSignature, length: bodyData.count + 1))
write("feed-bad-length-text.xml",
      feed(body, signedOver: bodyData, signature: feedSignature, length: bodyData.count)
      .replacingOccurrences(of: "length: \(bodyData.count)", with: "length: not-a-number"))
