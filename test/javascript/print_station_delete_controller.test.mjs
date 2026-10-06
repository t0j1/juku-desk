import { describe, it, expect } from "vitest"

// Stimulus コントローラの正規化ロジックをテスト用に抽出
function normalize(str) {
  if (!str) return ""
  return str
    .trim()
    .replace(/[\s\u3000]+/g, " ")
    .normalize("NFKC")
}

describe("printStationDeleteController normalization", () => {
  it("trims leading and trailing whitespace", () => {
    expect(normalize("  A-bizhub551i  ")).toBe("A-bizhub551i")
  })

  it("collapses consecutive half-width spaces", () => {
    expect(normalize("A   bizhub551i")).toBe("A bizhub551i")
  })

  it("collapses consecutive full-width spaces", () => {
    expect(normalize("A\u3000\u3000bizhub551i")).toBe("A bizhub551i")
  })

  it("collapses mixed half-width and full-width spaces", () => {
    expect(normalize("A \u3000 bizhub551i")).toBe("A bizhub551i")
  })

  it("converts full-width alphanumerics to half-width via NFKC", () => {
    expect(normalize("Ａ-bizhub551i")).toBe("A-bizhub551i")
    expect(normalize("ａ-Bizhub551i")).toBe("a-Bizhub551i")
    expect(normalize("１２３")).toBe("123")
  })

  it("preserves Japanese characters (kanji, kana)", () => {
    expect(normalize("教室A")).toBe("教室A")
    expect(normalize("大部屋")).toBe("大部屋")
    expect(normalize("ひらがな")).toBe("ひらがな")
    expect(normalize("カタカナ")).toBe("カタカナ")
  })

  it("preserves case sensitivity", () => {
    expect(normalize("A-bizhub551i")).toBe("A-bizhub551i")
    expect(normalize("a-bizhub551i")).toBe("a-bizhub551i")
  })

  it("returns empty string for empty or whitespace-only input", () => {
    expect(normalize("")).toBe("")
    expect(normalize("   ")).toBe("")
    expect(normalize("\u3000\u3000")).toBe("")
  })

  it("exact match after normalization enables delete button", () => {
    const target = "A-bizhub551i"
    const inputs = [
      "A-bizhub551i",
      "  A-bizhub551i  ",
      "Ａ-bizhub551i",  // full-width alphanumerics converted, hyphen preserved
    ]
    inputs.forEach(input => {
      expect(normalize(input)).toBe(normalize(target))
    })
  })

  it("case difference prevents match", () => {
    const target = "A-bizhub551i"
    expect(normalize("a-bizhub551i")).not.toBe(normalize(target))
  })
})