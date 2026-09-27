import Foundation
import Testing

@testable import CADModel

@Suite("Appearance")
struct AppearanceTests {
    @Test("Hex colours parse with or without #, in either case, and print as #RRGGBB")
    func hex() throws {
        let green = try #require(HexColor("#2e7d32"))
        #expect(green.hex == "#2E7D32")
        #expect(HexColor("2E7D32") == green)
        #expect(green.red == 0x2E && green.green == 0x7D && green.blue == 0x32)
        #expect(abs(green.rgb.y - 125.0 / 255) < 1e-12)
        for bad in ["", "#", "#12345", "#1234567", "#GG0000", "red", "# 2E7D32"] {
            #expect(HexColor(bad) == nil, "\(bad)")
        }
    }

    @Test("Metallic and roughness must lie in 0…1")
    func ranges() {
        let colour = HexColor(red: 200, green: 40, blue: 40)
        #expect(throws: AppearanceError.self) { try Appearance(color: colour, metallic: 1.5) }
        #expect(throws: AppearanceError.self) { try Appearance(color: colour, roughness: -0.1) }
        #expect(throws: AppearanceError.self) { try Appearance(color: colour, metallic: .nan) }
        #expect((try? Appearance(color: colour, metallic: 1, roughness: 0)) != nil)
    }

    @Test("Parts and instances keep their appearance through a save; earlier documents load without one")
    func roundTrip() throws {
        let part = Part(
            name: "Ornament",
            appearance: try Appearance(color: HexColor(red: 0x2E, green: 0x7D, blue: 0x32), metallic: 0.8))
        let red = Appearance(color: HexColor(red: 0xC6, green: 0x28, blue: 0x28))
        let document = CADDocument(
            parts: [part],
            assembly: Assembly(instances: [
                Instance(name: "Plain", part: part.id), Instance(name: "Red", part: part.id, appearance: red),
            ]))
        let data = try document.jsonData()
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("\"color\" : \"#2E7D32\""))
        #expect(text.contains("\"metallic\" : 0.8"))
        #expect(!text.contains("roughness"))
        let decoded = try CADDocument(json: data)
        #expect(decoded == document)
        #expect(decoded.parts[0].appearance?.metallic == 0.8)
        #expect(decoded.instances[0].appearance == nil)
        #expect(decoded.instances[1].appearance == red)

        let earlier = try CADDocument(json: Data(DocumentCodingTests.handWritten.utf8))
        #expect(earlier.parts[0].appearance == nil)
    }

    @Test("A document with a malformed colour or an out-of-range factor does not load")
    func refusesBadValues() {
        func document(_ appearance: String) -> Data {
            Data(
                """
                {"format": 1, "units": "mm", "parts": [{"name": "P", "appearance": \(appearance)}]}
                """.utf8)
        }
        #expect(throws: DecodingError.self) { try CADDocument(json: document(##"{"color": "#12"}"##)) }
        #expect(throws: DecodingError.self) {
            try CADDocument(json: document(##"{"color": "#123456", "roughness": 2}"##))
        }
        #expect((try? CADDocument(json: document(##"{"color": "#123456", "roughness": 0.5}"##))) != nil)
    }
}
