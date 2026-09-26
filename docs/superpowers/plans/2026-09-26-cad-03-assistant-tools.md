# CAD 03: Assistant tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the chat assistant read and edit `.cadmodel` documents through typed tools, headlessly: a `CADSession` that owns a document and its rebuild, a compact text listing given to the model every turn, and the tools `get_listing`, `set_parameter`, `add_feature`, `edit_feature`, `delete_feature`, `rename_feature`, `suppress_feature`, wired into the app so every tool call is one named undo step.

**Architecture:** A new package `Packages/CADAssistantTools` depends on `SwiftUIAssistant` (for `AssistantTool`) and `CADModel` (pure; the kernel is injected, so the package never imports OCCT). `CADSession` is a `@MainActor @Observable` class holding the document, a type-erased rebuild engine and the latest `RebuildResult`; tools parse arguments, apply one edit through `CADSession.write`, which validates, repairs body references, refuses new expression failures, commits via `onCommit` and rebuilds, then renders a report. The app keeps `CADModelDocument` as the file/undo source of truth, routes session commits through `CADModelDocument.edit`, and feeds outside changes back with `session.load`. `SwiftUIAssistant` gains per-message context (the system prompt must stay fixed per conversation) and custom JSON Schemas for tool parameters.

**Tech Stack:** Swift 6 (tools 6.1 for the new package), Swift Testing, Observation, Synchronization, SwiftUI, CADModel/CADModelKernel (OCCT through CADKernel) in tests.

**Spec:** `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md` (sections "Agent tools", "Rebuild", PR-stack row 3). Previous layer: `docs/superpowers/plans/2026-09-26-cad-02-document-model.md` (ruling "ordinal body names").

## Global Constraints

- macOS 26, Apple Silicon only (`ARCHS: arm64`), Swift 6 strict concurrency. Use `xcrun swift`, never bare `swift`.
- Only `CADKernel` imports OCCTSwift. `CADAssistantTools` imports `CADModel` and `SwiftUIAssistant` only; tests may add `CADModelKernel`.
- No C++ exception may cross into Swift; kernel failures arrive as `FeatureStatus.failed`.
- The agent-facing surface (document, rebuild, tools) runs without the app or any UI.
- Millimetres in the model and the tools; angles in degrees.
- Every PR in the stack builds, passes its tests and leaves `main` shippable on its own.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). App test module: `@testable import _D_Modeller`.
- Semantic commits, one concern each, no "and" in the subject, no co-author lines. Comments only for a non-obvious why.

## Conventions fixed by this plan

- **Listing** (`DocumentListing.render(document, result:)`): line 1 `parameters: a = 60, r = d / 2 (= 2.75), bad = 1 / 0 (error: division by zero)` or `parameters: none`; then per part `part <name>` and one line per feature, `  <name>  <summary> → <body>  <status>`, or `  (no features)`. Summaries: `box W×D×H`, `cylinder r=R h=H`, `sphere r=R`, `cone r1=B r2=T h=H`, `torus R=M r=m`, then `at origin` / `at (x, y, z)` and optionally ` rotated A° about (ax, ay, az)`, then `, join|cut|intersect BodyN`; booleans `union B1 with B2`, `subtract B2, B3 from B1`, `intersect B1 with B2`; transforms `transform B1 rotated A° about (…), then moved by (…)` / `moved by (…)` / `unchanged`. Compound expressions are parenthesised inside `×` products and `key=value`, not inside tuples. Status is the rebuild's `FeatureStatus.description`, or `not built` (`suppressed` for a suppressed feature) when no rebuild of this exact document exists. No column alignment, so an edit changes only its own lines. Numbers print with at most 3 decimals and never `-0`.
- **Tool arguments**: numbers accept a JSON number or a string (numeric strings become numbers, anything else is an expression). `placement` is `{translation: {x,y,z} | [x,y,z], rotationAxis: {x,y,z}, rotationDegrees}`, any part optional. Solids: `operation` newBody (default) | join | cut | intersect with `body`; boolean: `operation` union | subtract | intersect, `body` = target, `tools` = [bodies]; transform: `body`, `placement`. JSON `null` counts as absent. Unknown argument keys are errors.
- **Write result** (`ToolExecutionResult.message`, the only part the model sees): `<summary>`, `<feature>: <status>`, `Status changes elsewhere:` lines `Name: old → new`, `Body references renumbered:` lines, `Bodies:` lines `Body1 (Part): valid closed solid, volume V mm³, bounds (x, y, z) to (x, y, z)` (or `problems: invalid shape, not closed, N solids`, or `Bodies: none`), `Listing changes:` lines `- old` / `+ new`. A write that changes nothing returns `<summary>. Nothing changed.` and commits nothing.
- **Refusals** return `success: false`, change nothing and commit nothing.
- **Undo action names**: `Add Parameter x`, `Set Parameter x`, `Remove Parameter x`, `Add <name>`, `Edit <name>`, `Delete <name>`, `Rename <old> to <new>`, `Suppress <name>`, `Unsuppress <name>`.
- **Default feature names**: the type capitalised plus the lowest free number in the part (`Box1`, `Boolean1`). Names must match `[A-Za-z_][A-Za-z0-9_]*`, at most 64 characters, unique in the part.

## Rulings

- **Ruling: per-message context, fixed system prompt.** `Assistant` freezes the system prompt per conversation (models that replay thinking reject a changed one), so a listing in `{context}` would go stale after the first write. `AssistantConfiguration.attachesContextToMessages` stores the context on each user `Message.context`; `ClaudeProvider` sends it as a `<context>` text block before the message text; the UI keeps showing only the text. The CAD system prompt has no `{context}` placeholder. Cost if wrong: small; the flag defaults to off, so other hosts are unaffected.
- **Ruling: `ToolParameter.custom(_:description:required:schema:)`.** Numbers must accept numbers or expression strings and placements are nested objects, which the flat `type` field cannot express. Cost if wrong: one extra optional field.
- **Ruling: body references follow their creating feature; refuse when it disappears.** Every write runs `BodyReferenceRepair`: each reference in the edited document is mapped old name → creating feature (old document) → that feature's new name. A reference whose creating feature no longer creates a body (deleted, or turned into join/cut/intersect) refuses the whole edit, naming each user and the creator, and suggests suppressing instead. This covers delete (the PR-2 hazard), insertion before existing body creators and newBody ↔ join edits alike. Cost if wrong: an agent that wanted the renumbering to retarget must now edit the reference explicitly.
- **Ruling: refuse edits that make an expression newly fail.** `ExpressionAudit` evaluates every parameter and every feature scalar before and after; a failure keyed by (parameter | feature id + field, expression text) that did not exist before refuses the edit and lists all of them. Pre-existing failures do not block unrelated edits. Kernel failures (e.g. zero width) are not refused; they are reported as statuses. Cost if wrong: an agent cannot stage a temporarily broken expression; it can set a valid placeholder first.
- **Ruling: the session is `@MainActor`, the context is read through a `Mutex` snapshot.** `Assistant.contextProvider` is a synchronous `@Sendable` closure; `CADSession.assistantContext()` is `nonisolated` and reads the last published listing. Cost if wrong: none observed; `cadbench` runs on the main actor too.
- **Ruling: the app displays `session.result`.** One rebuild pipeline: `.task(id: document.model) { await session.load(document.model) }`; the session drops results of documents it no longer holds. Cost if wrong: a stale frame at most.
- **Ruling: the app stops registering Fetch/Calculator/Time.** Fetch makes network requests on the model's behalf, Calculator duplicates expressions, and Time is irrelevant; the package stays and is still tested in CI. Cost if wrong: re-add one line.
- **Ruling: UI outline Delete does not repair body references yet.** It predates this layer and edits the document directly. Recorded as a follow-up.
- **Ruling: several parts need `part`.** Tools resolve a feature by name across parts; ambiguity or a multi-part document without `part` (for add) is refused with the candidates. Cost if wrong: one more argument for the agent.

## Review Focus

1. Arguments in the wrong shape — numbers as strings, vectors as arrays, `null`, unknown keys, fields that belong to another type — are accepted when unambiguous and otherwise refused with a message naming the key; never silently ignored. Pinned in Task 5 (`defaultsAndArrays`, `refusals`) and Task 5 edit (`refusals` with nulls).
2. Edits that renumber bodies (insert before, delete earlier, newBody ↔ join) keep references on the same creating feature or refuse. Pinned in Task 5 (`insertRenumbers`, `removingUsedBodyRefused`) and Task 6 (`deleteRenumbers`, `deleteUsedBodyRefused`).
3. A newer document arriving while an older rebuild runs (user undo during a tool call): the older result never replaces the newer one. Pinned in Task 3 (`staleResultDropped`) and Task 8 (`toolEditsAreUndoable`).
4. Parameter edits that break other expressions (remove in use, cycles, division by zero) are refused, listing every broken expression. Pinned in Task 4 (`removeInUseRefused`, `badInput`).
5. Several parts, or the same feature name in two parts: the tool asks for `part` instead of guessing. Pinned in Task 5 (`severalParts`) and Task 6 (`deleteRefusals`).

## File Structure

`Packages/SwiftUIAssistant/` (modify): `Tools/ToolParameter.swift` (custom schema), `Conversation/Message.swift` (`context`), `Core/AssistantConfiguration.swift` (`attachesContextToMessages`), `Core/Assistant.swift`, `Providers/ClaudeProvider.swift`; tests `ToolParameterTests.swift` (new), `AssistantTests.swift`, `ClaudeProviderTests.swift`, `Mocks/MockLLMProvider.swift`.

`Packages/CADModel/` (add): `Sources/CADModel/Part+Bodies.swift`, `Tests/CADModelTests/BodyNamingTests.swift`.

`Packages/CADAssistantTools/` (new):

- `Package.swift`
- `Sources/CADAssistantTools/Format.swift` — number, point, vector and operand formatting.
- `DocumentListing.swift` — the listing.
- `CADSession.swift` — session and `ListingContext`.
- `ToolError.swift`, `Arguments.swift` (argument parsing, `Naming`, part/feature lookup), `ExpressionAudit.swift` (+ `scalarFields`), `BodyReferenceRepair.swift`, `WriteReport.swift` (+ `WriteFocus`, `CADSession.write`), `ToolSchemas.swift`.
- `ReadTools.swift` (`GetListingTool`), `SetParameterTool.swift`, `FeatureSpec.swift` (+ `ToolSchemas.kindParameters`), `FeatureEditTools.swift` (add, edit), `FeatureLifecycleTools.swift` (delete, rename, suppress), `CADTools.swift`, `CADAssistantPrompt.swift`.
- Tests: `FakeKernel.swift`, `Fixtures.swift`, `Harness.swift`, `DocumentListingTests.swift`, `CADSessionTests.swift`, `SetParameterToolTests.swift`, `AddFeatureToolTests.swift`, `EditFeatureToolTests.swift`, `FeatureLifecycleToolTests.swift`, `RealKernelTests.swift`, `AssistantLoopTests.swift`.

App: `3DModellerApp/Document/CADModelDocument+Session.swift` (new), `Views/ContentView.swift`, `project.yml`, `Package.swift`, `3DModellerApp.xcodeproj`, `3DModellerAppTests/AssistantEditingTests.swift` (new). Docs: `CLAUDE.md`, `README.md`, `.claude/skills/verify/SKILL.md`, `.github/workflows/ci.yml`.

---
### Task 1: Assistant context per message and custom parameter schemas

**Files:**
- Modify: `Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Tools/ToolParameter.swift`, `Conversation/Message.swift`, `Core/AssistantConfiguration.swift`, `Core/Assistant.swift`, `Providers/ClaudeProvider.swift`
- Test: `Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/ToolParameterTests.swift` (new), `AssistantTests.swift`, `ClaudeProviderTests.swift`, `Mocks/MockLLMProvider.swift`

**Interfaces:**
- Produces: `ToolParameter.schema: [String: JSONValue]?`, `static func custom(_ name: String, description: String, required: Bool = false, schema: [String: JSONValue]) -> ToolParameter` (its `toJSONSchema()` is `schema` plus `description`); `Message.context: String?`, `Message.user(_ content: String, context: String? = nil)`; `AssistantConfiguration(systemPromptTemplate:maxToolExecutionRounds:includeTimestamps:attachesContextToMessages: Bool = false)`; `ClaudeProvider` sends a user message with context as `[{type: text, text: "<context>\n…\n</context>"}, {type: text, text: content}]`.

- [ ] **Step 1: Write the failing tests** — new file:

`Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/ToolParameterTests.swift`:

```swift
import Foundation
import Testing

@testable import SwiftUIAssistant

@Suite("ToolParameter")
struct ToolParameterTests {
    @Test("A custom schema replaces the generated one and keeps the description")
    func customSchema() {
        let parameter = ToolParameter.custom(
            "width",
            description: "Width in mm",
            schema: ["anyOf": [["type": "number"], ["type": "string"]]]
        )

        #expect(parameter.required == false)
        #expect(
            parameter.toJSONSchema() == [
                "anyOf": [["type": "number"], ["type": "string"]],
                "description": "Width in mm",
            ])
    }

    @Test("Parameters without a custom schema keep the generated one")
    func generatedSchema() {
        let parameter = ToolParameter.enumParameter("mode", description: "Mode", values: ["a", "b"])

        #expect(parameter.toJSONSchema() == ["type": "string", "description": "Mode", "enum": ["a", "b"]])
    }
}
```

and these additions to the existing tests and mock:

````diff
diff --git a/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/AssistantTests.swift b/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/AssistantTests.swift
index b0212fe..dc3f390 100644
--- a/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/AssistantTests.swift
+++ b/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/AssistantTests.swift
@@ -250,6 +250,47 @@ struct AssistantTests {
         #expect(Set(prompts).count == 1)
     }
 
+    @Test("Each user message carries the context of its turn when configured")
+    @MainActor
+    func contextAttachedToEachMessage() async throws {
+        let provider = MockLLMProvider()
+        await provider.queueTextResponse("One")
+        await provider.queueTextResponse("Two")
+
+        let counter = ContextCounter()
+        let assistant = Assistant(
+            provider: provider,
+            tools: [],
+            contextProvider: { MockContext(description: "state \(counter.next())") },
+            configuration: AssistantConfiguration(
+                systemPromptTemplate: "Fixed prompt", attachesContextToMessages: true)
+        )
+
+        try await assistant.send("First")
+        try await assistant.send("Second")
+
+        let histories = await provider.receivedHistories
+        let prompts = await provider.receivedMessages.map(\.systemPrompt)
+        #expect(prompts == ["Fixed prompt", "Fixed prompt"])
+        let contexts = histories[1].filter { $0.role == .user }.compactMap(\.context)
+        #expect(contexts.count == 2)
+        #expect(contexts[0] != contexts[1])
+        #expect(contexts.allSatisfy { $0.hasPrefix("state ") })
+        #expect(assistant.messages[0].content == "First")
+    }
+
+    @Test("User messages carry no context by default")
+    @MainActor
+    func noContextByDefault() async throws {
+        let provider = MockLLMProvider()
+        await provider.queueTextResponse("One")
+        let assistant = Assistant(provider: provider, tools: [], contextProvider: { MockContext() })
+
+        try await assistant.send("First")
+
+        #expect(assistant.messages[0].context == nil)
+    }
+
     @Test("Clearing history starts a new system prompt")
     @MainActor
     func clearHistoryRebuildsSystemPrompt() async throws {
diff --git a/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/ClaudeProviderTests.swift b/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/ClaudeProviderTests.swift
index de3aa38..e4aca2b 100644
--- a/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/ClaudeProviderTests.swift
+++ b/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/ClaudeProviderTests.swift
@@ -78,4 +78,37 @@ struct ClaudeProviderTests {
         #expect(content[0]["signature"] as? String == "sig-1")
         #expect(content[1]["type"] as? String == "tool_use")
     }
+
+    @Test("A user message with context sends the context as a text block before the message")
+    func userContextBlock() async throws {
+        let provider = ClaudeProvider(apiKey: "test")
+        let request = try await provider.buildRequest(
+            systemPrompt: "system",
+            messages: [.user("add a hole", context: "part Plate")],
+            tools: []
+        )
+        let messages = try #require(try body(of: request)["messages"] as? [[String: Any]])
+        let content = try #require(messages[0]["content"] as? [[String: Any]])
+
+        #expect(content.count == 2)
+        #expect(content[0]["text"] as? String == "<context>\npart Plate\n</context>")
+        #expect(content[1]["text"] as? String == "add a hole")
+    }
+
+    @Test("Tool parameters with a custom schema are sent unchanged")
+    func customParameterSchema() async throws {
+        let provider = ClaudeProvider(apiKey: "test")
+        let tool = MockTool(
+            id: "t", name: "t", description: "d",
+            parameters: [.custom("width", description: "mm", required: true, schema: ["type": ["number", "string"]])]
+        )
+        let request = try await provider.buildRequest(systemPrompt: "s", messages: [.user("x")], tools: [tool])
+        let tools = try #require(try body(of: request)["tools"] as? [[String: Any]])
+        let schema = try #require(tools[0]["input_schema"] as? [String: Any])
+        let width = try #require((schema["properties"] as? [String: Any])?["width"] as? [String: Any])
+
+        #expect(width["type"] as? [String] == ["number", "string"])
+        #expect(width["description"] as? String == "mm")
+        #expect(schema["required"] as? [String] == ["width"])
+    }
 }
diff --git a/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/Mocks/MockLLMProvider.swift b/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/Mocks/MockLLMProvider.swift
index a9070a9..0c7bf95 100644
--- a/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/Mocks/MockLLMProvider.swift
+++ b/Packages/SwiftUIAssistant/Tests/SwiftUIAssistantTests/Mocks/MockLLMProvider.swift
@@ -9,6 +9,9 @@ actor MockLLMProvider: LLMProvider {
     /// All messages received by this provider
     private(set) var receivedMessages: [(message: String, systemPrompt: String)] = []
 
+    /// The conversation history sent with each request
+    private(set) var receivedHistories: [[Message]] = []
+
     /// Delay before responding (for testing async behavior)
     var responseDelay: UInt64 = 0
 
@@ -47,6 +50,7 @@ actor MockLLMProvider: LLMProvider {
         tools: [any AssistantTool]
     ) async throws -> LLMResponse {
         receivedMessages.append((message: message, systemPrompt: systemPrompt))
+        receivedHistories.append(conversationHistory)
 
         if responseDelay > 0 {
             try await Task.sleep(nanoseconds: responseDelay)
````

- [ ] **Step 2: Run to verify they fail**

Run: `cd Packages/SwiftUIAssistant && xcrun swift test > <scratch>/t.log 2>&1; tail -3 <scratch>/t.log`
Expected: compile errors (`custom`, `context`, `attachesContextToMessages` do not exist).

- [ ] **Step 3: Implement**

````diff
diff --git a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Conversation/Message.swift b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Conversation/Message.swift
index 1c6e07d..1f53531 100644
--- a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Conversation/Message.swift
+++ b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Conversation/Message.swift
@@ -9,6 +9,8 @@ public struct Message: Identifiable, Sendable, Equatable {
     public let toolCallId: String?
     /// Provider-native content blocks, replayed verbatim on the next request
     public let rawContent: [JSONValue]?
+    /// Host state captured when a user message was sent; sent to the model but not shown
+    public let context: String?
     public let timestamp: Date
 
     /// The role of the message sender
@@ -26,6 +28,7 @@ public struct Message: Identifiable, Sendable, Equatable {
         toolCalls: [ToolCall]? = nil,
         toolCallId: String? = nil,
         rawContent: [JSONValue]? = nil,
+        context: String? = nil,
         timestamp: Date = Date()
     ) {
         self.id = id
@@ -34,14 +37,15 @@ public struct Message: Identifiable, Sendable, Equatable {
         self.toolCalls = toolCalls
         self.toolCallId = toolCallId
         self.rawContent = rawContent
+        self.context = context
         self.timestamp = timestamp
     }
 
     // MARK: - Convenience Initializers
 
     /// Create a user message
-    public static func user(_ content: String) -> Message {
-        Message(role: .user, content: content)
+    public static func user(_ content: String, context: String? = nil) -> Message {
+        Message(role: .user, content: content, context: context)
     }
 
     /// Create an assistant message
diff --git a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/Assistant.swift b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/Assistant.swift
index ae7ac18..067ce7d 100644
--- a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/Assistant.swift
+++ b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/Assistant.swift
@@ -59,7 +59,8 @@ public final class Assistant: ObservableObject {
         defer { isProcessing = false }
 
         // Add user message
-        messages.append(Message.user(message))
+        let context = configuration.attachesContextToMessages ? contextProvider().contextDescription : nil
+        messages.append(Message.user(message, context: context))
 
         // Process response (may involve multiple tool execution rounds)
         try await processResponse()
diff --git a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/AssistantConfiguration.swift b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/AssistantConfiguration.swift
index b2ba6d6..aaa9fb3 100644
--- a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/AssistantConfiguration.swift
+++ b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Core/AssistantConfiguration.swift
@@ -13,17 +13,22 @@ public struct AssistantConfiguration: Sendable {
     /// Whether to include timestamps in messages
     public var includeTimestamps: Bool
 
+    /// Whether each user message carries the context of its turn, for context that changes during a conversation
+    public var attachesContextToMessages: Bool
+
     /// Default configuration
     public static let `default` = AssistantConfiguration()
 
     public init(
         systemPromptTemplate: String = Self.defaultSystemPrompt,
         maxToolExecutionRounds: Int = 10,
-        includeTimestamps: Bool = true
+        includeTimestamps: Bool = true,
+        attachesContextToMessages: Bool = false
     ) {
         self.systemPromptTemplate = systemPromptTemplate
         self.maxToolExecutionRounds = maxToolExecutionRounds
         self.includeTimestamps = includeTimestamps
+        self.attachesContextToMessages = attachesContextToMessages
     }
 
     /// Default system prompt template
diff --git a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Providers/ClaudeProvider.swift b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Providers/ClaudeProvider.swift
index 6f42849..568e447 100644
--- a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Providers/ClaudeProvider.swift
+++ b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Providers/ClaudeProvider.swift
@@ -101,9 +101,15 @@ public actor ClaudeProvider: LLMProvider {
             return nil
 
         case .user:
+            guard let context = message.context else {
+                return ["role": "user", "content": message.content]
+            }
             return [
                 "role": "user",
-                "content": message.content,
+                "content": [
+                    ["type": "text", "text": "<context>\n\(context)\n</context>"],
+                    ["type": "text", "text": message.content],
+                ],
             ]
 
         case .assistant:
diff --git a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Tools/ToolParameter.swift b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Tools/ToolParameter.swift
index 5609167..cd41ca7 100644
--- a/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Tools/ToolParameter.swift
+++ b/Packages/SwiftUIAssistant/Sources/SwiftUIAssistant/Tools/ToolParameter.swift
@@ -20,6 +20,9 @@ public struct ToolParameter: Sendable, Equatable {
     /// Default value if not provided
     public let defaultValue: JSONValue?
 
+    /// A JSON Schema that replaces the one generated from `type` and `enumValues`
+    public let schema: [String: JSONValue]?
+
     /// The data type of the parameter
     public enum ParameterType: String, Sendable, Equatable {
         case string
@@ -36,7 +39,8 @@ public struct ToolParameter: Sendable, Equatable {
         description: String,
         required: Bool = false,
         enumValues: [String]? = nil,
-        defaultValue: JSONValue? = nil
+        defaultValue: JSONValue? = nil,
+        schema: [String: JSONValue]? = nil
     ) {
         self.name = name
         self.type = type
@@ -44,12 +48,18 @@ public struct ToolParameter: Sendable, Equatable {
         self.required = required
         self.enumValues = enumValues
         self.defaultValue = defaultValue
+        self.schema = schema
     }
 
     // MARK: - Schema Generation
 
     /// Generate a JSON Schema representation for this parameter
     public func toJSONSchema() -> [String: JSONValue] {
+        if var schema {
+            schema["description"] = .string(description)
+            return schema
+        }
+
         var schema: [String: JSONValue] = [
             "type": .string(type.rawValue),
             "description": .string(description)
@@ -91,6 +101,13 @@ public extension ToolParameter {
         ToolParameter(name: name, type: .boolean, description: description, required: true)
     }
 
+    /// Create a parameter described by its own JSON Schema, for unions, nested objects and arrays
+    static func custom(
+        _ name: String, description: String, required: Bool = false, schema: [String: JSONValue]
+    ) -> ToolParameter {
+        ToolParameter(name: name, type: .object, description: description, required: required, schema: schema)
+    }
+
     /// Create an enum parameter with allowed values
     static func enumParameter(_ name: String, description: String, values: [String], required: Bool = true) -> ToolParameter {
         ToolParameter(name: name, type: .string, description: description, required: required, enumValues: values)
````

- [ ] **Step 4: Run to verify they pass** — same command. Expected: all tests pass. Note the system prompt build also calls the context provider, so the per-message test compares contexts for being distinct rather than for exact counter values.

- [ ] **Step 5: Commits**
  1. `feat(assistant): describe tool parameters with a custom schema` — ToolParameter, `ToolParameterTests`, the ClaudeProvider schema test.
  2. `feat(assistant): attach the current context to each user message` — Message, configuration, Assistant, ClaudeProvider, the remaining tests and the mock.

### Task 2: Body naming helpers in CADModel

**Files:**
- Create: `Packages/CADModel/Sources/CADModel/Part+Bodies.swift`
- Test: `Packages/CADModel/Tests/CADModelTests/BodyNamingTests.swift`

**Interfaces:**
- Produces: `Part.createdBodies() -> [String: UUID]` (body name → creating feature id), `Part.affectedBodies() -> [UUID: String]` (feature id → body it creates or changes; matches `FeatureResult.body`), `FeatureKind.bodyReferences: [String]`, `FeatureKind.renameBodyReferences(_ rename: (String) -> String)`.

- [ ] **Step 1: Write the failing test**

`Packages/CADModel/Tests/CADModelTests/BodyNamingTests.swift`:

```swift
import Foundation
import Testing

@testable import CADModel

@Suite("Body naming")
struct BodyNamingTests {
    private func box(_ name: String, _ operation: SolidOperation = .newBody, suppressed: Bool = false) -> Feature {
        Feature(
            name: name, suppressed: suppressed,
            kind: .primitive(PrimitiveFeature(.box(width: 1, depth: 1, height: 1), operation: operation)))
    }

    @Test("Bodies are named by the ordinal of their creating feature, counting suppressed ones")
    func createdBodies() {
        let a = box("A")
        let b = box("B", suppressed: true)
        let c = box("C", .cut("Body1"))
        let d = box("D")
        let part = Part(name: "P", features: [a, b, c, d])

        #expect(part.createdBodies() == ["Body1": a.id, "Body2": b.id, "Body3": d.id])
    }

    @Test("Each feature names the body it creates or changes, matching the rebuild")
    func affectedBodies() async throws {
        let a = box("A")
        let b = box("B", .join("Body1"))
        let c = Feature(name: "C", kind: .transform(TransformFeature(body: "Body1", placement: .identity)))
        let d = box("D")
        let e = Feature(name: "E", kind: .boolean(BooleanFeature(operation: .union, target: "Body2", tools: ["Body1"])))
        let part = Part(name: "P", features: [a, b, c, d, e])
        let rebuilt = try await RebuildEngine(kernel: FakeKernel()).rebuild(CADDocument(parts: [part]))

        let expected: [UUID: String] = [
            a.id: "Body1", b.id: "Body1", c.id: "Body1", d.id: "Body2", e.id: "Body2",
        ]
        #expect(part.affectedBodies() == expected)
        #expect(Dictionary(uniqueKeysWithValues: rebuilt.parts[0].features.map { ($0.id, $0.body) }) == expected)
    }

    @Test("Body references are listed and renamed for every feature kind")
    func references() {
        var cut = FeatureKind.primitive(PrimitiveFeature(.sphere(radius: 1), operation: .cut("Body1")))
        var boolean = FeatureKind.boolean(
            BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"]))
        var transform = FeatureKind.transform(TransformFeature(body: "Body2", placement: .identity))
        var fresh = FeatureKind.primitive(PrimitiveFeature(.sphere(radius: 1)))

        #expect(cut.bodyReferences == ["Body1"])
        #expect(boolean.bodyReferences == ["Body1", "Body2", "Body3"])
        #expect(transform.bodyReferences == ["Body2"])
        #expect(fresh.bodyReferences.isEmpty)

        let rename: (String) -> String = { $0 == "Body1" ? "BodyA" : $0 + "x" }
        cut.renameBodyReferences(rename)
        boolean.renameBodyReferences(rename)
        transform.renameBodyReferences(rename)
        fresh.renameBodyReferences(rename)

        #expect(cut.bodyReferences == ["BodyA"])
        #expect(boolean.bodyReferences == ["BodyA", "Body2x", "Body3x"])
        #expect(transform.bodyReferences == ["Body2x"])
        #expect(fresh == .primitive(PrimitiveFeature(.sphere(radius: 1))))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/CADModel && xcrun swift test --filter BodyNamingTests > <scratch>/t.log 2>&1; tail -3 <scratch>/t.log`
Expected: compile errors.

- [ ] **Step 3: Implement**

`Packages/CADModel/Sources/CADModel/Part+Bodies.swift`:

```swift
import Foundation

extension Part {
    /// The body each `newBody` feature creates, by name: the n-th such feature owns `Body<n>`.
    public func createdBodies() -> [String: UUID] {
        var bodies: [String: UUID] = [:]
        for feature in features where feature.kind.createsNewBody {
            bodies["Body\(bodies.count + 1)"] = feature.id
        }
        return bodies
    }

    /// The body each feature creates or changes, by feature id.
    public func affectedBodies() -> [UUID: String] {
        var bodies: [UUID: String] = [:]
        var created = 0
        for feature in features {
            var newBody: String?
            if feature.kind.createsNewBody {
                created += 1
                newBody = "Body\(created)"
            }
            bodies[feature.id] = feature.kind.affectedBody(newBody: newBody)
        }
        return bodies
    }
}

extension FeatureKind {
    /// Names of the existing bodies this feature reads or changes.
    public var bodyReferences: [String] {
        switch self {
        case .primitive(let primitive): primitive.operation.targetBody.map { [$0] } ?? []
        case .boolean(let boolean): [boolean.target] + boolean.tools
        case .transform(let transform): [transform.body]
        }
    }

    public mutating func renameBodyReferences(_ rename: (String) -> String) {
        switch self {
        case .primitive(var primitive):
            switch primitive.operation {
            case .newBody: return
            case .join(let body): primitive.operation = .join(rename(body))
            case .cut(let body): primitive.operation = .cut(rename(body))
            case .intersect(let body): primitive.operation = .intersect(rename(body))
            }
            self = .primitive(primitive)
        case .boolean(var boolean):
            boolean.target = rename(boolean.target)
            boolean.tools = boolean.tools.map(rename)
            self = .boolean(boolean)
        case .transform(var transform):
            transform.body = rename(transform.body)
            self = .transform(transform)
        }
    }
}
```

- [ ] **Step 4: Run to verify it passes** — `cd Packages/CADModel && xcrun swift test --filter CADModelTests`.

- [ ] **Step 5: Commit** — `feat(model): expose body names and body references`

### Task 3: CADAssistantTools package, listing and session

**Files:**
- Create: `Packages/CADAssistantTools/Package.swift`, `Sources/CADAssistantTools/{Format,DocumentListing,CADSession}.swift`
- Test: `Tests/CADAssistantToolsTests/{FakeKernel,Fixtures,DocumentListingTests,CADSessionTests}.swift`
- Modify: `.github/workflows/ci.yml` (add `Test CADAssistantTools` before `Test app`)

**Interfaces:**
- Consumes: `Part.affectedBodies()` (Task 2), `RebuildEngine`, `ParameterTable`.
- Produces: `public enum DocumentListing { static func render(_: CADDocument, result: RebuildResult?) -> String }` and internal `lines(_:result:) -> [String]`; `enum Format { number(_:), point(_:), operand(_:), vector(_:) }`; `@MainActor @Observable public final class CADSession` with `init<Kernel: GeometryKernel>(document: CADDocument = CADDocument(), kernel: Kernel)`, `document`, `result`, `onCommit: (@MainActor (CADDocument, String) -> Void)?`, `listing: String`, `nonisolated currentListing() -> String`, `nonisolated assistantContext() -> ListingContext`, `rebuild() async throws -> RebuildResult`, `load(_:) async`, `apply(_:actionName:) async -> RebuildResult?`, `currentResult() async -> RebuildResult?`; `public struct ListingContext: AssistantContext`.

- [ ] **Step 1: Package manifest**

`Packages/CADAssistantTools/Package.swift`:

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "CADAssistantTools",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(name: "CADAssistantTools", targets: ["CADAssistantTools"])
    ],
    dependencies: [
        .package(path: "../SwiftUIAssistant"),
        .package(path: "../CADModel"),
    ],
    targets: [
        .target(
            name: "CADAssistantTools",
            dependencies: [
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
            ]
        ),
        .testTarget(
            name: "CADAssistantToolsTests",
            dependencies: [
                "CADAssistantTools",
                .product(name: "SwiftUIAssistant", package: "SwiftUIAssistant"),
                .product(name: "CADModel", package: "CADModel"),
                .product(name: "CADModelKernel", package: "CADModel"),
            ]
        ),
    ]
)
```

- [ ] **Step 2: Write the failing tests** (fake kernel with a box hook for gating, fixtures, listing snapshots, session behaviour)

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/FakeKernel.swift`:

```swift
import CADModel
import Foundation

struct FakeBody: Sendable {
    var volume: Double
    var boundsMin: SIMD3<Double>
    var boundsMax: SIMD3<Double>
}

struct FakeKernelError: Error, CustomStringConvertible {
    let description: String
}

/// Boxes have exact volumes and bounds; everything else is approximate but deterministic.
struct FakeKernel: GeometryKernel {
    var onBox: @Sendable () -> Void = {}

    private func positive(_ values: Double...) throws {
        guard values.allSatisfy({ $0 > 0 }) else { throw FakeKernelError(description: "dimensions must be positive") }
    }

    private func body(volume: Double, size: SIMD3<Double>, at placement: ResolvedPlacement) -> FakeBody {
        FakeBody(volume: volume, boundsMin: placement.translation, boundsMax: placement.translation + size)
    }

    func box(width: Double, depth: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        onBox()
        try positive(width, depth, height)
        return body(volume: width * depth * height, size: SIMD3(width, depth, height), at: placement)
    }

    func cylinder(radius: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody {
        try positive(radius, height)
        return body(volume: 3 * radius * radius * height, size: SIMD3(2 * radius, 2 * radius, height), at: placement)
    }

    func sphere(radius: Double, placement: ResolvedPlacement) throws -> FakeBody {
        try positive(radius)
        return body(volume: 4 * radius * radius * radius, size: SIMD3(repeating: 2 * radius), at: placement)
    }

    func cone(bottomRadius: Double, topRadius: Double, height: Double, placement: ResolvedPlacement) throws -> FakeBody
    {
        guard bottomRadius != topRadius else { throw FakeKernelError(description: "cone radii must differ") }
        return body(volume: height, size: SIMD3(1, 1, height), at: placement)
    }

    func torus(majorRadius: Double, minorRadius: Double, placement: ResolvedPlacement) throws -> FakeBody {
        try positive(majorRadius, minorRadius)
        return body(volume: majorRadius * minorRadius, size: SIMD3(1, 1, 1), at: placement)
    }

    func boolean(_ operation: BooleanOperation, _ target: FakeBody, _ tool: FakeBody) throws -> FakeBody {
        var result = target
        switch operation {
        case .union:
            result.volume += tool.volume
            result.boundsMin = pointwiseMin(target.boundsMin, tool.boundsMin)
            result.boundsMax = pointwiseMax(target.boundsMax, tool.boundsMax)
        case .subtract: result.volume -= tool.volume
        case .intersect: result.volume = min(target.volume, tool.volume)
        }
        guard result.volume > 0 else { throw FakeKernelError(description: "the operation left no solid") }
        return result
    }

    func transform(_ body: FakeBody, by placement: ResolvedPlacement) throws -> FakeBody {
        FakeBody(
            volume: body.volume, boundsMin: body.boundsMin + placement.translation,
            boundsMax: body.boundsMax + placement.translation)
    }

    func metrics(of body: FakeBody) throws -> BodyMetrics {
        BodyMetrics(
            volume: body.volume, boundsMin: body.boundsMin, boundsMax: body.boundsMax, faceCount: 6, solidCount: 1,
            isValid: true, isClosed: true)
    }

    func mesh(of _: FakeBody) throws -> BodyMesh {
        BodyMesh(positions: [.zero, SIMD3(1, 0, 0), SIMD3(0, 1, 0)], normals: [], indices: [0, 1, 2])
    }
}
```

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/Fixtures.swift`:

```swift
import CADModel
import Foundation

enum Fixtures {
    static let plateParameters = [
        Parameter(name: "width", expression: 60),
        Parameter(name: "depth", expression: 40),
        Parameter(name: "t", expression: 10),
        Parameter(name: "hole_d", expression: 5.5),
        Parameter(name: "hole_r", expression: "hole_d / 2"),
    ]

    static func box(_ name: String, _ w: Scalar, _ d: Scalar, _ h: Scalar, _ operation: SolidOperation = .newBody)
        -> Feature
    {
        Feature(
            name: name, kind: .primitive(PrimitiveFeature(.box(width: w, depth: d, height: h), operation: operation)))
    }

    /// A plate with a hole, a suppressed pin, a failing cone, a boolean that depends on it and a move.
    static func plate() -> CADDocument {
        CADDocument(
            parameters: plateParameters,
            parts: [
                Part(
                    name: "Plate",
                    features: [
                        box("Base", "width", "depth", "t"),
                        Feature(
                            name: "Hole",
                            kind: .primitive(
                                PrimitiveFeature(
                                    .cylinder(radius: "hole_r", height: "t"),
                                    placement: Placement(translation: Vector3("width / 2", "depth / 2", 0)),
                                    operation: .cut("Body1")))),
                        Feature(
                            name: "Pin", suppressed: true,
                            kind: .primitive(
                                PrimitiveFeature(
                                    .cylinder(radius: 2, height: 5),
                                    placement: Placement(
                                        translation: Vector3(0, 0, 10), rotationAxis: Vector3(1, 0, 0),
                                        rotationDegrees: 90)))),
                        Feature(
                            name: "BadCone",
                            kind: .primitive(PrimitiveFeature(.cone(bottomRadius: 3, topRadius: 3, height: 5)))),
                        Feature(
                            name: "Merge",
                            kind: .boolean(BooleanFeature(operation: .union, target: "Body1", tools: ["Body3"]))),
                        Feature(
                            name: "Move",
                            kind: .transform(
                                TransformFeature(body: "Body1", placement: Placement(translation: Vector3(10, 0, 0))))),
                    ])
            ])
    }
}
```

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/DocumentListingTests.swift`:

```swift
import CADModel
import Foundation
import Testing

@testable import CADAssistantTools

@Suite("Document listing")
struct DocumentListingTests {
    @Test("A rebuilt document lists parameters with values and every feature with its body and status")
    func plate() async throws {
        let document = Fixtures.plate()
        let result = try await RebuildEngine(kernel: FakeKernel()).rebuild(document)

        #expect(
            DocumentListing.render(document, result: result) == """
                parameters: width = 60, depth = 40, t = 10, hole_d = 5.5, hole_r = hole_d / 2 (= 2.75)
                part Plate
                  Base  box width×depth×t at origin → Body1  ok
                  Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok
                  Pin  cylinder r=2 h=5 at (0, 0, 10) rotated 90° about (1, 0, 0) → Body2  suppressed
                  BadCone  cone r1=3 r2=3 h=5 at origin → Body3  failed: cone radii must differ
                  Merge  union Body1 with Body3 → Body1  skipped: depends on BadCone
                  Move  transform Body1 moved by (10, 0, 0) → Body1  ok
                """)
    }

    @Test("Without a rebuild result features read as not built, suppressed ones as suppressed")
    func notBuilt() {
        #expect(
            DocumentListing.render(Fixtures.plate(), result: nil).split(separator: "\n").map(String.init)[2...4] == [
                "  Base  box width×depth×t at origin → Body1  not built",
                "  Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  not built",
                "  Pin  cylinder r=2 h=5 at (0, 0, 10) rotated 90° about (1, 0, 0) → Body2  suppressed",
            ])
    }

    @Test("Empty documents, empty parts and failing parameters are listed plainly")
    func emptyAndFailing() {
        let document = CADDocument(
            parameters: [Parameter(name: "a", expression: "1 / 0"), Parameter(name: "b", expression: "a + 1")],
            parts: [Part(name: "Empty")])

        #expect(
            DocumentListing.render(document, result: nil) == """
                parameters: a = 1 / 0 (error: division by zero), b = a + 1 (error: parameter 'a' has an error)
                part Empty
                  (no features)
                """)
        #expect(DocumentListing.render(CADDocument(parts: []), result: nil) == "parameters: none")
    }

    @Test("Compound expressions are parenthesised where they would read ambiguously")
    func compoundExpressions() {
        let document = CADDocument(
            parts: [
                Part(
                    name: "P",
                    features: [
                        Fixtures.box("B", "w + 1", 2, "h * 2"),
                        Feature(
                            name: "C",
                            kind: .primitive(
                                PrimitiveFeature(
                                    .cone(bottomRadius: "r - 1", topRadius: 0, height: 3),
                                    placement: Placement(rotationDegrees: "a / 2"), operation: .join("Body1")))),
                        Feature(
                            name: "T",
                            kind: .transform(
                                TransformFeature(
                                    body: "Body1",
                                    placement: Placement(
                                        translation: Vector3(1, 2, 3), rotationAxis: Vector3(0, 0, 1),
                                        rotationDegrees: 45)))),
                        Feature(name: "U", kind: .transform(TransformFeature(body: "Body1", placement: .identity))),
                        Feature(
                            name: "S",
                            kind: .boolean(
                                BooleanFeature(operation: .subtract, target: "Body1", tools: ["Body2", "Body3"]))),
                        Feature(
                            name: "I",
                            kind: .boolean(BooleanFeature(operation: .intersect, target: "Body1", tools: ["Body2"]))),
                        Feature(
                            name: "Tor", kind: .primitive(PrimitiveFeature(.torus(majorRadius: 5, minorRadius: 1)))),
                        Feature(name: "Sph", kind: .primitive(PrimitiveFeature(.sphere(radius: 1.25)))),
                    ])
            ])

        #expect(
            DocumentListing.render(document, result: nil) == """
                parameters: none
                part P
                  B  box (w + 1)×2×(h * 2) at origin → Body1  not built
                  C  cone r1=(r - 1) r2=0 h=3 at origin rotated (a / 2)° about (0, 0, 1), join Body1 → Body1  not built
                  T  transform Body1 rotated 45° about (0, 0, 1), then moved by (1, 2, 3) → Body1  not built
                  U  transform Body1 unchanged → Body1  not built
                  S  subtract Body2, Body3 from Body1 → Body1  not built
                  I  intersect Body1 with Body2 → Body1  not built
                  Tor  torus R=5 r=1 at origin → Body2  not built
                  Sph  sphere r=1.25 at origin → Body3  not built
                """)
    }

    @Test("Numbers are shown with at most three decimals and no negative zero")
    func numbers() {
        #expect(Format.number(2.75) == "2.75")
        #expect(Format.number(1.0 / 3.0) == "0.333")
        #expect(Format.number(-0.0001) == "0")
        #expect(Format.number(24000) == "24000")
        #expect(Format.number(-12.5) == "-12.5")
    }
}
```

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/CADSessionTests.swift`:

```swift
import CADModel
import Foundation
import Synchronization
import Testing

@testable import CADAssistantTools

/// Holds every box build until released, so a test can overlap two rebuilds.
final class Gate: Sendable {
    private let state = Mutex((entered: 0, open: false))

    var entered: Int { state.withLock { $0.entered } }

    func pass() {
        state.withLock { $0.entered += 1 }
        while !state.withLock({ $0.open }) { Thread.sleep(forTimeInterval: 0.001) }
    }

    func open() { state.withLock { $0.open = true } }
}

final class Counter: Sendable {
    private let value = Mutex(0)
    var count: Int { value.withLock { $0 } }
    func increment() { value.withLock { $0 += 1 } }
}

@MainActor
@Suite("CAD session")
struct CADSessionTests {
    private func sphereDocument(_ name: String) -> CADDocument {
        CADDocument(parts: [
            Part(name: "P", features: [Feature(name: name, kind: .primitive(PrimitiveFeature(.sphere(radius: 1))))])
        ])
    }

    @Test("A new session lists its document as not built until it rebuilds")
    func listingFollowsRebuild() async throws {
        let plate = Fixtures.plate()
        let session = CADSession(document: plate, kernel: FakeKernel())

        #expect(session.result == nil)
        #expect(session.currentListing().contains("Base  box width×depth×t at origin → Body1  not built"))

        let result = try await session.rebuild()

        #expect(session.result == result)
        #expect(session.listing == DocumentListing.render(plate, result: result))
        #expect(session.currentListing() == session.listing)
        #expect(session.assistantContext().contextDescription.hasSuffix(session.listing))
    }

    @Test("Applying an edit hands it to the commit hook with its action name, then rebuilds")
    func applyCommits() async throws {
        let session = CADSession(document: CADDocument(), kernel: FakeKernel())
        var commits: [(CADDocument, String)] = []
        session.onCommit = { commits.append(($0, $1)) }
        let edited = Fixtures.plate()

        let result = await session.apply(edited, actionName: "Add Base")

        #expect(commits.count == 1)
        #expect(commits.first?.0 == edited)
        #expect(commits.first?.1 == "Add Base")
        #expect(session.document == edited)
        #expect(result?.parts.first?.features.count == 6)
        #expect(session.result == result)
    }

    @Test("Loading the document the session already built does not rebuild it again")
    func loadSkipsCurrentDocument() async throws {
        let boxes = Counter()
        let plate = Fixtures.plate()
        let session = CADSession(document: plate, kernel: FakeKernel(onBox: { boxes.increment() }))

        await session.load(plate)
        let afterFirst = boxes.count
        await session.load(session.document)

        #expect(afterFirst == 1)
        #expect(boxes.count == 1)
        #expect(session.result != nil)
    }

    @Test("A slow rebuild of an older document never replaces the result of a newer one")
    func staleResultDropped() async throws {
        let gate = Gate()
        let session = CADSession(document: CADDocument(), kernel: FakeKernel(onBox: { gate.pass() }))
        let slow = Task { await session.load(Fixtures.plate()) }
        while gate.entered == 0 { try await Task.sleep(for: .milliseconds(1)) }

        let newer = sphereDocument("Ball")
        await session.load(newer)
        gate.open()
        await slow.value

        #expect(session.document == newer)
        #expect(session.result?.parts.first?.features.map(\.name) == ["Ball"])
        #expect(session.listing.contains("Ball  sphere r=1 at origin → Body1  ok"))
    }

    @Test("The current result is rebuilt on demand when the document changed since the last rebuild")
    func currentResultOnDemand() async throws {
        let session = CADSession(document: sphereDocument("Ball"), kernel: FakeKernel())

        let result = await session.currentResult()

        #expect(result?.parts.first?.features.first?.status == .ok)
        #expect(await session.currentResult() == result)
    }
}
```

- [ ] **Step 3: Run to verify they fail**

Run: `cd Packages/CADAssistantTools && xcrun swift test > <scratch>/t.log 2>&1; tail -3 <scratch>/t.log`
Expected: compile errors (`DocumentListing`, `CADSession` missing).

- [ ] **Step 4: Implement**

`Packages/CADAssistantTools/Sources/CADAssistantTools/Format.swift`:

```swift
import CADModel

enum Format {
    static func number(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == 0 { return "0" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    static func point(_ point: SIMD3<Double>) -> String {
        "(\(number(point.x)), \(number(point.y)), \(number(point.z)))"
    }

    /// The scalar as written; compound expressions get parentheses so they read unambiguously next to other text.
    static func operand(_ scalar: Scalar) -> String {
        guard case .expression(let text) = scalar else { return scalar.description }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let isAtom = trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        return isAtom ? trimmed : "(\(trimmed))"
    }

    static func vector(_ vector: Vector3) -> String {
        "(\(vector.x), \(vector.y), \(vector.z))"
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/DocumentListing.swift`:

```swift
import CADModel
import Foundation

/// A compact, deterministic text rendering of a document for the assistant. Each feature is one line so a change
/// shows up as a change to its own lines only.
public enum DocumentListing {
    public static func render(_ document: CADDocument, result: RebuildResult?) -> String {
        lines(document, result: result).joined(separator: "\n")
    }

    static func lines(_ document: CADDocument, result: RebuildResult?) -> [String] {
        var lines = [parametersLine(document.parameters)]
        for part in document.parts {
            lines.append("part \(part.name)")
            if part.features.isEmpty { lines.append("  (no features)") }
            let bodies = part.affectedBodies()
            for feature in part.features {
                let status =
                    result?.feature(id: feature.id)?.status.description
                    ?? (feature.suppressed ? FeatureStatus.suppressed.description : "not built")
                lines.append("  \(feature.name)  \(summary(feature.kind, body: bodies[feature.id]))  \(status)")
            }
        }
        return lines
    }

    static func parametersLine(_ parameters: [Parameter]) -> String {
        guard !parameters.isEmpty else { return "parameters: none" }
        let table = ParameterTable(parameters)
        let entries = table.parameters.map { parameter in
            var entry = "\(parameter.name) = \(parameter.expression)"
            switch parameter.value {
            case .failure(let error): entry += " (error: \(error))"
            case .success(let value):
                if case .expression = parameter.expression { entry += " (= \(Format.number(value)))" }
            }
            return entry
        }
        return "parameters: " + entries.joined(separator: ", ")
    }

    static func summary(_ kind: FeatureKind, body: String?) -> String {
        let arrow = body.map { " → \($0)" } ?? ""
        switch kind {
        case .primitive(let primitive):
            var text = "\(shape(primitive.shape)) \(location(primitive.placement))"
            switch primitive.operation {
            case .newBody: break
            case .join(let target): text += ", join \(target)"
            case .cut(let target): text += ", cut \(target)"
            case .intersect(let target): text += ", intersect \(target)"
            }
            return text + arrow
        case .boolean(let boolean):
            let tools = boolean.tools.joined(separator: ", ")
            let text =
                switch boolean.operation {
                case .union: "union \(boolean.target) with \(tools)"
                case .subtract: "subtract \(tools) from \(boolean.target)"
                case .intersect: "intersect \(boolean.target) with \(tools)"
                }
            return text + arrow
        case .transform(let transform):
            return "transform \(transform.body) \(motion(transform.placement))" + arrow
        }
    }

    private static func shape(_ shape: PrimitiveShape) -> String {
        let o = Format.operand
        return switch shape {
        case .box(let width, let depth, let height): "box \(o(width))×\(o(depth))×\(o(height))"
        case .cylinder(let radius, let height): "cylinder r=\(o(radius)) h=\(o(height))"
        case .sphere(let radius): "sphere r=\(o(radius))"
        case .cone(let bottom, let top, let height): "cone r1=\(o(bottom)) r2=\(o(top)) h=\(o(height))"
        case .torus(let major, let minor): "torus R=\(o(major)) r=\(o(minor))"
        }
    }

    private static func isZero(_ scalar: Scalar) -> Bool { scalar == .number(0) }

    private static func isOrigin(_ vector: Vector3) -> Bool { isZero(vector.x) && isZero(vector.y) && isZero(vector.z) }

    private static func rotation(_ placement: Placement) -> String? {
        guard !isZero(placement.rotationDegrees) else { return nil }
        return "rotated \(Format.operand(placement.rotationDegrees))° about \(Format.vector(placement.rotationAxis))"
    }

    private static func location(_ placement: Placement) -> String {
        let position = isOrigin(placement.translation) ? "at origin" : "at \(Format.vector(placement.translation))"
        return [position, rotation(placement)].compactMap(\.self).joined(separator: " ")
    }

    private static func motion(_ placement: Placement) -> String {
        let move = isOrigin(placement.translation) ? nil : "moved by \(Format.vector(placement.translation))"
        switch (rotation(placement), move) {
        case (nil, nil): return "unchanged"
        case (let rotation?, nil): return rotation
        case (nil, let move?): return move
        case (let rotation?, let move?): return "\(rotation), then \(move)"
        }
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/CADSession.swift`:

```swift
import CADModel
import Foundation
import Observation
import SwiftUIAssistant
import Synchronization

/// Owns a document and its latest rebuild so the assistant tools can edit and inspect it without any UI.
/// A host that keeps its own copy of the document (for files and undo) sets `onCommit` and calls `load` when its
/// copy changes for other reasons.
@MainActor
@Observable
public final class CADSession {
    public private(set) var document: CADDocument
    /// The latest rebuild; it may lag behind `document` while a rebuild runs.
    public private(set) var result: RebuildResult?

    /// Called with every document an edit produces and the edit's action name, before the rebuild.
    @ObservationIgnored public var onCommit: (@MainActor (CADDocument, String) -> Void)?

    @ObservationIgnored private let build: @Sendable (CADDocument) async throws -> RebuildResult
    @ObservationIgnored private var builtDocument: CADDocument?
    @ObservationIgnored private var buildingDocument: CADDocument?
    private nonisolated let snapshot: Mutex<String>

    public init<Kernel: GeometryKernel>(document: CADDocument = CADDocument(), kernel: Kernel) {
        let engine = RebuildEngine(kernel: kernel)
        build = { try await engine.rebuild($0) }
        self.document = document
        snapshot = Mutex(DocumentListing.render(document, result: nil))
    }

    /// The listing of the document, with statuses only from a rebuild of this exact document.
    public var listing: String {
        DocumentListing.render(document, result: builtDocument == document ? result : nil)
    }

    /// The latest listing, readable from any isolation, for the assistant's context provider.
    public nonisolated func currentListing() -> String {
        snapshot.withLock { $0 }
    }

    public nonisolated func assistantContext() -> ListingContext {
        ListingContext(listing: currentListing())
    }

    @discardableResult
    public func rebuild() async throws -> RebuildResult {
        let target = document
        buildingDocument = target
        defer { if buildingDocument == target { buildingDocument = nil } }
        let rebuilt = try await build(target)
        if document == target {
            result = rebuilt
            builtDocument = target
            publishListing()
        }
        return rebuilt
    }

    /// Adopts a document changed outside the tools (opened, undone, edited in the UI) and rebuilds it.
    public func load(_ document: CADDocument) async {
        if document == self.document, builtDocument == document || buildingDocument == document { return }
        self.document = document
        publishListing()
        _ = try? await rebuild()
    }

    /// Replaces the document with an edited one, reports it through `onCommit` and rebuilds it.
    /// Returns the rebuild of `document`, even when a newer document replaced it meanwhile.
    @discardableResult
    public func apply(_ document: CADDocument, actionName: String) async -> RebuildResult? {
        self.document = document
        publishListing()
        onCommit?(document, actionName)
        return try? await rebuild()
    }

    /// The rebuild of the current document, rebuilding first when the latest result is for another document.
    public func currentResult() async -> RebuildResult? {
        if builtDocument == document { return result }
        return try? await rebuild()
    }

    private func publishListing() {
        let text = listing
        snapshot.withLock { $0 = text }
    }
}

public struct ListingContext: AssistantContext {
    public let listing: String

    public init(listing: String) {
        self.listing = listing
    }

    public var contextDescription: String {
        "Current model (lengths in mm, angles in degrees):\n\(listing)"
    }
}
```

- [ ] **Step 5: CI** — in `.github/workflows/ci.yml`, before `- name: Test app`:

```yaml
      - name: Test CADAssistantTools
        working-directory: Packages/CADAssistantTools
        run: xcrun swift test
```

- [ ] **Step 6: Run to verify they pass** — same command; expected: all pass.

- [ ] **Step 7: Commit** — `feat(tools): list documents in a headless CAD session`

### Task 4: Write pipeline, set_parameter and get_listing

**Files:**
- Create: `Sources/CADAssistantTools/{ToolError,Arguments,ExpressionAudit,WriteReport,ToolSchemas,ReadTools,SetParameterTool,CADTools}.swift`
- Test: `Tests/CADAssistantToolsTests/{Harness,SetParameterToolTests}.swift`

**Interfaces:**
- Consumes: `CADSession.apply`, `currentResult`, `listing`; `DocumentListing.lines`.
- Produces: `struct ToolError: Error, CustomStringConvertible`; `struct Arguments` (`init(_:allowed:) throws(ToolError)`, `string`, `requiredString`, `bool`, `scalar`, `strings`, `object`, `static scalar(_:_:)`); `enum Naming { isIdentifier, checkFeatureName(_:in:excluding:) }`; `CADDocument.partIndex(named:)`, `featureLocation(named:part:)`; `ExpressionAudit.check(before:after:) throws(ToolError)`; `FeatureKind.scalarFields: [(String, Scalar)]`; `struct WriteFocus { actionName, summary, feature: UUID? }`; `CADSession.write(_ change: (inout CADDocument) throws(ToolError) -> WriteFocus) async -> ToolExecutionResult`; `ToolSchemas.scalar(_:_:required:)`, `.featureName`, `.part`, `.placement`; `GetListingTool`, `SetParameterTool` (public, `init(session:)`); `CADTools.all(session:)`.

- [ ] **Step 1: Write the failing tests**

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/Harness.swift`:

```swift
import CADModel
import Foundation
import SwiftUIAssistant

@testable import CADAssistantTools

/// A session over the fake kernel that records every commit, with shortcuts for calling tools by name.
@MainActor
final class Harness {
    let session: CADSession
    private(set) var commits: [String] = []

    init(_ document: CADDocument = CADDocument(parts: [Part(name: "Plate")])) {
        session = CADSession(document: document, kernel: FakeKernel())
        session.onCommit = { [unowned self] _, action in commits.append(action) }
    }

    var document: CADDocument { session.document }

    func features(_ part: Int = 0) -> [String] { document.parts[part].features.map(\.name) }

    func call(_ tool: String, _ arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        let match = CADTools.all(session: session).first { $0.name == tool }
        guard let match else { fatalError("no tool \(tool)") }
        return try await match.execute(arguments: arguments)
    }

    /// Calls the tool and checks the call failed without touching the document or the undo history.
    func refused(_ tool: String, _ arguments: [String: JSONValue]) async throws -> String? {
        let before = document
        let commitCount = commits.count
        let result = try await call(tool, arguments)
        guard !result.success, document == before, commits.count == commitCount else { return nil }
        return result.message
    }
}

extension Fixtures {
    static func plateParametersOnly() -> CADDocument {
        CADDocument(parameters: plateParameters, parts: [Part(name: "Plate")])
    }
}
```

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/SetParameterToolTests.swift`:

```swift
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("set_parameter")
struct SetParameterToolTests {
    @Test("Adding a parameter appends it and reports the changed listing line")
    func adds() async throws {
        let harness = Harness()

        let result = try await harness.call("set_parameter", ["name": "width", "expression": 60])

        #expect(result.success)
        #expect(harness.document.parameters == [Parameter(name: "width", expression: 60)])
        #expect(harness.commits == ["Add Parameter width"])
        #expect(
            result.message == """
                Added parameter width = 60
                Bodies: none
                Listing changes:
                  - parameters: none
                  + parameters: width = 60
                """)
    }

    @Test("Changing a parameter rebuilds and reports the features whose status changed")
    func updatesAndReportsStatusChanges() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("set_parameter", ["name": "width", "expression": "0"])

        #expect(result.success)
        #expect(harness.commits == ["Set Parameter width"])
        #expect(harness.document.parameters[0].expression == 0)
        #expect(result.message.contains("Status changes elsewhere:\n  Base: ok → failed: dimensions must be positive"))
        #expect(result.message.contains("  Hole: ok → skipped: depends on Base"))
        #expect(result.message.contains("+ parameters: width = 0, depth = 40"))
    }

    @Test("Expression strings are kept as expressions and numeric strings become numbers")
    func expressionStrings() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        _ = try await harness.call("set_parameter", ["name": "gap", "expression": "t / 4"])
        _ = try await harness.call("set_parameter", ["name": "count", "expression": " 3 "])

        #expect(
            harness.document.parameters.suffix(2) == [
                Parameter(name: "gap", expression: "t / 4"), Parameter(name: "count", expression: 3),
            ])
        #expect(harness.session.listing.contains("gap = t / 4 (= 2.5), count = 3"))
    }

    @Test("Removing an unused parameter succeeds")
    func removes() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        let result = try await harness.call("set_parameter", ["name": "hole_r", "remove": true])

        #expect(result.success)
        #expect(harness.commits == ["Remove Parameter hole_r"])
        #expect(!harness.document.parameters.contains { $0.name == "hole_r" })
    }

    @Test("Removing a parameter that features or parameters use is refused with every broken expression")
    func removeInUseRefused() async throws {
        let harness = Harness(Fixtures.plate())

        let message = try await harness.refused("set_parameter", ["name": "hole_d", "remove": true])

        #expect(
            message == """
                Nothing changed, because these expressions would not evaluate:
                  parameter hole_r = hole_d / 2: unknown parameter 'hole_d'
                  Hole.radius = hole_r: parameter 'hole_r' has an error
                """)
    }

    @Test("Bad expressions, cycles and bad names are refused and leave the document unchanged")
    func badInput() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        #expect(
            try await harness.refused("set_parameter", ["name": "a", "expression": "1 +"])?.contains("syntax error")
                == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "t", "expression": "width / (depth - 40)"])?.contains(
                "parameter t = width / (depth - 40): division by zero") == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "hole_d", "expression": "hole_r * 2"])?.contains(
                "cycle") == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "2x", "expression": 1])?.contains(
                "not a valid parameter name") == true)
        #expect(
            try await harness.refused("set_parameter", ["name": "x"])
                == "Give 'expression' to set the parameter, or 'remove': true.")
        #expect(
            try await harness.refused("set_parameter", ["name": "t", "expression": 1, "remove": true])
                == "Give either 'expression' or 'remove', not both.")
        #expect(
            try await harness.refused("set_parameter", ["name": "nope", "remove": true])
                == "No parameter named 'nope'. Parameters: width, depth, t, hole_d, hole_r.")
        #expect(
            try await harness.refused("set_parameter", ["name": "x", "value": 1])
                == "Unknown argument 'value'. Accepted: name, expression, remove.")
        #expect(
            try await harness.refused("set_parameter", ["name": "x", "expression": true])?.contains(
                "must be a number or an expression") == true)
    }

    @Test("Setting a parameter to its current expression changes nothing and adds no undo step")
    func noChange() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        let result = try await harness.call("set_parameter", ["name": "t", "expression": 10])

        #expect(result.success)
        #expect(result.message == "Set parameter t = 10. Nothing changed.")
        #expect(harness.commits.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify they fail** — Run: `cd Packages/CADAssistantTools && xcrun swift test > <scratch>/t.log 2>&1; tail -3 <scratch>/t.log`
Expected: compile errors.

- [ ] **Step 3: Implement**

`Packages/CADAssistantTools/Sources/CADAssistantTools/ToolError.swift`:

```swift
struct ToolError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/Arguments.swift`:

```swift
import CADModel
import SwiftUIAssistant

/// Tool arguments checked against the keys a tool accepts; JSON nulls count as absent.
struct Arguments {
    private let values: [String: JSONValue]

    init(_ values: [String: JSONValue], allowed: [String]) throws(ToolError) {
        let unknown = values.keys.filter { !allowed.contains($0) }.sorted()
        guard unknown.isEmpty else {
            throw ToolError(
                "Unknown argument \(unknown.map { "'\($0)'" }.joined(separator: ", ")). "
                    + "Accepted: \(allowed.joined(separator: ", ")).")
        }
        self.values = values.filter { !$0.value.isNull }
    }

    var keys: Set<String> { Set(values.keys) }

    func has(_ key: String) -> Bool { values[key] != nil }

    func string(_ key: String) throws(ToolError) -> String? {
        guard let value = values[key] else { return nil }
        guard let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ToolError("'\(key)' must be a non-empty string.")
        }
        return text
    }

    func requiredString(_ key: String) throws(ToolError) -> String {
        guard let text = try string(key) else { throw ToolError("Missing required argument '\(key)'.") }
        return text
    }

    func bool(_ key: String) throws(ToolError) -> Bool? {
        guard let value = values[key] else { return nil }
        guard let flag = value.boolValue else { throw ToolError("'\(key)' must be true or false.") }
        return flag
    }

    func scalar(_ key: String) throws(ToolError) -> Scalar? {
        try values[key].map { (value) throws(ToolError) in try Self.scalar(value, key) }
    }

    func strings(_ key: String) throws(ToolError) -> [String]? {
        guard let value = values[key] else { return nil }
        guard let items = value.arrayValue else { throw ToolError("'\(key)' must be an array of body names.") }
        var names: [String] = []
        for item in items {
            guard let name = item.stringValue?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
                throw ToolError("'\(key)' must be an array of body names.")
            }
            names.append(name)
        }
        return names
    }

    func object(_ key: String) throws(ToolError) -> [String: JSONValue]? {
        guard let value = values[key] else { return nil }
        guard let object = value.objectValue else { throw ToolError("'\(key)' must be an object.") }
        return object
    }

    /// A number, or a string holding a number or an expression over parameters.
    static func scalar(_ value: JSONValue, _ key: String) throws(ToolError) -> Scalar {
        switch value {
        case .number(let number) where number.isFinite: return .number(number)
        case .integer(let integer): return .number(Double(integer))
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ToolError("'\(key)' is empty; give a number or an expression.") }
            if let number = Double(trimmed), number.isFinite { return .number(number) }
            return .expression(trimmed)
        default:
            throw ToolError("'\(key)' must be a number or an expression string such as \"width / 2\".")
        }
    }
}

enum Naming {
    static func isIdentifier(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLetter || first == "_", name.count <= 64 else {
            return false
        }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }

    static func checkFeatureName(_ name: String, in part: Part, excluding id: UUID? = nil) throws(ToolError) {
        guard isIdentifier(name) else {
            throw ToolError(
                "'\(name)' is not a valid feature name: use letters, digits and _, starting with a letter or _.")
        }
        if let other = part.features.first(where: { $0.name == name && $0.id != id }) {
            throw ToolError("Part \(part.name) already has a feature named '\(other.name)'.")
        }
    }
}

extension CADDocument {
    func partIndex(named name: String?) throws(ToolError) -> Int {
        let names = parts.map(\.name).joined(separator: ", ")
        guard let name else {
            switch parts.count {
            case 0: throw ToolError("The document has no parts.")
            case 1: return 0
            default: throw ToolError("The document has several parts (\(names)); say which one with 'part'.")
            }
        }
        guard let index = parts.firstIndex(where: { $0.name == name }) else {
            throw ToolError("No part named '\(name)'. Parts: \(names.isEmpty ? "none" : names).")
        }
        return index
    }

    func featureLocation(named name: String, part: String?) throws(ToolError) -> (part: Int, feature: Int) {
        let candidates =
            try part.map { (part) throws(ToolError) in [try partIndex(named: part)] } ?? Array(parts.indices)
        let matches = candidates.compactMap { index in
            parts[index].features.firstIndex { $0.name == name }.map { (part: index, feature: $0) }
        }
        switch matches.count {
        case 1:
            return matches[0]
        case 0:
            let listing = candidates.map { index in
                let features = parts[index].features.map(\.name)
                return "\(parts[index].name): \(features.isEmpty ? "none" : features.joined(separator: ", "))"
            }
            throw ToolError("No feature named '\(name)'. Features by part: \(listing.joined(separator: "; ")).")
        default:
            let owners = matches.map { parts[$0.part].name }.joined(separator: ", ")
            throw ToolError("Several parts have a feature named '\(name)' (\(owners)); say which one with 'part'.")
        }
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/ExpressionAudit.swift`:

```swift
import CADModel

/// Refuses an edit that leaves an expression failing that did not fail before, so a typo never reaches the model.
enum ExpressionAudit {
    struct Failure {
        let key: String
        let text: String
    }

    static func failures(in document: CADDocument) -> [Failure] {
        let table = ParameterTable(document.parameters)
        var failures: [Failure] = []
        for parameter in table.parameters {
            if case .failure(let error) = parameter.value {
                failures.append(
                    Failure(
                        key: "parameter \(parameter.name)",
                        text: "parameter \(parameter.name) = \(parameter.expression): \(error)"))
            }
        }
        for part in document.parts {
            for feature in part.features {
                for (field, scalar) in feature.kind.scalarFields {
                    do {
                        _ = try table.evaluate(scalar)
                    } catch {
                        failures.append(
                            Failure(
                                key: "\(feature.id) \(field) \(scalar)",
                                text: "\(feature.name).\(field) = \(scalar): \(error)"))
                    }
                }
            }
        }
        return failures
    }

    static func check(before: CADDocument, after: CADDocument) throws(ToolError) {
        let known = Set(failures(in: before).map(\.key))
        let introduced = failures(in: after).filter { !known.contains($0.key) }
        guard !introduced.isEmpty else { return }
        throw ToolError(
            "Nothing changed, because these expressions would not evaluate:\n"
                + introduced.map { "  \($0.text)" }.joined(separator: "\n"))
    }
}

extension FeatureKind {
    /// Every numeric field with the name the rebuild uses in its errors.
    var scalarFields: [(String, Scalar)] {
        switch self {
        case .primitive(let primitive): primitive.shape.scalarFields + primitive.placement.scalarFields
        case .boolean: []
        case .transform(let transform): transform.placement.scalarFields
        }
    }
}

extension PrimitiveShape {
    var scalarFields: [(String, Scalar)] {
        switch self {
        case .box(let width, let depth, let height): [("width", width), ("depth", depth), ("height", height)]
        case .cylinder(let radius, let height): [("radius", radius), ("height", height)]
        case .sphere(let radius): [("radius", radius)]
        case .cone(let bottom, let top, let height): [("bottomRadius", bottom), ("topRadius", top), ("height", height)]
        case .torus(let major, let minor): [("majorRadius", major), ("minorRadius", minor)]
        }
    }
}

extension Placement {
    var scalarFields: [(String, Scalar)] {
        [
            ("placement.translation.x", translation.x), ("placement.translation.y", translation.y),
            ("placement.translation.z", translation.z), ("placement.rotationAxis.x", rotationAxis.x),
            ("placement.rotationAxis.y", rotationAxis.y), ("placement.rotationAxis.z", rotationAxis.z),
            ("placement.rotationDegrees", rotationDegrees),
        ]
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/ToolSchemas.swift`:

```swift
import SwiftUIAssistant

enum ToolSchemas {
    static let scalar: [String: JSONValue] = ["anyOf": [["type": "number"], ["type": "string"]]]

    static let vector: JSONValue = [
        "type": "object",
        "properties": ["x": .object(scalar), "y": .object(scalar), "z": .object(scalar)],
        "additionalProperties": false,
    ]

    static let placement: [String: JSONValue] = [
        "type": "object",
        "properties": ["translation": vector, "rotationAxis": vector, "rotationDegrees": .object(scalar)],
        "additionalProperties": false,
    ]

    static func scalar(_ name: String, _ description: String, required: Bool = false) -> ToolParameter {
        .custom(
            name, description: "\(description) A number or an expression over parameters, e.g. \"width / 2\".",
            required: required, schema: scalar)
    }

    static let featureName = ToolParameter.string("feature", description: "Name of the feature, as in the listing.")

    static let part = ToolParameter.optionalString(
        "part", description: "Name of the part. Needed only when the document has several parts.")
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/ReadTools.swift`:

```swift
import SwiftUIAssistant

public struct GetListingTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "get_listing"

    public let description = """
        Returns the whole document as text: parameters with their values, then each part's features in order, \
        each with what it does, the body it creates or changes, and its rebuild status. Lengths are in mm, angles in \
        degrees.
        """

    public func execute(arguments _: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.getListing()
    }
}

extension CADSession {
    func getListing() async -> ToolExecutionResult {
        _ = await currentResult()
        return .success(listing)
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/SetParameterTool.swift`:

```swift
import CADModel
import SwiftUIAssistant

public struct SetParameterTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "set_parameter"

    public let description = """
        Adds a document parameter, changes its expression, or removes it. Any numeric field of a feature can use \
        parameters by name. Lengths are in mm and angles in degrees. An expression is a number or arithmetic \
        (+ - * /, parentheses) over other parameters. The change is refused when it would make an expression that \
        works now stop evaluating, for example by removing a parameter that features still use.
        """

    public var parameters: [ToolParameter] {
        [
            .string("name", description: "Parameter name: letters, digits and _, starting with a letter or _."),
            ToolSchemas.scalar("expression", "The new value. Leave out when removing."),
            ToolParameter(
                name: "remove", type: .boolean, description: "true to remove the parameter.", required: false),
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.setParameter(arguments)
    }
}

extension CADSession {
    func setParameter(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["name", "expression", "remove"])
            let name = try arguments.requiredString("name")
            let expression = try arguments.scalar("expression")
            let exists = document.parameters.contains { $0.name == name }
            if try arguments.bool("remove") == true {
                guard expression == nil else { throw ToolError("Give either 'expression' or 'remove', not both.") }
                guard exists else {
                    let names = document.parameters.map(\.name)
                    throw ToolError(
                        "No parameter named '\(name)'. Parameters: \(names.isEmpty ? "none" : names.joined(separator: ", "))."
                    )
                }
                document.parameters.removeAll { $0.name == name }
                return WriteFocus(actionName: "Remove Parameter \(name)", summary: "Removed parameter \(name)")
            }
            guard let expression else { throw ToolError("Give 'expression' to set the parameter, or 'remove': true.") }
            if exists {
                for index in document.parameters.indices where document.parameters[index].name == name {
                    document.parameters[index].expression = expression
                }
                return WriteFocus(actionName: "Set Parameter \(name)", summary: "Set parameter \(name) = \(expression)")
            }
            guard Naming.isIdentifier(name) else {
                throw ToolError(
                    "'\(name)' is not a valid parameter name: use letters, digits and _, starting with a letter or _.")
            }
            document.parameters.append(Parameter(name: name, expression: expression))
            return WriteFocus(actionName: "Add Parameter \(name)", summary: "Added parameter \(name) = \(expression)")
        }
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/WriteReport.swift` (body-reference repair arrives in Task 5; here `notes` is empty):

```swift
import CADModel
import Foundation
import SwiftUIAssistant

/// What a write tool tells the model: the edited feature's status, statuses that changed elsewhere, every body's
/// validity and size, and the listing lines that changed.
struct WriteReport {
    var summary: String
    var focus: UUID?
    var notes: [String] = []
    var before: CADDocument
    var beforeResult: RebuildResult?
    var after: CADDocument
    var afterResult: RebuildResult?

    func render() -> String {
        var lines = [summary]
        guard let afterResult else {
            lines.append("The rebuild did not finish; call get_listing to see the statuses.")
            return lines.joined(separator: "\n")
        }
        if let focus, let feature = afterResult.feature(id: focus) {
            lines.append("\(feature.name): \(feature.status)")
        }
        let changes = statusChanges(afterResult)
        if !changes.isEmpty {
            lines.append("Status changes elsewhere:")
            lines += changes.map { "  \($0)" }
        }
        if !notes.isEmpty {
            lines.append("Body references renumbered:")
            lines += notes.map { "  \($0)" }
        }
        let bodies = afterResult.parts.flatMap { part in part.bodies.map { Self.describe($0, in: part.name) } }
        lines.append(bodies.isEmpty ? "Bodies: none" : "Bodies:")
        lines += bodies.map { "  \($0)" }
        let diff = Self.diff(
            DocumentListing.lines(before, result: beforeResult), DocumentListing.lines(after, result: afterResult))
        if !diff.isEmpty {
            lines.append("Listing changes:")
            lines += diff.map { "  \($0)" }
        }
        return lines.joined(separator: "\n")
    }

    private func statusChanges(_ afterResult: RebuildResult) -> [String] {
        guard let beforeResult else { return [] }
        return afterResult.parts.flatMap(\.features).compactMap { feature in
            guard feature.id != focus, let old = beforeResult.feature(id: feature.id), old.status != feature.status
            else { return nil }
            return "\(feature.name): \(old.status) → \(feature.status)"
        }
    }

    static func describe(_ body: BodyResult, in part: String) -> String {
        let name = "\(body.name) (\(part))"
        guard let metrics = body.metrics else { return "\(name): error: \(body.error ?? "no metrics")" }
        var problems: [String] = []
        if !metrics.isValid { problems.append("invalid shape") }
        if !metrics.isClosed { problems.append("not closed") }
        if metrics.solidCount != 1 { problems.append("\(metrics.solidCount) solids") }
        let state = problems.isEmpty ? "valid closed solid" : "problems: \(problems.joined(separator: ", "))"
        let volume = metrics.volume.map { "volume \(Format.number($0)) mm³" } ?? "volume unknown"
        return
            "\(name): \(state), \(volume), bounds \(Format.point(metrics.boundsMin)) to \(Format.point(metrics.boundsMax))"
    }

    /// Lines only in `old` as "- …", then lines only in `new` as "+ …", each in its listing's order.
    static func diff(_ old: [String], _ new: [String]) -> [String] {
        func unmatched(_ lines: [String], against other: [String]) -> [String] {
            var available = Dictionary(other.map { ($0, 1) }, uniquingKeysWith: +)
            return lines.filter { line in
                guard let count = available[line], count > 0 else { return true }
                available[line] = count - 1
                return false
            }
        }
        let trim = { (line: String) in line.trimmingCharacters(in: .whitespaces) }
        return unmatched(old, against: new).map { "- " + trim($0) }
            + unmatched(new, against: old).map { "+ " + trim($0) }
    }
}

struct WriteFocus {
    var actionName: String
    var summary: String
    var feature: UUID?
}

extension CADSession {
    /// Applies one tool edit as a single undoable step: validates it, keeps body references pointing at the same
    /// creating features, refuses new expression failures, commits, rebuilds and reports.
    func write(_ change: (inout CADDocument) throws(ToolError) -> WriteFocus) async -> ToolExecutionResult {
        let beforeResult = await currentResult()
        let before = document
        var after = before
        let focus: WriteFocus
        let notes: [String]
        do throws(ToolError) {
            focus = try change(&after)
            notes = []
            try ExpressionAudit.check(before: before, after: after)
        } catch {
            return .failure(error.description)
        }
        guard after != before else { return .success("\(focus.summary). Nothing changed.") }
        let afterResult = await apply(after, actionName: focus.actionName)
        let report = WriteReport(
            summary: focus.summary, focus: focus.feature, notes: notes, before: before,
            beforeResult: beforeResult, after: after, afterResult: afterResult)
        return .success(report.render())
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/CADTools.swift`:

```swift
import SwiftUIAssistant

public enum CADTools {
    /// Every CAD tool, operating on `session`.
    public static func all(session: CADSession) -> [any AssistantTool] {
        [
            GetListingTool(session: session),
            SetParameterTool(session: session),
        ]
    }
}
```

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — `feat(tools): set parameters through a validated write`

### Task 5: add_feature and edit_feature with body-reference repair

**Files:**
- Create: `Sources/CADAssistantTools/{FeatureSpec,FeatureEditTools,BodyReferenceRepair}.swift`
- Modify: `WriteReport.swift` (`notes = try BodyReferenceRepair.apply(from: before, to: &after)`), `CADTools.swift`
- Test: `Tests/CADAssistantToolsTests/{AddFeatureToolTests,EditFeatureToolTests}.swift`

**Interfaces:**
- Consumes: Task 4 pipeline; `Part.createdBodies()`, `FeatureKind.renameBodyReferences` (Task 2).
- Produces: `struct FeatureSpec` (`init(_ kind:)`, `init(_ arguments:) throws(ToolError)`, `overriding(_ base:)`, `kind(given:) throws(ToolError) -> FeatureKind`, `isEmpty`, static `types`, `keys`, `solidOperations`); `ToolSchemas.kindParameters(typeRequired:)`; `BodyReferenceRepair.apply(from:to:) throws(ToolError) -> [String]`; `AddFeatureTool`, `EditFeatureTool`.

- [ ] **Step 1: Write the failing tests**

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/AddFeatureToolTests.swift`:

```swift
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("add_feature")
struct AddFeatureToolTests {
    @Test("A box with expressions reports its status, the body and the new listing line")
    func box() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())

        let result = try await harness.call(
            "add_feature", ["name": "Base", "type": "box", "width": "width", "depth": "depth", "height": "t"])

        #expect(result.success)
        #expect(harness.commits == ["Add Base"])
        #expect(
            result.message == """
                Added Base to part Plate
                Base: ok
                Bodies:
                  Body1 (Plate): valid closed solid, volume 24000 mm³, bounds (0, 0, 0) to (60, 40, 10)
                Listing changes:
                  - (no features)
                  + Base  box width×depth×t at origin → Body1  ok
                """)
    }

    @Test("A placed cylinder cuts an existing body")
    func cutCylinder() async throws {
        let harness = Harness(Fixtures.plateParametersOnly())
        _ = try await harness.call("add_feature", ["type": "box", "width": 60, "depth": 40, "height": 10])

        let result = try await harness.call(
            "add_feature",
            [
                "name": "Hole", "type": "cylinder", "radius": "hole_r", "height": "t",
                "placement": ["translation": ["x": "width / 2", "y": 20]], "operation": "cut", "body": "Body1",
            ])

        #expect(result.success)
        #expect(harness.features() == ["Box1", "Hole"])
        #expect(
            harness.document.parts[0].features[1].kind
                == .primitive(
                    PrimitiveFeature(
                        .cylinder(radius: "hole_r", height: "t"),
                        placement: Placement(translation: Vector3("width / 2", 20, 0)), operation: .cut("Body1"))))
        #expect(result.message.contains("Hole: ok"))
        #expect(result.message.contains("Body1 (Plate): valid closed solid, volume 23773.125 mm³"))
    }

    @Test("Default names count up per type, and translations may be given as [x, y, z]")
    func defaultsAndArrays() async throws {
        let harness = Harness()

        _ = try await harness.call("add_feature", ["type": "sphere", "radius": 2])
        _ = try await harness.call(
            "add_feature",
            [
                "type": "sphere", "radius": 1,
                "placement": [
                    "translation": [1, 2, "3"], "rotationAxis": ["x": 1, "y": 0, "z": 0], "rotationDegrees": 90,
                ],
            ])
        _ = try await harness.call(
            "add_feature", ["type": "boolean", "operation": "union", "body": "Body1", "tools": ["Body2"]])
        _ = try await harness.call(
            "add_feature", ["type": "transform", "body": "Body1", "placement": ["translation": ["z": 5]]])

        #expect(harness.features() == ["Sphere1", "Sphere2", "Boolean1", "Transform1"])
        #expect(
            harness.document.parts[0].features[1].kind
                == .primitive(
                    PrimitiveFeature(
                        .sphere(radius: 1),
                        placement: Placement(
                            translation: Vector3(1, 2, 3), rotationAxis: Vector3(1, 0, 0), rotationDegrees: 90))))
        #expect(
            harness.document.parts[0].features[3].kind
                == .transform(TransformFeature(body: "Body1", placement: Placement(translation: Vector3(0, 0, 5)))))
        #expect(harness.session.result?.parts[0].features.map(\.status) == [.ok, .ok, .ok, .ok])
    }

    @Test("Inserting a new body before others renumbers the references that follow")
    func insertRenumbers() async throws {
        let harness = Harness()
        _ = try await harness.call("add_feature", ["name": "A", "type": "box", "width": 10, "depth": 10, "height": 10])
        _ = try await harness.call(
            "add_feature", ["name": "Cut", "type": "sphere", "radius": 1, "operation": "cut", "body": "Body1"])

        let result = try await harness.call(
            "add_feature", ["name": "First", "type": "sphere", "radius": 3, "before": "A"])

        #expect(result.success)
        #expect(harness.features() == ["First", "A", "Cut"])
        #expect(harness.document.parts[0].features[2].kind.bodyReferences == ["Body2"])
        #expect(result.message.contains("Body references renumbered:\n  Cut now refers to Body2 (was Body1)"))
        #expect(harness.session.result?.parts[0].features.map(\.status) == [.ok, .ok, .ok])
    }

    @Test("'after' inserts right after the named feature")
    func insertAfter() async throws {
        let harness = Harness()
        _ = try await harness.call("add_feature", ["name": "A", "type": "sphere", "radius": 1])
        _ = try await harness.call("add_feature", ["name": "B", "type": "sphere", "radius": 1])

        _ = try await harness.call("add_feature", ["name": "C", "type": "transform", "body": "Body1", "after": "A"])

        #expect(harness.features() == ["A", "C", "B"])
    }

    @Test("Wrong or missing fields are refused with a precise message")
    func refusals() async throws {
        let harness = Harness(Fixtures.plate())
        func refused(_ arguments: [String: JSONValue]) async throws -> String? {
            try await harness.refused("add_feature", arguments)
        }

        #expect(
            try await refused(["radius": 1])
                == "Missing 'type'. Types: box, cylinder, sphere, cone, torus, boolean, transform.")
        #expect(
            try await refused(["type": "wedge"])
                == "Unknown type 'wedge'. Types: box, cylinder, sphere, cone, torus, boolean, transform.")
        #expect(try await refused(["type": "box", "width": 1, "depth": 1]) == "A box needs 'height'.")
        #expect(
            try await refused(["type": "box", "width": 1, "depth": 1, "height": 1, "radius": 2])
                == "A box does not take 'radius'; it takes width, depth, height.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "body": "Body1"])
                == "'body' only applies to join, cut and intersect; newBody creates its own body.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "operation": "cut"])
                == "Operation cut needs 'body', the body to cut.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "operation": "union"])
                == "A solid's 'operation' is one of newBody, join, cut, intersect, not 'union'.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "tools": ["Body1"]]) == "A sphere does not take 'tools'.")
        #expect(
            try await refused(["type": "boolean", "operation": "subtract", "body": "Body1"])
                == "A boolean needs 'tools', a non-empty list of bodies.")
        #expect(
            try await refused(["type": "boolean", "operation": "cut", "body": "Body1", "tools": ["Body2"]])
                == "A boolean needs 'operation': union, subtract, intersect.")
        #expect(
            try await refused([
                "type": "boolean", "operation": "union", "body": "Body1", "tools": ["Body2"], "radius": 1,
            ]) == "A boolean does not take 'radius'.")
        #expect(
            try await refused(["type": "transform", "body": "Body1", "operation": "cut"])
                == "A transform does not take 'operation'.")
        #expect(try await refused(["type": "transform"]) == "A transform needs 'body', the body to move.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "name": "Base"])
                == "Part Plate already has a feature named 'Base'.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "name": "my ball"])?.hasPrefix(
                "'my ball' is not a valid feature name") == true)
        #expect(
            try await refused(["type": "sphere", "radius": 1, "before": "Nope"])
                == "No feature named 'Nope' in part Plate.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "before": "Base", "after": "Hole"])
                == "Give 'before' or 'after', not both.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "part": "Lid"]) == "No part named 'Lid'. Parts: Plate.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "placement": ["position": [1, 2, 3]]])
                == "Unknown argument 'position'. Accepted: translation, rotationAxis, rotationDegrees.")
        #expect(
            try await refused(["type": "sphere", "radius": 1, "placement": ["translation": [1, 2]]])
                == "'placement.translation' must have x, y and z.")
        #expect(
            try await refused(["type": "box", "width": "wdth", "depth": 1, "height": "t +"]) == """
                Nothing changed, because these expressions would not evaluate:
                  Box1.width = wdth: unknown parameter 'wdth'
                  Box1.height = t +: syntax error: unexpected end of expression
                """)
    }

    @Test("A document with several parts needs the part named")
    func severalParts() async throws {
        let harness = Harness(CADDocument(parts: [Part(name: "A"), Part(name: "B")]))

        #expect(
            try await harness.refused("add_feature", ["type": "sphere", "radius": 1])
                == "The document has several parts (A, B); say which one with 'part'.")
        #expect(try await harness.call("add_feature", ["type": "sphere", "radius": 1, "part": "B"]).success)
        #expect(harness.features(1) == ["Sphere1"])
    }

    @Test("A feature that fails to build is still added, and its failure is reported")
    func failingFeature() async throws {
        let harness = Harness()

        let result = try await harness.call(
            "add_feature", ["type": "cone", "bottomRadius": 2, "topRadius": 2, "height": 3])

        #expect(result.success)
        #expect(result.message.contains("Cone1: failed: cone radii must differ"))
        #expect(result.message.contains("Bodies: none"))
    }
}
```

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/EditFeatureToolTests.swift`:

```swift
@testable import CADAssistantTools
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@MainActor
@Suite("edit_feature")
struct EditFeatureToolTests {
    private func hole(_ harness: Harness) -> FeatureKind {
        harness.document.parts[0].features[1].kind
    }

    @Test("Only the given fields change; the rest of the placement is kept")
    func partialEdit() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call(
            "edit_feature", ["feature": "Hole", "radius": 4, "placement": ["translation": ["x": 12]]]
        )

        #expect(result.success)
        #expect(harness.commits == ["Edit Hole"])
        #expect(
            hole(harness)
                == .primitive(
                    PrimitiveFeature(
                        .cylinder(radius: 4, height: "t"),
                        placement: Placement(translation: Vector3(12, "depth / 2", 0)),
                        operation: .cut("Body1")
                    )
                )
        )
        #expect(result.message.contains("Hole: ok"))
        #expect(
            result.message.contains("- Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok")
        )
        #expect(result.message.contains("+ Hole  cylinder r=4 h=t at (12, depth / 2, 0), cut Body1 → Body1  ok"))
    }

    @Test("Switching an operation to newBody drops the old target body")
    func toNewBody() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("edit_feature", ["feature": "Hole", "operation": "newBody"])

        #expect(result.success)
        guard case let .primitive(primitive) = hole(harness) else {
            Issue.record("not a primitive")
            return
        }
        #expect(primitive.operation == .newBody)
        #expect(result.message.contains("→ Body2  ok"))
    }

    @Test("Changing the type keeps shared dimensions and needs the new ones")
    func changeType() async throws {
        let harness = Harness(Fixtures.plate())

        #expect(
            try await harness.refused("edit_feature", ["feature": "Base", "type": "cylinder"])
                == "A cylinder needs 'radius'."
        )
        let result = try await harness.call("edit_feature", ["feature": "Base", "type": "cylinder", "radius": 30])

        #expect(result.success)
        #expect(
            harness.document.parts[0].features[0].kind
                == .primitive(PrimitiveFeature(.cylinder(radius: 30, height: "t")))
        )
    }

    @Test("Edits that name nothing, bad expressions and unknown features are refused")
    func refusals() async throws {
        let harness = Harness(Fixtures.plate())

        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole"])?.hasPrefix(
                "Give at least one field to change"
            ) == true
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole", "radius": .null, "placement": .null])?
                .hasPrefix("Give at least one field to change") == true
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole", "radius": "hole_rr"])?.contains(
                "Hole.radius = hole_rr: unknown parameter 'hole_rr'"
            ) == true
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Holes", "radius": 1])
                == "No feature named 'Holes'. Features by part: Plate: Base, Hole, Pin, BadCone, Merge, Move."
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Hole", "name": "Bore"])
                == "Unknown argument 'name'. Accepted: feature, part, type, width, depth, height, radius, bottomRadius, topRadius, majorRadius, minorRadius, placement, operation, body, tools."
        )
        #expect(
            try await harness.refused("edit_feature", ["feature": "Base", "radius": 3])
                == "A box does not take 'radius'; it takes width, depth, height."
        )
    }

    @Test("Turning a body-creating feature into a join is refused while others use its body")
    func removingUsedBodyRefused() async throws {
        let harness = Harness(Fixtures.plate())

        let message = try await harness.refused(
            "edit_feature", ["feature": "Base", "operation": "join", "body": "Body2"]
        )

        #expect(message?.contains("Hole uses Body1, which Base creates") == true)
        #expect(message?.contains("Merge uses Body1, which Base creates") == true)
        #expect(message?.contains("Move uses Body1, which Base creates") == true)
    }

    @Test("An edit that already failed before but keeps its expression is allowed to change other fields")
    func preexistingFailureAllowed() async throws {
        var document = Fixtures.plate()
        document.parts[0].features[1].kind = .primitive(
            PrimitiveFeature(.cylinder(radius: "missing", height: "t"), operation: .cut("Body1"))
        )
        let harness = Harness(document)

        let result = try await harness.call("edit_feature", ["feature": "Hole", "height": 5])

        #expect(result.success)
        #expect(result.message.contains("Hole: failed: radius: unknown parameter 'missing'"))
    }
}
```

- [ ] **Step 2: Run to verify they fail** — expected: compile errors.

- [ ] **Step 3: Implement**

`Packages/CADAssistantTools/Sources/CADAssistantTools/FeatureSpec.swift`:

```swift
import CADModel
import SwiftUIAssistant

/// The flat argument form of a feature kind shared by add_feature and edit_feature. Every field is optional so an
/// edit can carry only the fields it changes and be laid over the feature's current values.
struct FeatureSpec: Equatable {
    static let shapeDimensions: [String: [String]] = [
        "box": ["width", "depth", "height"],
        "cylinder": ["radius", "height"],
        "sphere": ["radius"],
        "cone": ["bottomRadius", "topRadius", "height"],
        "torus": ["majorRadius", "minorRadius"],
    ]
    static let types = ["box", "cylinder", "sphere", "cone", "torus", "boolean", "transform"]
    static let dimensionKeys = [
        "width", "depth", "height", "radius", "bottomRadius", "topRadius", "majorRadius", "minorRadius",
    ]
    static let keys = ["type"] + dimensionKeys + ["placement", "operation", "body", "tools"]
    static let solidOperations = ["newBody", "join", "cut", "intersect"]
    static let booleanOperations = ["union", "subtract", "intersect"]

    var type: String?
    var dimensions: [String: Scalar] = [:]
    var translation: [String: Scalar] = [:]
    var rotationAxis: [String: Scalar] = [:]
    var rotationDegrees: Scalar?
    var operation: String?
    var body: String?
    var tools: [String]?

    init() {}

    init(_ kind: FeatureKind) {
        switch kind {
        case .primitive(let primitive):
            switch primitive.shape {
            case .box: type = "box"
            case .cylinder: type = "cylinder"
            case .sphere: type = "sphere"
            case .cone: type = "cone"
            case .torus: type = "torus"
            }
            dimensions = Dictionary(uniqueKeysWithValues: primitive.shape.scalarFields)
            setPlacement(primitive.placement)
            switch primitive.operation {
            case .newBody: operation = "newBody"
            case .join(let target): (operation, body) = ("join", target)
            case .cut(let target): (operation, body) = ("cut", target)
            case .intersect(let target): (operation, body) = ("intersect", target)
            }
        case .boolean(let boolean):
            (type, operation, body, tools) = ("boolean", boolean.operation.rawValue, boolean.target, boolean.tools)
        case .transform(let transform):
            (type, body) = ("transform", transform.body)
            setPlacement(transform.placement)
        }
    }

    init(_ arguments: Arguments) throws(ToolError) {
        if let type = try arguments.string("type") {
            guard Self.types.contains(type) else {
                throw ToolError("Unknown type '\(type)'. Types: \(Self.types.joined(separator: ", ")).")
            }
            self.type = type
        }
        for key in Self.dimensionKeys {
            if let value = try arguments.scalar(key) { dimensions[key] = value }
        }
        if let placement = try arguments.object("placement") {
            let placementArguments = try Arguments(
                placement, allowed: ["translation", "rotationAxis", "rotationDegrees"])
            translation = try Self.vector(placement["translation"], "placement.translation")
            rotationAxis = try Self.vector(placement["rotationAxis"], "placement.rotationAxis")
            rotationDegrees = try placementArguments.scalar("rotationDegrees")
        }
        operation = try arguments.string("operation")
        body = try arguments.string("body")
        tools = try arguments.strings("tools")
    }

    private static func vector(_ value: JSONValue?, _ key: String) throws(ToolError) -> [String: Scalar] {
        guard let value, !value.isNull else { return [:] }
        var components: [String: Scalar] = [:]
        if let items = value.arrayValue {
            guard items.count == 3 else { throw ToolError("'\(key)' must have x, y and z.") }
            for (axis, item) in zip(["x", "y", "z"], items) {
                components[axis] = try Arguments.scalar(item, "\(key).\(axis)")
            }
            return components
        }
        guard let object = value.objectValue else { throw ToolError("'\(key)' must be an object with x, y and z.") }
        let arguments = try Arguments(object, allowed: ["x", "y", "z"])
        for axis in ["x", "y", "z"] {
            if let scalar = try arguments.scalar(axis) { components[axis] = scalar }
        }
        return components
    }

    private mutating func setPlacement(_ placement: Placement) {
        translation = ["x": placement.translation.x, "y": placement.translation.y, "z": placement.translation.z]
        rotationAxis = ["x": placement.rotationAxis.x, "y": placement.rotationAxis.y, "z": placement.rotationAxis.z]
        rotationDegrees = placement.rotationDegrees
    }

    var isEmpty: Bool { self == FeatureSpec() }

    var hasPlacement: Bool { !translation.isEmpty || !rotationAxis.isEmpty || rotationDegrees != nil }

    /// These fields laid over `base`. Switching an operation to newBody drops the old target body.
    func overriding(_ base: FeatureSpec) -> FeatureSpec {
        var merged = base
        if let type { merged.type = type }
        merged.dimensions.merge(dimensions) { $1 }
        merged.translation.merge(translation) { $1 }
        merged.rotationAxis.merge(rotationAxis) { $1 }
        if let rotationDegrees { merged.rotationDegrees = rotationDegrees }
        if let operation {
            merged.operation = operation
            if operation == "newBody" { merged.body = nil }
        }
        if let body { merged.body = body }
        if let tools { merged.tools = tools }
        return merged
    }

    /// Builds the kind from these (merged) fields. `given` holds only what the caller passed, and is what
    /// fields that do not apply to the type are checked against.
    func kind(given: FeatureSpec) throws(ToolError) -> FeatureKind {
        guard let type else { throw ToolError("Missing 'type'. Types: \(Self.types.joined(separator: ", ")).") }
        let placement = Placement(
            translation: Vector3(translation["x"] ?? 0, translation["y"] ?? 0, translation["z"] ?? 0),
            rotationAxis: Vector3(rotationAxis["x"] ?? 0, rotationAxis["y"] ?? 0, rotationAxis["z"] ?? 1),
            rotationDegrees: rotationDegrees ?? 0)
        switch type {
        case "boolean":
            try given.reject(dimensions: true, placement: true, type: type)
            guard let operation, let booleanOperation = BooleanOperation(rawValue: operation) else {
                throw ToolError("A boolean needs 'operation': \(Self.booleanOperations.joined(separator: ", ")).")
            }
            guard let body else { throw ToolError("A boolean needs 'body', the target body.") }
            guard let tools, !tools.isEmpty else {
                throw ToolError("A boolean needs 'tools', a non-empty list of bodies.")
            }
            return .boolean(BooleanFeature(operation: booleanOperation, target: body, tools: tools))
        case "transform":
            try given.reject(dimensions: true, operation: true, tools: true, type: type)
            guard let body else { throw ToolError("A transform needs 'body', the body to move.") }
            return .transform(TransformFeature(body: body, placement: placement))
        default:
            try given.reject(tools: true, type: type)
            let names = Self.shapeDimensions[type] ?? []
            if let extra = given.dimensions.keys.sorted().first(where: { !names.contains($0) }) {
                throw ToolError("A \(type) does not take '\(extra)'; it takes \(names.joined(separator: ", ")).")
            }
            var values: [Scalar] = []
            for name in names {
                guard let value = dimensions[name] else { throw ToolError("A \(type) needs '\(name)'.") }
                values.append(value)
            }
            let shape: PrimitiveShape =
                switch type {
                case "box": .box(width: values[0], depth: values[1], height: values[2])
                case "cylinder": .cylinder(radius: values[0], height: values[1])
                case "sphere": .sphere(radius: values[0])
                case "cone": .cone(bottomRadius: values[0], topRadius: values[1], height: values[2])
                default: .torus(majorRadius: values[0], minorRadius: values[1])
                }
            return .primitive(
                PrimitiveFeature(shape, placement: placement, operation: try solidOperation(given: given)))
        }
    }

    private func solidOperation(given: FeatureSpec) throws(ToolError) -> SolidOperation {
        switch operation ?? "newBody" {
        case "newBody":
            if given.body != nil {
                throw ToolError("'body' only applies to join, cut and intersect; newBody creates its own body.")
            }
            return .newBody
        case let mode where Self.solidOperations.contains(mode):
            guard let body else { throw ToolError("Operation \(mode) needs 'body', the body to \(mode).") }
            return mode == "join" ? .join(body) : mode == "cut" ? .cut(body) : .intersect(body)
        case let mode:
            throw ToolError(
                "A solid's 'operation' is one of \(Self.solidOperations.joined(separator: ", ")), not '\(mode)'.")
        }
    }

    private func reject(
        dimensions rejectDimensions: Bool = false, placement: Bool = false, operation rejectOperation: Bool = false,
        tools rejectTools: Bool = false, type: String
    ) throws(ToolError) {
        var extra: [String] = []
        if rejectDimensions { extra += dimensions.keys.sorted() }
        if placement, hasPlacement { extra.append("placement") }
        if rejectOperation, operation != nil { extra.append("operation") }
        if rejectTools, tools != nil { extra.append("tools") }
        guard extra.isEmpty else {
            throw ToolError("A \(type) does not take \(extra.map { "'\($0)'" }.joined(separator: ", ")).")
        }
    }
}

extension ToolSchemas {
    static func kindParameters(typeRequired: Bool) -> [ToolParameter] {
        [
            .enumParameter(
                "type",
                description: """
                    Feature type. box: width along X, depth along Y, height along Z, one corner at the placement \
                    origin. cylinder: radius, height along +Z, base centred on the origin. sphere: radius, centred. \
                    cone: bottomRadius, topRadius, height along +Z. torus: majorRadius, minorRadius, centred, axis Z. \
                    boolean: combine bodies. transform: move or rotate a body.
                    """,
                values: FeatureSpec.types, required: typeRequired),
            scalar("width", "Box size along X in mm."),
            scalar("depth", "Box size along Y in mm."),
            scalar("height", "Box, cylinder or cone height along Z in mm."),
            scalar("radius", "Cylinder or sphere radius in mm."),
            scalar("bottomRadius", "Cone radius at its base in mm."),
            scalar("topRadius", "Cone radius at its top in mm; 0 for a pointed cone."),
            scalar("majorRadius", "Torus radius from its centre to the tube centre in mm."),
            scalar("minorRadius", "Torus tube radius in mm."),
            .custom(
                "placement",
                description: """
                    Solids: where the solid sits. transform: how the body moves. The shape is rotated by \
                    rotationDegrees (degrees) about rotationAxis through the origin, then moved by translation (mm). \
                    Left-out values keep their current value, or the default: no move, axis Z, 0 degrees.
                    """,
                schema: placement),
            .enumParameter(
                "operation",
                description: """
                    Solids: newBody (default) creates a new body; join, cut and intersect combine the solid into the \
                    existing body named by 'body'. boolean: union, subtract or intersect the 'tools' bodies into 'body'.
                    """,
                values: FeatureSpec.solidOperations + ["union", "subtract"], required: false),
            .optionalString(
                "body",
                description: """
                    A body name such as Body1. Solids: the body to join, cut or intersect. boolean: the target body. \
                    transform: the body to move.
                    """),
            .custom(
                "tools", description: "boolean only: the bodies combined into 'body'. They are used up.",
                schema: ["type": "array", "items": ["type": "string"]]),
        ]
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/FeatureEditTools.swift`:

```swift
import CADModel
import Foundation
import SwiftUIAssistant

public struct AddFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "add_feature"

    public let description = """
        Adds a feature to a part: a solid (box, cylinder, sphere, cone, torus) with a placement and an operation, a \
        boolean that combines bodies, or a transform that moves a body. Lengths are in mm, angles in degrees; every \
        number may be an expression over parameters. The n-th feature that creates a new body in a part makes \
        Body<n>. It goes at the end of the part unless 'before' or 'after' names a feature. Returns the new \
        feature's status, status changes elsewhere, every body's validity, volume and bounds, and the changed \
        listing lines.
        """

    public var parameters: [ToolParameter] {
        [
            ToolSchemas.part,
            .optionalString(
                "name",
                description:
                    "Unique name in the part (letters, digits, _). Defaults to the type and a number, e.g. Box2."),
            .optionalString("before", description: "Insert before this feature."),
            .optionalString("after", description: "Insert after this feature."),
        ] + ToolSchemas.kindParameters(typeRequired: true)
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.addFeature(arguments)
    }
}

public struct EditFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "edit_feature"

    public let description = """
        Changes fields of an existing feature; fields left out keep their values, including each placement value. \
        Lengths are in mm, angles in degrees; every number may be an expression over parameters. Changing the type \
        keeps the dimensions both types share. Returns the feature's status, status changes elsewhere, every body's \
        validity, volume and bounds, and the changed listing lines. Use rename_feature to rename.
        """

    public var parameters: [ToolParameter] {
        [ToolSchemas.featureName, ToolSchemas.part] + ToolSchemas.kindParameters(typeRequired: false)
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.editFeature(arguments)
    }
}

extension CADSession {
    func addFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["part", "name", "before", "after"] + FeatureSpec.keys)
            let partIndex = try document.partIndex(named: try arguments.string("part"))
            let given = try FeatureSpec(arguments)
            let kind = try given.kind(given: given)
            let part = document.parts[partIndex]
            let name = try arguments.string("name") ?? Self.defaultName(for: given.type ?? "", in: part)
            try Naming.checkFeatureName(name, in: part)
            var index = part.features.endIndex
            switch (try arguments.string("before"), try arguments.string("after")) {
            case (nil, nil): break
            case (let before?, nil): index = try Self.index(of: before, in: part)
            case (nil, let after?): index = try Self.index(of: after, in: part) + 1
            case (_?, _?): throw ToolError("Give 'before' or 'after', not both.")
            }
            let feature = Feature(name: name, kind: kind)
            document.parts[partIndex].features.insert(feature, at: index)
            return WriteFocus(
                actionName: "Add \(name)", summary: "Added \(name) to part \(part.name)", feature: feature.id)
        }
    }

    func editFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "part"] + FeatureSpec.keys)
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            let given = try FeatureSpec(arguments)
            guard !given.isEmpty else {
                throw ToolError("Give at least one field to change: \(FeatureSpec.keys.joined(separator: ", ")).")
            }
            let kind = try given.overriding(FeatureSpec(feature.kind)).kind(given: given)
            document.parts[location.part].features[location.feature].kind = kind
            return WriteFocus(
                actionName: "Edit \(feature.name)", summary: "Edited \(feature.name)", feature: feature.id)
        }
    }

    private static func index(of name: String, in part: Part) throws(ToolError) -> Int {
        guard let index = part.features.firstIndex(where: { $0.name == name }) else {
            throw ToolError("No feature named '\(name)' in part \(part.name).")
        }
        return index
    }

    private static func defaultName(for type: String, in part: Part) -> String {
        let base = type.prefix(1).uppercased() + type.dropFirst()
        let names = Set(part.features.map(\.name))
        return (1...).lazy.map { "\(base)\($0)" }.first { !names.contains($0) }!
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/BodyReferenceRepair.swift`:

```swift
import CADModel
import Foundation

/// Bodies are named by the order of the features that create them, so adding, deleting or changing a creating
/// feature renames every later body. This keeps each reference pointing at the same creating feature, and refuses
/// the edit when a referenced body would stop existing.
enum BodyReferenceRepair {
    static func apply(from before: CADDocument, to after: inout CADDocument) throws(ToolError) -> [String] {
        var notes: [String] = []
        var conflicts: [String] = []
        for partIndex in after.parts.indices {
            guard let old = before.parts.first(where: { $0.id == after.parts[partIndex].id }) else { continue }
            let owners = old.createdBodies()
            let newNames = Dictionary(uniqueKeysWithValues: after.parts[partIndex].createdBodies().map { ($1, $0) })
            for featureIndex in after.parts[partIndex].features.indices {
                let feature = after.parts[partIndex].features[featureIndex]
                var renamed: [String] = []
                var kind = feature.kind
                kind.renameBodyReferences { name in
                    guard let owner = owners[name] else { return name }
                    guard let newName = newNames[owner] else {
                        let creator = old.features.first { $0.id == owner }?.name ?? "?"
                        conflicts.append("\(feature.name) uses \(name), which \(creator) creates")
                        return name
                    }
                    if newName != name { renamed.append("\(newName) (was \(name))") }
                    return newName
                }
                after.parts[partIndex].features[featureIndex].kind = kind
                if !renamed.isEmpty {
                    notes.append("\(feature.name) now refers to \(renamed.joined(separator: ", "))")
                }
            }
        }
        guard conflicts.isEmpty else {
            throw ToolError(
                "Nothing changed, because bodies that other features use would no longer exist: "
                    + conflicts.joined(separator: "; ")
                    + ". Change or delete those features first, or suppress the creating feature instead.")
        }
        return notes
    }
}
```

In `WriteReport.swift`, replace `notes = []` with `notes = try BodyReferenceRepair.apply(from: before, to: &after)`. `CADTools.swift`:

```swift
import SwiftUIAssistant

public enum CADTools {
    /// Every CAD tool, operating on `session`.
    public static func all(session: CADSession) -> [any AssistantTool] {
        [
            GetListingTool(session: session),
            SetParameterTool(session: session),
            AddFeatureTool(session: session),
            EditFeatureTool(session: session),
        ]
    }
}
```

- [ ] **Step 4: Run to verify they pass.**

- [ ] **Step 5: Commit** — `feat(tools): add and edit features`

### Task 6: delete_feature, rename_feature, suppress_feature

**Files:**
- Create: `Sources/CADAssistantTools/FeatureLifecycleTools.swift`
- Modify: `CADTools.swift` (all seven tools)
- Test: `Tests/CADAssistantToolsTests/FeatureLifecycleToolTests.swift`

**Interfaces:**
- Produces: `DeleteFeatureTool`, `RenameFeatureTool`, `SuppressFeatureTool`; `CADTools.all(session:)` returns, in order, `get_listing`, `set_parameter`, `add_feature`, `edit_feature`, `delete_feature`, `rename_feature`, `suppress_feature`.

- [ ] **Step 1: Write the failing test**

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/FeatureLifecycleToolTests.swift`:

```swift
import CADModel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("delete_feature, rename_feature, suppress_feature, get_listing")
struct FeatureLifecycleToolTests {
    /// A, B and C each create a body; D cuts Body2 (B's), E moves Body3 (C's), F subtracts Body3 from Body2.
    private func threeBodies() -> CADDocument {
        CADDocument(parts: [
            Part(
                name: "P",
                features: [
                    Fixtures.box("A", 1, 1, 1),
                    Fixtures.box("B", 10, 10, 10),
                    Fixtures.box("C", 2, 2, 2),
                    Fixtures.box("D", 1, 1, 1, .cut("Body2")),
                    Feature(
                        name: "E",
                        kind: .transform(
                            TransformFeature(body: "Body3", placement: Placement(translation: Vector3(1, 0, 0))))),
                    Feature(
                        name: "F",
                        kind: .boolean(BooleanFeature(operation: .subtract, target: "Body2", tools: ["Body3"]))),
                ])
        ])
    }

    @Test("Deleting a feature that creates nothing others use removes it and reports what changed")
    func deleteLeaf() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("delete_feature", ["feature": "Hole"])

        #expect(result.success)
        #expect(harness.commits == ["Delete Hole"])
        #expect(harness.features() == ["Base", "Pin", "BadCone", "Merge", "Move"])
        #expect(result.message.hasPrefix("Deleted Hole from part Plate\n"))
        #expect(
            result.message.contains("- Hole  cylinder r=hole_r h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok")
        )
    }

    @Test("Ruling: deleting an earlier body renumbers later references so they keep their bodies")
    func deleteRenumbers() async throws {
        let harness = Harness(threeBodies())
        let before = try #require(await harness.session.currentResult())

        let result = try await harness.call("delete_feature", ["feature": "A"])

        #expect(result.success)
        let kinds = harness.document.parts[0].features.map(\.kind.bodyReferences)
        #expect(kinds == [[], [], ["Body1"], ["Body2"], ["Body1", "Body2"]])
        #expect(
            result.message.contains(
                """
                Body references renumbered:
                  D now refers to Body1 (was Body2)
                  E now refers to Body2 (was Body3)
                  F now refers to Body1 (was Body2), Body2 (was Body3)
                """))
        let after = try #require(harness.session.result)
        #expect(after.parts[0].features.map(\.status) == [.ok, .ok, .ok, .ok, .ok])
        #expect(
            after.parts[0].bodies.map(\.metrics?.volume)
                == before.parts[0].bodies.dropFirst().prefix(1).map(\.metrics?.volume))
    }

    @Test("Ruling: deleting a feature whose body others use is refused and names them")
    func deleteUsedBodyRefused() async throws {
        let harness = Harness(threeBodies())

        let message = try await harness.refused("delete_feature", ["feature": "C"])

        #expect(
            message == """
                Nothing changed, because bodies that other features use would no longer exist: \
                E uses Body3, which C creates; F uses Body3, which C creates. Change or delete those features first, \
                or suppress the creating feature instead.
                """)
    }

    @Test("Deleting an unknown feature, or an ambiguous one, is refused")
    func deleteRefusals() async throws {
        let sphere = { Feature(name: "S", kind: .primitive(PrimitiveFeature(.sphere(radius: 1)))) }
        let harness = Harness(
            CADDocument(parts: [Part(name: "A", features: [sphere()]), Part(name: "B", features: [sphere()])]))

        #expect(
            try await harness.refused("delete_feature", ["feature": "T"])
                == "No feature named 'T'. Features by part: A: S; B: S.")
        #expect(
            try await harness.refused("delete_feature", ["feature": "S"])
                == "Several parts have a feature named 'S' (A, B); say which one with 'part'.")
        #expect(try await harness.call("delete_feature", ["feature": "S", "part": "B"]).success)
        #expect(harness.document.parts.map(\.features.count) == [1, 0])
    }

    @Test("Renaming keeps references, since they point at ids and bodies, not names")
    func rename() async throws {
        let harness = Harness(Fixtures.plate())

        let result = try await harness.call("rename_feature", ["feature": "BadCone", "new_name": "Cone"])

        #expect(result.success)
        #expect(harness.commits == ["Rename BadCone to Cone"])
        #expect(result.message.contains("Cone: failed: cone radii must differ"))
        #expect(result.message.contains("Merge: skipped: depends on BadCone → skipped: depends on Cone"))
        #expect(
            try await harness.refused("rename_feature", ["feature": "Cone", "new_name": "Base"])
                == "Part Plate already has a feature named 'Base'.")
        #expect(
            try await harness.refused("rename_feature", ["feature": "Cone", "new_name": "1st"])?.hasPrefix(
                "'1st' is not a valid feature name") == true)
        #expect(
            try await harness.refused("rename_feature", ["feature": "Nope", "new_name": "X"])?.hasPrefix(
                "No feature named 'Nope'") == true)
        #expect(
            try await harness.call("rename_feature", ["feature": "Cone", "new_name": "Cone"]).message
                == "Renamed Cone to Cone. Nothing changed.")
    }

    @Test("Suppressing skips dependants; unsuppressing restores them; each is one named undo step")
    func suppress() async throws {
        let harness = Harness(Fixtures.plate())

        let suppressed = try await harness.call("suppress_feature", ["feature": "Base"])
        #expect(suppressed.success)
        #expect(suppressed.message.contains("Base: suppressed"))
        #expect(suppressed.message.contains("Hole: ok → skipped: depends on Base"))

        let restored = try await harness.call("suppress_feature", ["feature": "Base", "suppressed": false])
        #expect(restored.message.contains("Base: ok"))
        #expect(harness.commits == ["Suppress Base", "Unsuppress Base"])
        #expect(
            try await harness.call("suppress_feature", ["feature": "Pin"]).message == "Suppressed Pin. Nothing changed."
        )
        #expect(
            try await harness.refused("suppress_feature", ["feature": "Pin", "suppressed": "yes"])
                == "'suppressed' must be true or false.")
    }

    @Test("get_listing rebuilds when needed and returns the listing with statuses")
    func getListing() async throws {
        let plate = Fixtures.plate()
        let harness = Harness(plate)

        let result = try await harness.call("get_listing", [:])

        #expect(result.success)
        #expect(result.message == DocumentListing.render(plate, result: harness.session.result))
        #expect(result.message.contains("Base  box width×depth×t at origin → Body1  ok"))
        #expect(harness.commits.isEmpty)
    }

    @Test("Every tool is offered with a unique name, and descriptions state the units")
    func toolSet() {
        let tools = CADTools.all(session: Harness().session)
        #expect(
            tools.map(\.name) == [
                "get_listing", "set_parameter", "add_feature", "edit_feature", "delete_feature", "rename_feature",
                "suppress_feature",
            ])
        for name in ["get_listing", "set_parameter", "add_feature", "edit_feature"] {
            let description = tools.first { $0.name == name }?.description ?? ""
            #expect(description.contains("mm") && description.contains("degrees"), "\(name)")
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails.**

- [ ] **Step 3: Implement**

`Packages/CADAssistantTools/Sources/CADAssistantTools/FeatureLifecycleTools.swift`:

```swift
import SwiftUIAssistant

public struct DeleteFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "delete_feature"

    public let description = """
        Deletes a feature. Deleting a feature that creates a body renumbers later bodies; references to them are \
        updated to match and reported. The delete is refused while another feature uses the deleted feature's body. \
        Returns status changes, every body's validity, volume and bounds, and the changed listing lines.
        """

    public var parameters: [ToolParameter] { [ToolSchemas.featureName, ToolSchemas.part] }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.deleteFeature(arguments)
    }
}

public struct RenameFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "rename_feature"

    public let description = "Renames a feature. Names are unique within a part: letters, digits and _."

    public var parameters: [ToolParameter] {
        [ToolSchemas.featureName, .string("new_name", description: "The new name."), ToolSchemas.part]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.renameFeature(arguments)
    }
}

public struct SuppressFeatureTool: AssistantTool {
    let session: CADSession

    public init(session: CADSession) {
        self.session = session
    }

    public let name = "suppress_feature"

    public let description = """
        Suppresses a feature so the rebuild skips it, or brings it back with suppressed: false. A suppressed \
        feature keeps its body number; features that use its body are skipped. Returns status changes, every \
        body's validity, volume and bounds, and the changed listing lines.
        """

    public var parameters: [ToolParameter] {
        [
            ToolSchemas.featureName,
            ToolParameter(
                name: "suppressed", type: .boolean, description: "false to unsuppress. Defaults to true.",
                required: false),
            ToolSchemas.part,
        ]
    }

    public func execute(arguments: [String: JSONValue]) async throws -> ToolExecutionResult {
        await session.suppressFeature(arguments)
    }
}

extension CADSession {
    func deleteFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "part"])
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features.remove(at: location.feature)
            return WriteFocus(
                actionName: "Delete \(feature.name)",
                summary: "Deleted \(feature.name) from part \(document.parts[location.part].name)")
        }
    }

    func renameFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "new_name", "part"])
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            let newName = try arguments.requiredString("new_name")
            try Naming.checkFeatureName(newName, in: document.parts[location.part], excluding: feature.id)
            document.parts[location.part].features[location.feature].name = newName
            return WriteFocus(
                actionName: "Rename \(feature.name) to \(newName)", summary: "Renamed \(feature.name) to \(newName)",
                feature: feature.id)
        }
    }

    func suppressFeature(_ raw: [String: JSONValue]) async -> ToolExecutionResult {
        await write { (document) throws(ToolError) in
            let arguments = try Arguments(raw, allowed: ["feature", "suppressed", "part"])
            let location = try document.featureLocation(
                named: try arguments.requiredString("feature"), part: try arguments.string("part"))
            let feature = document.parts[location.part].features[location.feature]
            let suppressed = try arguments.bool("suppressed") ?? true
            document.parts[location.part].features[location.feature].suppressed = suppressed
            let verb = suppressed ? "Suppress" : "Unsuppress"
            return WriteFocus(
                actionName: "\(verb) \(feature.name)", summary: "\(verb)ed \(feature.name)", feature: feature.id)
        }
    }
}
```

`Packages/CADAssistantTools/Sources/CADAssistantTools/CADTools.swift`:

```swift
import SwiftUIAssistant

public enum CADTools {
    /// Every CAD tool, operating on `session`.
    public static func all(session: CADSession) -> [any AssistantTool] {
        [
            GetListingTool(session: session),
            SetParameterTool(session: session),
            AddFeatureTool(session: session),
            EditFeatureTool(session: session),
            DeleteFeatureTool(session: session),
            RenameFeatureTool(session: session),
            SuppressFeatureTool(session: session),
        ]
    }
}
```

- [ ] **Step 4: Run to verify it passes.**

- [ ] **Step 5: Commit** — `feat(tools): delete, rename and suppress features`

### Task 7: System prompt, real-kernel integration and the assistant loop

**Files:**
- Create: `Sources/CADAssistantTools/CADAssistantPrompt.swift`
- Test: `Tests/CADAssistantToolsTests/{RealKernelTests,AssistantLoopTests}.swift`

**Interfaces:**
- Produces: `public enum CADAssistantPrompt { static let system: String; static let configuration: AssistantConfiguration }` (max 30 tool rounds, `attachesContextToMessages: true`).

- [ ] **Step 1: Write the failing tests** (scripted `LLMProvider`; real `OCCTGeometryKernel`)

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/RealKernelTests.swift`:

```swift
import CADModel
import CADModelKernel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

@MainActor
@Suite("Tools on the Open CASCADE kernel")
struct RealKernelTests {
    @Test("A plate with a parametric hole has the exact volume and stays a valid closed solid")
    func plateWithHole() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        let tools = Dictionary(uniqueKeysWithValues: CADTools.all(session: session).map { ($0.name, $0) })
        for (name, value) in [("width", 60), ("depth", 40), ("t", 10)] as [(String, JSONValue)] {
            #expect(
                try await tools["set_parameter"]!.execute(arguments: ["name": .string(name), "expression": value])
                    .success)
        }

        _ = try await tools["add_feature"]!.execute(arguments: [
            "name": "Plate", "type": "box", "width": "width", "depth": "depth", "height": "t",
        ])
        let hole = try await tools["add_feature"]!.execute(arguments: [
            "name": "Hole", "type": "cylinder", "radius": 2.75, "height": "t",
            "placement": ["translation": ["x": "width / 2", "y": "depth / 2"]], "operation": "cut", "body": "Body1",
        ])

        #expect(hole.success)
        #expect(hole.message.contains("Hole: ok"))
        #expect(hole.message.contains("Body1 (Plate): valid closed solid, volume 23762.4"))
        #expect(hole.message.contains("bounds (0, 0, 0) to (60, 40, 10)"))
        let volume = try #require(session.result?.bodies.first?.metrics?.volume)
        #expect(abs(volume - (24000 - Double.pi * 2.75 * 2.75 * 10)) < 0.01)
    }

    @Test("A kernel failure is reported as the feature's status and the document keeps the feature")
    func kernelFailure() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "P")]), kernel: OCCTGeometryKernel())
        let add = AddFeatureTool(session: session)
        _ = try await add.execute(arguments: ["type": "box", "width": 10, "depth": 10, "height": 10])

        let result = try await add.execute(arguments: [
            "type": "box", "width": 5, "depth": 5, "height": 5, "placement": ["translation": [100, 0, 0]],
            "operation": "intersect", "body": "Body1",
        ])

        #expect(result.success)
        #expect(result.message.contains("Box2: failed:"))
        #expect(session.document.parts[0].features.count == 2)
        #expect(result.message.contains("Body1 (P): valid closed solid, volume 1000 mm³"))
    }
}
```

`Packages/CADAssistantTools/Tests/CADAssistantToolsTests/AssistantLoopTests.swift`:

```swift
import CADModel
import CADModelKernel
import Foundation
import SwiftUIAssistant
import Testing

@testable import CADAssistantTools

/// Plays back a fixed list of model turns and records every request it receives.
actor ScriptedProvider: LLMProvider {
    private var turns: [LLMResponse]
    private(set) var requests: [(systemPrompt: String, history: [Message])] = []

    init(_ turns: [LLMResponse]) {
        self.turns = turns
    }

    func sendMessage(
        _ message: String, systemPrompt: String, conversationHistory: [Message], tools: [any AssistantTool]
    ) async throws -> LLMResponse {
        requests.append((systemPrompt, conversationHistory))
        guard !turns.isEmpty else {
            return LLMResponse(content: "(script ended)", toolCalls: nil, stopReason: .endTurn)
        }
        return turns.removeFirst()
    }
}

@MainActor
@Suite("Assistant loop")
struct AssistantLoopTests {
    private func call(_ id: String, _ name: String, _ arguments: [String: JSONValue]) -> ToolCall {
        ToolCall(id: id, name: name, arguments: arguments)
    }

    @Test("A scripted model builds a plate with a hole through the tools, reading results between turns")
    func plateWithHole() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "Plate")]), kernel: OCCTGeometryKernel())
        var commits: [String] = []
        session.onCommit = { commits.append($1) }
        let provider = ScriptedProvider([
            LLMResponse(
                content: "Setting up parameters.",
                toolCalls: [
                    call("1", "set_parameter", ["name": "width", "expression": 60]),
                    call("2", "set_parameter", ["name": "depth", "expression": 40]),
                    call("3", "set_parameter", ["name": "t", "expression": 10]),
                    call("4", "set_parameter", ["name": "hole_d", "expression": 5.5]),
                ], stopReason: .toolUse),
            LLMResponse(
                content: nil,
                toolCalls: [
                    call(
                        "5", "add_feature",
                        ["name": "Plate", "type": "box", "width": "width", "depth": "depth", "height": "t"])
                ],
                stopReason: .toolUse),
            LLMResponse(
                content: nil,
                toolCalls: [
                    call(
                        "6", "add_feature",
                        [
                            "name": "Hole", "type": "cylinder", "radius": "hole_d / 2", "height": "t",
                            "placement": ["translation": ["x": "width / 2", "y": "depth / 2"]],
                            "operation": "cut", "body": "Body1",
                        ])
                ], stopReason: .toolUse),
            LLMResponse(content: "Built a 60×40×10 mm plate with a 5.5 mm hole.", toolCalls: nil, stopReason: .endTurn),
        ])
        let assistant = Assistant(
            provider: provider, tools: CADTools.all(session: session),
            contextProvider: { session.assistantContext() }, configuration: CADAssistantPrompt.configuration)

        try await assistant.send("Make a 60 by 40 by 10 plate with a 5.5 mm hole in the middle.")

        let requests = await provider.requests
        #expect(requests.count == 4)
        #expect(requests.allSatisfy { $0.systemPrompt == CADAssistantPrompt.system })
        #expect(requests[0].history.first?.context?.contains("parameters: none\npart Plate\n  (no features)") == true)
        let results = requests[3].history.filter { $0.role == .toolResult }.map(\.content)
        #expect(results.count == 6)
        #expect(results.allSatisfy { $0.hasPrefix("Success: ") })
        #expect(results[5].contains("Hole: ok"))
        #expect(
            commits == [
                "Add Parameter width", "Add Parameter depth", "Add Parameter t", "Add Parameter hole_d", "Add Plate",
                "Add Hole",
            ])
        #expect(assistant.messages.last?.content == "Built a 60×40×10 mm plate with a 5.5 mm hole.")

        let body = try #require(session.result?.bodies.first)
        #expect(session.result?.bodies.count == 1)
        #expect(body.metrics?.isValid == true && body.metrics?.isClosed == true && body.metrics?.solidCount == 1)
        #expect(abs((body.metrics?.volume ?? 0) - (24000 - Double.pi * 2.75 * 2.75 * 10)) < 0.01)
        #expect(
            session.currentListing().contains(
                "Hole  cylinder r=(hole_d / 2) h=t at (width / 2, depth / 2, 0), cut Body1 → Body1  ok"))
    }

    @Test("A refused call reaches the model as an error and the next turn can correct it")
    func refusedCallIsReported() async throws {
        let session = CADSession(document: CADDocument(parts: [Part(name: "P")]), kernel: FakeKernel())
        let provider = ScriptedProvider([
            LLMResponse(
                content: nil, toolCalls: [call("1", "add_feature", ["type": "box", "width": 1])], stopReason: .toolUse),
            LLMResponse(
                content: nil,
                toolCalls: [call("2", "add_feature", ["type": "box", "width": 1, "depth": 1, "height": 1])],
                stopReason: .toolUse),
            LLMResponse(content: "Done.", toolCalls: nil, stopReason: .endTurn),
        ])
        let assistant = Assistant(
            provider: provider, tools: CADTools.all(session: session),
            contextProvider: { session.assistantContext() }, configuration: CADAssistantPrompt.configuration)

        try await assistant.send("A cube please")

        let results = await provider.requests[2].history.filter { $0.role == .toolResult }.map(\.content)
        #expect(results.count == 2)
        #expect(results.first == "Error: A box needs 'depth'.")
        #expect(results.last?.hasPrefix("Success: Added Box1 to part P") == true)
        #expect(session.document.parts[0].features.map(\.name) == ["Box1"])
    }
}
```

- [ ] **Step 2: Run to verify they fail** — expected: `CADAssistantPrompt` missing.

- [ ] **Step 3: Implement**

`Packages/CADAssistantTools/Sources/CADAssistantTools/CADAssistantPrompt.swift`:

```swift
import SwiftUIAssistant

public enum CADAssistantPrompt {
    /// The system prompt for a modelling assistant using `CADTools`. It has no `{context}` placeholder: the listing
    /// changes every turn, so it travels with each user message instead (`attachesContextToMessages`).
    public static let system = """
        You are the modelling assistant of a parametric CAD app. You build and change the user's model only through \
        the tools, never by describing code.

        ## The model
        - Lengths are millimetres and angles are degrees, in every tool and in the listing.
        - Parameters are named values. Any numeric field accepts a number or an expression over parameters, such as \
        "width / 2" or "(t + 1) * 2". Put dimensions the user may want to change into parameters.
        - A document has parts; each part has an ordered feature tree that is replayed on every change.
        - Features: solids (box, cylinder, sphere, cone, torus), boolean (union, subtract, intersect of bodies) and \
        transform (move or rotate a body).
        - A box has one corner at its placement origin and extends along +X (width), +Y (depth) and +Z (height). \
        Cylinders and cones stand on their placement origin along +Z; spheres and tori are centred on it.
        - A placement rotates by rotationDegrees about rotationAxis through the origin, then moves by translation.
        - A solid either creates a new body (operation newBody) or is joined, cut or intersected into an existing \
        body. The n-th body-creating feature of a part makes Body<n>. To drill a hole, add a cylinder with \
        operation cut into the plate's body.

        ## Working
        - The message you receive starts with the current listing in <context>: parameters with values, then each \
        feature with what it does, the body it creates or changes, and its status. Call get_listing when you need \
        it again mid-turn.
        - Every write tool returns the edited feature's status, status changes elsewhere, each body's validity, \
        volume and bounding box, and the changed listing lines. Read them after every write. If a feature failed, \
        was skipped or a body is not a valid closed solid, fix it before moving on.
        - A refused write changes nothing; its message says why. Correct the call and try again.
        - Prefer editing existing features over deleting and re-adding them. Name features after what they are \
        (Plate, MountingHole) so later requests can refer to them.
        - When you are done, tell the user briefly what you built or changed, with the key dimensions.
        """

    public static let configuration = AssistantConfiguration(
        systemPromptTemplate: system, maxToolExecutionRounds: 30, attachesContextToMessages: true)
}
```

- [ ] **Step 4: Run to verify they pass** — the plate volume is 24000 − π·2.75²·10 ≈ 23762.4 mm³.

- [ ] **Step 5: Commit** — `feat(tools): drive the assistant loop over the CAD tools`

### Task 8: App wiring

**Files:**
- Create: `3DModellerApp/Document/CADModelDocument+Session.swift`, `3DModellerAppTests/AssistantEditingTests.swift`
- Modify: `3DModellerApp/Views/ContentView.swift`, `project.yml`, `Package.swift`, regenerate `3DModellerApp.xcodeproj`

**Interfaces:**
- Consumes: `CADSession`, `CADTools.all(session:)`, `CADAssistantPrompt.configuration`.
- Produces: `CADModelDocument.connect(_ session: CADSession, undoManager: UndoManager?)` (`@MainActor`).

- [ ] **Step 1: Write the failing test**

`3DModellerAppTests/AssistantEditingTests.swift`:

```swift
import CADAssistantTools
import CADModel
import CADModelKernel
import Foundation
import Testing

@testable import _D_Modeller

@Suite("Assistant editing")
@MainActor
struct AssistantEditingTests {
    private func undoManager() -> UndoManager {
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        return undoManager
    }

    @Test("Each tool call is one undo step named after its action, and undo reaches the session")
    func toolEditsAreUndoable() async throws {
        let undoManager = undoManager()
        let document = CADModelDocument()
        let session = CADSession(document: document.model, kernel: OCCTGeometryKernel())
        document.connect(session, undoManager: undoManager)

        let added = try await AddFeatureTool(session: session).execute(arguments: [
            "type": "box", "width": 10, "depth": 10, "height": 10,
        ])
        let parameter = try await SetParameterTool(session: session).execute(arguments: ["name": "t", "expression": 2])

        #expect(added.success && parameter.success)
        #expect(document.model == session.document)
        #expect(undoManager.undoActionName == "Add Parameter t")

        undoManager.undo()
        #expect(undoManager.undoActionName == "Add Box1")
        undoManager.undo()
        #expect(document.model.parts[0].features.isEmpty)
        #expect(!undoManager.canUndo)

        await session.load(document.model)
        #expect(session.document == document.model)
        #expect(session.result?.bodies.isEmpty == true)
        #expect(session.currentListing().contains("(no features)"))
    }

    @Test("A refused tool call adds no undo step")
    func refusalAddsNoUndo() async throws {
        let undoManager = undoManager()
        let document = CADModelDocument()
        let session = CADSession(document: document.model, kernel: OCCTGeometryKernel())
        document.connect(session, undoManager: undoManager)

        let result = try await AddFeatureTool(session: session).execute(arguments: ["type": "box", "width": 10])

        #expect(!result.success)
        #expect(!undoManager.canUndo)
        #expect(document.model == session.document)
        #expect(document.model.parts[0].features.isEmpty)
    }
}
```

- [ ] **Step 2: Implement**

`3DModellerApp/Document/CADModelDocument+Session.swift`:

```swift
import CADAssistantTools
import Foundation

extension CADModelDocument {
    /// Routes the session's edits through `edit`, so each assistant tool call is one named step on the window's
    /// undo stack, shared with the menus.
    @MainActor
    func connect(_ session: CADSession, undoManager: UndoManager?) {
        session.onCommit = { [weak self] model, actionName in
            self?.edit(actionName, undoManager: undoManager) { $0 = model }
        }
    }
}
```

````diff
diff --git a/3DModellerApp/Views/ContentView.swift b/3DModellerApp/Views/ContentView.swift
index a691522..855e375 100644
--- a/3DModellerApp/Views/ContentView.swift
+++ b/3DModellerApp/Views/ContentView.swift
@@ -1,41 +1,44 @@
+import CADAssistantTools
 import CADModel
 import CADModelKernel
 import SwiftUI
 import SwiftUIAssistant
-import SwiftUIAssistantTools
 
 @MainActor
 struct ContentView: View {
     @ObservedObject var document: CADModelDocument
     @EnvironmentObject private var appModel: AppModel
     @Environment(\.undoManager) private var undoManager
-    @State private var result: RebuildResult?
+    @State private var session: CADSession
     @State private var selection: UUID?
     @State private var assistant: Assistant?
 
-    private static let engine = RebuildEngine(kernel: OCCTGeometryKernel())
+    init(document: CADModelDocument) {
+        _document = ObservedObject(wrappedValue: document)
+        _session = State(wrappedValue: CADSession(document: document.model, kernel: OCCTGeometryKernel()))
+    }
 
     var body: some View {
         NavigationSplitView {
             FeatureOutlineView(
                 model: document.model,
-                result: result,
+                result: session.result,
                 selection: $selection,
                 setSuppressed: setSuppressed,
                 delete: delete
             )
             .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
         } detail: {
-            Viewport3DView(result: result)
+            Viewport3DView(result: session.result)
                 .overlay(alignment: .bottom) {
-                    ModelStatisticsView(result: result)
+                    ModelStatisticsView(result: session.result)
                         .padding()
                 }
         }
         .inspector(isPresented: $appModel.showInspector) {
             InspectorView(
                 feature: selection.flatMap(document.model.feature(id:)),
-                featureResult: selection.flatMap { result?.feature(id: $0) },
+                featureResult: selection.flatMap { session.result?.feature(id: $0) },
                 assistant: assistant
             )
             .inspectorColumnWidth(min: 280, ideal: 340, max: 500)
@@ -58,9 +61,10 @@ struct ContentView: View {
             setupAssistant()
         }
         .task(id: document.model) {
-            if let rebuilt = try? await Self.engine.rebuild(document.model), !Task.isCancelled {
-                result = rebuilt
-            }
+            await session.load(document.model)
+        }
+        .onChange(of: undoManager, initial: true) { _, undoManager in
+            document.connect(session, undoManager: undoManager)
         }
     }
 
@@ -84,26 +88,11 @@ struct ContentView: View {
     private func setupAssistant() {
         guard !appModel.llmApiKey.isEmpty else { return }
 
-        let systemPrompt = """
-            You are the assistant of a parametric CAD app. Models are measured in millimetres.
-            You cannot read or change the model yet; modelling tools arrive in a later release.
-            If asked to model something, say so briefly and describe how you would build it
-            from boxes, cylinders, spheres, cones and tori combined with booleans.
-
-            You can:
-            - Fetch data from URLs (GET, POST, PUT, PATCH, DELETE)
-            - Perform calculations (arithmetic, trigonometry, logarithms)
-            - Work with dates and times (parse, format, calculate differences)
-
-            ## Current Context
-            {context}
-            """
-
         assistant = Assistant(
             provider: ClaudeProvider(apiKey: appModel.llmApiKey),
-            tools: [FetchTool(), CalculatorTool(), TimeTool()],
-            contextProvider: { EmptyContext() },
-            configuration: AssistantConfiguration(systemPromptTemplate: systemPrompt)
+            tools: CADTools.all(session: session),
+            contextProvider: { [session] in session.assistantContext() },
+            configuration: CADAssistantPrompt.configuration
         )
     }
 }
diff --git a/Package.swift b/Package.swift
index 640be9d..6dea148 100644
--- a/Package.swift
+++ b/Package.swift
@@ -16,17 +16,17 @@ let package = Package(
     ],
     dependencies: [
         .package(path: "Packages/SwiftUIAssistant"),
-        .package(path: "Packages/SwiftUIAssistantTools"),
         .package(path: "Packages/CADModel"),
+        .package(path: "Packages/CADAssistantTools"),
     ],
     targets: [
         .executableTarget(
             name: "3DModellerApp",
             dependencies: [
                 "SwiftUIAssistant",
-                "SwiftUIAssistantTools",
                 .product(name: "CADModel", package: "CADModel"),
                 .product(name: "CADModelKernel", package: "CADModel"),
+                .product(name: "CADAssistantTools", package: "CADAssistantTools"),
             ],
             path: "3DModellerApp"
         )
diff --git a/project.yml b/project.yml
index ac10361..81a1602 100644
--- a/project.yml
+++ b/project.yml
@@ -9,10 +9,10 @@ options:
 packages:
   SwiftUIAssistant:
     path: Packages/SwiftUIAssistant
-  SwiftUIAssistantTools:
-    path: Packages/SwiftUIAssistantTools
   CADModel:
     path: Packages/CADModel
+  CADAssistantTools:
+    path: Packages/CADAssistantTools
 
 targets:
   3DModellerApp:
@@ -47,12 +47,12 @@ targets:
     dependencies:
       - package: SwiftUIAssistant
         product: SwiftUIAssistant
-      - package: SwiftUIAssistantTools
-        product: SwiftUIAssistantTools
       - package: CADModel
         product: CADModel
       - package: CADModel
         product: CADModelKernel
+      - package: CADAssistantTools
+        product: CADAssistantTools
     info:
       path: 3DModellerApp/Info.plist
       properties:
````

- [ ] **Step 3: Regenerate and test** — `xcodegen generate`, then
`xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp -destination 'platform=macOS' -derivedDataPath <scratch>/dd CODE_SIGNING_ALLOWED=NO test > <scratch>/app.log 2>&1; tail -3 <scratch>/app.log`. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit** — `feat(app): let the assistant edit the model with undoable tools`

### Task 9: Documentation and the verify skill

**Files:** `CLAUDE.md`, `README.md`, `.claude/skills/verify/SKILL.md`

````diff
diff --git a/.claude/skills/verify/SKILL.md b/.claude/skills/verify/SKILL.md
index bd217e3..cc31a5a 100644
--- a/.claude/skills/verify/SKILL.md
+++ b/.claude/skills/verify/SKILL.md
@@ -35,7 +35,8 @@ Bundle id: `com.example.3dmodeller`. Open a hand-written `.cadmodel` rather than
 - **Status bar (bottom):** bodies, triangles, and failed features when any.
 - **Edits without an API key:** right-click a feature → Suppress/Unsuppress or Delete. Each is one undo step; Edit ▸ Undo shows its name (`Undo Suppress BadCone`).
 - **Save:** ⌘S or autosave rewrites the file with sorted keys and generated ids; read it back with `python3 -m json.tool`.
-- The assistant panel needs an API key and has only the fetch, calculator and time tools until the CAD tools land.
+- **Assistant (needs an API key in Settings):** ask e.g. "add a pin named Pin, a cylinder r=2 h=5 standing on the plate at x=10, y=10, joined to the plate". Each tool call shows in the panel; the outline and viewport update after each write; Edit ▸ Undo names the tool action (`Undo Add Pin`, `Undo Set Parameter t`), one step per call. The tool results (expand a call in the panel) list statuses, bodies with volume and bounds, and changed listing lines. Refused calls show `Error: …` and leave the model unchanged.
+- **Without an API key** the tools are covered headlessly by `cd Packages/CADAssistantTools && xcrun swift test` (fake kernel, OCCT integration and a scripted assistant loop).
 
 ## Gotchas
 
diff --git a/CLAUDE.md b/CLAUDE.md
index f248a24..746b544 100644
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -39,6 +39,7 @@ cd Packages/SwiftUIAssistant && xcrun swift test
 cd Packages/SwiftUIAssistantTools && xcrun swift test
 cd Packages/CADKernel && xcrun swift test
 cd Packages/CADModel && xcrun swift test
+cd Packages/CADAssistantTools && xcrun swift test
 
 # Run a single test
 xcrun swift test --filter SwiftUIAssistantTests.AssistantTests/testSendMessage
@@ -48,7 +49,7 @@ Always use `xcrun swift`, not bare `swift`: the `swift` on `$PATH` may be a tool
 
 ## Architecture
 
-This is an AI-first parametric CAD app for macOS. A document holds parameters and parts with feature trees; a rebuild engine replays the features through the Open CASCADE kernel. The chat assistant will edit documents through typed tools (next layer; see `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md`).
+This is an AI-first parametric CAD app for macOS. A document holds parameters and parts with feature trees; a rebuild engine replays the features through the Open CASCADE kernel. The chat assistant reads a text listing of the document and edits it through typed tools (see `docs/superpowers/specs/2026-09-26-cad-roadmap-design.md`).
 
 ### Package Structure
 
@@ -57,7 +58,8 @@ This is an AI-first parametric CAD app for macOS. A document holds parameters an
 - `LLMProvider` protocol - Abstraction for AI backends (Claude implemented; `ClaudeProvider` defaults to `claude-opus-5-5`, effort `medium`)
 - `AssistantTool` protocol - Define executable tools the AI can invoke
 - `Assistant` class - Orchestrates LLM calls and tool execution loops
-- `AssistantContext` protocol - Host app provides scene state to AI
+- `AssistantContext` protocol - Host app provides scene state to AI. With `AssistantConfiguration.attachesContextToMessages` the context travels with each user message (`Message.context`) instead of the system prompt, which stays fixed per conversation
+- `ToolParameter.custom` - a parameter with its own JSON Schema (unions, nested objects, arrays)
 - SwiftUI views: `AssistantPanel`, `AssistantView`, `MessageBubbleView`, etc.
 
 **SwiftUIAssistantTools** (`Packages/SwiftUIAssistantTools/`) - Common `AssistantTool`s: `FetchTool`, `CalculatorTool`, `TimeTool`
@@ -71,26 +73,36 @@ This is an AI-first parametric CAD app for macOS. A document holds parameters an
 - `Feature` - `{id, name, suppressed, kind}`; kinds: box/cylinder/sphere/cone/torus (with `Placement` in degrees and a `SolidOperation`: newBody, join/cut/intersect into a named body), boolean, transform. The n-th newBody feature in a part owns `Body<n>`
 - `GeometryKernel` protocol and `RebuildEngine` - replays features off the main actor (`@concurrent`, cancellable) into an immutable `RebuildResult`: per-feature `FeatureStatus` (ok / failed / skipped(dependsOn) / suppressed), bodies with `BodyMetrics` and `BodyMesh`, evaluated parameters. A failure never aborts the rebuild
 - `CADModelKernel` target - `OCCTGeometryKernel`, the adapter to CADKernel (degrees → radians happen here). `CADModelTests` use a fake kernel; `CADModelKernelTests` use the real one
+- `Part.createdBodies()` / `affectedBodies()` and `FeatureKind.bodyReferences` / `renameBodyReferences` - body naming shared by the rebuild and the tools
+
+**CADAssistantTools** (`Packages/CADAssistantTools/`) - Headless agent surface over CADModel (no UI, no OCCT import):
+
+- `CADSession` - `@MainActor @Observable`; owns a `CADDocument`, a rebuild engine for any `GeometryKernel` and the latest `RebuildResult`. `apply(_:actionName:)` commits an edit (calls `onCommit`, then rebuilds); `load(_:)` adopts a document changed elsewhere; a rebuild of an older document never replaces a newer result
+- `DocumentListing` - the compact text listing (parameters with values; per part, one line per feature: name, summary with expressions, → body, status). `CADSession.assistantContext()` returns it as `ListingContext`, readable from any isolation
+- Tools (`CADTools.all(session:)`): `get_listing`, `set_parameter`, `add_feature`, `edit_feature`, `delete_feature`, `rename_feature`, `suppress_feature`. Every write is one commit: it is validated first (unknown names, duplicates, bad arguments, and any expression that would newly fail are refused with nothing changed), body references are renumbered when body-creating features move, and the result reports the feature's status, status changes elsewhere, every body's validity/volume/bounds and the changed listing lines
+- `CADAssistantPrompt.system` / `.configuration` - the modelling system prompt (mm, degrees, check statuses after each write) with per-message context
+- Tests use a fake kernel, plus `OCCTGeometryKernel` for integration and a scripted `LLMProvider` driving the `Assistant` loop
 
 **3DModellerApp** - The main application:
 
 - `CADModelDocument` - `ReferenceFileDocument` for `.cadmodel` files holding a `CADDocument` value; `edit(_:undoManager:_:)` registers the previous value on the window's `UndoManager` (Edit ▸ Undo, ⌘Z)
-- `ContentView` - rebuilds with `.task(id: document.model)`, so each edit cancels the previous rebuild
+- `ContentView` - owns a `CADSession`; `.task(id: document.model)` calls `session.load`, so each edit cancels the previous rebuild. `CADModelDocument.connect(_:undoManager:)` routes session commits through `edit`, one named undo step per tool call
 - `FeatureOutlineView` (parameters, parts → features with status icons; context menu Suppress/Delete), `FeatureInspectorView` (read-only), `ModelStatisticsView`
 - `Viewport3DView` + `ViewportScene` - draws the result's meshes; `ViewportFrame` converts model millimetres, Z-up, to RealityKit metres, Y-up
-- Assistant tools: only the generic `FetchTool`, `CalculatorTool`, `TimeTool` until the CAD tools land
+- Assistant: `CADTools.all(session:)` with the listing as per-message context (`CADAssistantPrompt.configuration`); the generic SwiftUIAssistantTools are no longer registered
 
 ### Key Data Flow
 
 1. The document opens → `CADModelDocument` decodes `CADDocument`
-2. `ContentView` runs `RebuildEngine.rebuild` off the main actor → `RebuildResult`
-3. The outline, inspector, status bar and viewport read the result
-4. An edit (`CADModelDocument.edit`) changes the value and registers undo → the rebuild task restarts
-5. The assistant loop (`Assistant.send()` → `LLMProvider` → `AssistantTool.execute()`) runs beside it, currently with generic tools only
+2. `ContentView` loads it into its `CADSession`, which rebuilds off the main actor → `RebuildResult`
+3. The outline, inspector, status bar and viewport read `session.result`
+4. A UI edit (`CADModelDocument.edit`) changes the value and registers undo → the task calls `session.load` → rebuild
+5. The assistant (`Assistant.send()` → `LLMProvider` → CAD tool) edits through `CADSession.apply` → `onCommit` → `CADModelDocument.edit` (undo step) → rebuild; the tool result reports statuses, bodies and listing changes
 
 ### Important Patterns
 
-- The document is a value; every edit goes through `CADModelDocument.edit` with an action name
+- The document is a value; every edit goes through `CADModelDocument.edit` with an action name, including assistant edits (via `CADSession.onCommit`)
+- Body names are ordinal (`Body<n>` = n-th newBody feature). Tool edits that add, delete or change a body-creating feature renumber later references to keep them on the same creating feature, and refuse the edit if a used body would disappear
 - Claude Opus 5.5 always thinks, and its thinking blocks must go back to the API unchanged. `ClaudeProvider` keeps each response's content blocks in `Message.rawContent` and replays them verbatim. Never rebuild or edit an assistant turn that has `rawContent`
 - Only `CADKernel` imports OCCTSwift; every OCCT call runs inside `OCCTSerial.withLock {}`
 
diff --git a/README.md b/README.md
index 955df59..1b69923 100644
--- a/README.md
+++ b/README.md
@@ -1,6 +1,6 @@
 # 3D Modeller
 
-An AI-first parametric CAD application for macOS. A model is a list of parameters and features that the app rebuilds with the Open CASCADE kernel; a chat assistant will build and change models through typed tools.
+An AI-first parametric CAD application for macOS. A model is a list of parameters and features that the app rebuilds with the Open CASCADE kernel; a chat assistant builds and changes models through typed tools.
 
 ## Features
 
@@ -10,7 +10,7 @@ An AI-first parametric CAD application for macOS. A model is a list of parameter
 - **Robust rebuild** - Each feature reports ok, failed (with the reason), skipped (with the feature it depends on) or suppressed; one failure never stops the rest
 - **Exact CAD geometry** - Solids built by the Open CASCADE kernel and drawn in a RealityKit viewport
 - **Undo/Redo** - Document edits go through the window's undo history (Edit ▸ Undo, ⌘Z)
-- **AI assistant** - Chat panel backed by Claude; modelling tools arrive in the next release
+- **AI assistant** - Chat panel backed by Claude that reads a text listing of the model and edits it through typed tools (parameters, add/edit/delete/rename/suppress features); each tool call is one undo step
 
 ## Requirements
 
@@ -53,6 +53,7 @@ xcodebuild -project 3DModellerApp.xcodeproj -scheme 3DModellerApp test
 (cd Packages/SwiftUIAssistantTools && xcrun swift test)
 (cd Packages/CADKernel && xcrun swift test)
 (cd Packages/CADModel && xcrun swift test)
+(cd Packages/CADAssistantTools && xcrun swift test)
 ```
 
 ### Configure API Key
@@ -90,7 +91,7 @@ Open or create a `.cadmodel` document. A small example, a plate with a hole:
 }
 ```
 
-The outline lists parameters and features with their rebuild status; select a feature to see its values in the inspector. Right-click a feature to suppress or delete it. Until the CAD tools land, the assistant can only use the general-purpose `fetch`, `calculator` and `time` tools.
+The outline lists parameters and features with their rebuild status; select a feature to see its values in the inspector. Right-click a feature to suppress or delete it. With an API key in Settings, ask the assistant to build or change the model ("a 60 × 40 × 10 plate with a 5.5 mm hole in the middle"); every change it makes appears in the outline and can be undone with ⌘Z.
 
 ## Architecture
 
@@ -99,8 +100,9 @@ The outline lists parameters and features with their rebuild status; select a fe
 │   ├── SwiftUIAssistant/      # Reusable AI assistant library
 │   ├── SwiftUIAssistantTools/ # Common tools (fetch, calculator, time)
 │   ├── CADKernel/             # Open CASCADE geometry (the only OCCT importer)
-│   └── CADModel/              # Document, parameters, features, rebuild engine
-│                              # (+ CADModelKernel: the CADKernel adapter)
+│   ├── CADModel/              # Document, parameters, features, rebuild engine
+│   │                          # (+ CADModelKernel: the CADKernel adapter)
+│   └── CADAssistantTools/     # Headless session, listing and CAD tools for the assistant
 │
 └── 3DModellerApp/             # Main application
     ├── App/                   # Entry point, global state
@@ -121,7 +123,11 @@ A standalone Swift package that can be reused to add AI assistant capabilities t
 
 ### SwiftUIAssistantTools
 
-Ready-made `AssistantTool`s any host app can register: `FetchTool`, `CalculatorTool`, `TimeTool`.
+Ready-made `AssistantTool`s any host app can register: `FetchTool`, `CalculatorTool`, `TimeTool`. The CAD app no longer registers them.
+
+### CADAssistantTools
+
+The agent-facing surface, usable without the app: a `CADSession` that owns a document and its rebuild, the text listing the assistant sees each turn, and the tools `get_listing`, `set_parameter`, `add_feature`, `edit_feature`, `delete_feature`, `rename_feature` and `suppress_feature`.
 
 ### Technology Stack
 
````

- [ ] **Commit** — `docs: describe the CAD assistant tools`

### Task 10: Final review (no commit unless fixes)

- [ ] Run every package's tests and the app tests; record counts.
- [ ] Whole-branch review by a fresh `opus` reviewer over `git merge-base cad/02-document-model HEAD..HEAD`; one fix pass for Critical/Important findings.
- [ ] Runtime verification in the app needs an API key; skipped unless one is configured (say so in the report).
