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
