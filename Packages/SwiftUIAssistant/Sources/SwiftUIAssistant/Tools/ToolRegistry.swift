import Foundation

/// Registry for managing available tools
public final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: any AssistantTool] = [:]
    private let lock = NSLock()

    public init() {}

    /// Initialize with a list of tools
    public init(tools: [any AssistantTool]) {
        for tool in tools {
            self.tools[tool.name] = tool
        }
    }

    // MARK: - Registration

    /// Register a tool
    public func register(_ tool: any AssistantTool) {
        lock.lock()
        defer { lock.unlock() }
        tools[tool.name] = tool
    }

    /// Register multiple tools
    public func register(_ toolList: [any AssistantTool]) {
        lock.lock()
        defer { lock.unlock() }
        for tool in toolList {
            tools[tool.name] = tool
        }
    }

    /// Unregister a tool by name
    public func unregister(named name: String) {
        lock.lock()
        defer { lock.unlock() }
        tools.removeValue(forKey: name)
    }

    // MARK: - Lookup

    /// Get a tool by name
    public func tool(named name: String) -> (any AssistantTool)? {
        lock.lock()
        defer { lock.unlock() }
        return tools[name]
    }

    /// Get all registered tools
    public var allTools: [any AssistantTool] {
        lock.lock()
        defer { lock.unlock() }
        return Array(tools.values)
    }

    /// Check if a tool is registered
    public func contains(named name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tools[name] != nil
    }

    // MARK: - Schema Generation

    /// Generate tool schemas for LLM API calls
    public func toolSchemas() -> [[String: Any]] {
        lock.lock()
        defer { lock.unlock() }

        return tools.values.map { tool in
            var schema: [String: Any] = [
                "name": tool.name,
                "description": tool.description
            ]

            if !tool.parameters.isEmpty {
                var properties: [String: Any] = [:]
                var required: [String] = []

                for param in tool.parameters {
                    properties[param.name] = param.toJSONSchema()
                    if param.required {
                        required.append(param.name)
                    }
                }

                schema["input_schema"] = [
                    "type": "object",
                    "properties": properties,
                    "required": required
                ]
            } else {
                schema["input_schema"] = [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            }

            return schema
        }
    }
}
