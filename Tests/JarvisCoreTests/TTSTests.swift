import XCTest
@testable import JarvisCore

final class TTSFrontEndTests: XCTestCase {
    func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func makePhonemizer() throws -> KokoroPhonemizer {
        let lex = PronunciationLexicon()
        try lex.load(jsonData: try fixture("gb_mini"))
        let vocab = try KokoroPhonemizer.loadVocab(jsonData: try fixture("kokoro_vocab_index"))
        XCTAssertGreaterThan(vocab.count, 100)
        return KokoroPhonemizer(lexicon: lex, vocab: vocab)
    }

    func testNormalizerBritishNumbers() {
        XCTAssertEqual(EnglishNormalizer.cardinal(123), "one hundred and twenty-three")
        XCTAssertEqual(EnglishNormalizer.cardinal(2_005), "two thousand and five")
        XCTAssertEqual(EnglishNormalizer.ordinal(21), "twenty-first")
        XCTAssertEqual(EnglishNormalizer.normalize("It costs £3.50."), "It costs three pounds fifty.")
        XCTAssertEqual(EnglishNormalizer.normalize("50% done"), "fifty per cent done")
        XCTAssertEqual(EnglishNormalizer.normalize("Meet at 14:30"), "Meet at fourteen thirty")
        XCTAssertEqual(EnglishNormalizer.normalize("5km away"), "five kilometres away")
        XCTAssertEqual(EnglishNormalizer.normalize("the 3D space"), "the three D space")
        XCTAssertEqual(EnglishNormalizer.normalize("Dr. Smith"), "doctor Smith")
    }

    func testWakeResponsePhonemes() throws {
        let p = try makePhonemizer()
        let ph = p.phonemize("Jarvis at your service, sir.")
        XCTAssertEqual(ph, "ʤˈɑːvɪs at jɔː sˈɜːvɪs, sˈɜː.")
        let ids = p.tokenIDs(ph)
        XCTAssertEqual(ids.count, ph.count, "every GB phoneme must exist in the Kokoro vocabulary")
    }

    func testStemmingAndHeteronyms() throws {
        let p = try makePhonemizer()
        XCTAssertEqual(p.phonemes(forWord: "walked"), (p.lexicon.lookup("walk") ?? "") + "t")
        XCTAssertEqual(p.phonemes(forWord: "boxes"), (p.lexicon.lookup("box") ?? "") + "ɪz")
        XCTAssertEqual(p.phonemes(forWord: "cities"), (p.lexicon.lookup("city") ?? "") + "z")
        XCTAssertEqual(p.lexicon.lookup("read"), "ɹˈiːd")
        XCTAssertEqual(p.lexicon.lookup("read", pos: "VBD"), "ɹˈɛd")
    }

    func testOOVFallbacks() throws {
        let p = try makePhonemizer()
        // Rule-based fallback produces vocab-only symbols with stress.
        let rule = p.phonemes(forWord: "zorbulate")
        XCTAssertTrue(rule.contains("ˈ"))
        XCTAssertEqual(p.tokenIDs(rule).count, rule.count)
        // Neural fallback (US phonemes) is converted to the GB inventory.
        p.neuralFallback = { _ in "kˈɑɹtOɾᵻ" }
        XCTAssertEqual(p.phonemes(forWord: "kartoty"), "kˈɑːtQtɪ")
    }

    func testChunkingFitsModelWindow() throws {
        let p = try makePhonemizer()
        let long = Array(repeating: "This should take approximately twenty seconds, sir, and the cube is ready.", count: 4).joined(separator: " ")
        let chunks = p.chunks(for: long)
        XCTAssertGreaterThanOrEqual(chunks.count, 4)
        XCTAssertTrue(chunks.allSatisfy { $0.ids.count <= 126 && !$0.ids.isEmpty })
        XCTAssertEqual(KokoroPhonemizer.sentences("Mr. Smith paid £3.50. Then he left!"), ["Mr. Smith paid £3.50.", "Then he left!"])
    }
}
