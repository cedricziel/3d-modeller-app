public enum Pricing {
    /// US dollars per million input and output tokens at Anthropic's first-party rates (June 2026).
    static let perMillionTokens: [String: (input: Double, output: Double)] = [
        "claude-opus-5-5": (4, 20),
        "claude-opus-5": (5, 25),
        "claude-fable-5-1": (10, 50),
        "claude-fable-5": (10, 50),
        "claude-opus-4-8": (5, 25),
        "claude-opus-4-7": (5, 25),
        "claude-opus-4-6": (5, 25),
        "claude-sonnet-5": (2, 10),
        "claude-sonnet-4-6": (3, 15),
        "claude-haiku-4-5": (1, 5),
    ]

    public static func cost(model: String, inputTokens: Int, outputTokens: Int) -> Double? {
        guard let price = perMillionTokens[model] else { return nil }
        return (Double(inputTokens) * price.input + Double(outputTokens) * price.output) / 1_000_000
    }
}
