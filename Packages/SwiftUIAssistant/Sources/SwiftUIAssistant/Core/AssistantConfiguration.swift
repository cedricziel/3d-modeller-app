import Foundation

/// Configuration options for the Assistant
public struct AssistantConfiguration: Sendable {
    /// The system prompt template
    /// Use {context} as a placeholder for the context description
    public var systemPromptTemplate: String

    /// Maximum number of tool execution rounds per message
    public var maxToolExecutionRounds: Int

    /// Whether to include timestamps in messages
    public var includeTimestamps: Bool

    /// Default configuration
    public static let `default` = AssistantConfiguration()

    public init(
        systemPromptTemplate: String = Self.defaultSystemPrompt,
        maxToolExecutionRounds: Int = 10,
        includeTimestamps: Bool = true
    ) {
        self.systemPromptTemplate = systemPromptTemplate
        self.maxToolExecutionRounds = maxToolExecutionRounds
        self.includeTimestamps = includeTimestamps
    }

    /// Default system prompt template
    public static let defaultSystemPrompt = """
        You are a helpful assistant with the ability to execute tools.

        When the user asks you to perform an action, use the available tools to accomplish the task.
        Always confirm what you did after executing tools.

        ## Current Context
        {context}
        """

    /// Build the system prompt with context
    public func buildSystemPrompt(context: any AssistantContext) -> String {
        systemPromptTemplate.replacingOccurrences(
            of: "{context}",
            with: context.contextDescription
        )
    }
}
