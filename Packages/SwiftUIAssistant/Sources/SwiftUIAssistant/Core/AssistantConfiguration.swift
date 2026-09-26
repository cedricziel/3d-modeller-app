import Foundation

/// Configuration options for the Assistant
public struct AssistantConfiguration: Sendable {
    /// The system prompt template
    /// Use {context} as a placeholder for the context description.
    /// It is filled in once per conversation, so it should describe stable context only.
    public var systemPromptTemplate: String

    /// Maximum number of tool execution rounds per message
    public var maxToolExecutionRounds: Int

    /// Whether to include timestamps in messages
    public var includeTimestamps: Bool

    /// Whether each user message carries the context of its turn, for context that changes during a conversation
    public var attachesContextToMessages: Bool

    /// Default configuration
    public static let `default` = AssistantConfiguration()

    public init(
        systemPromptTemplate: String = Self.defaultSystemPrompt,
        maxToolExecutionRounds: Int = 10,
        includeTimestamps: Bool = true,
        attachesContextToMessages: Bool = false
    ) {
        self.systemPromptTemplate = systemPromptTemplate
        self.maxToolExecutionRounds = maxToolExecutionRounds
        self.includeTimestamps = includeTimestamps
        self.attachesContextToMessages = attachesContextToMessages
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
