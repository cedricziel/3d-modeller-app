import SwiftUIAssistant

public enum CADTools {
    /// Every CAD tool, operating on `session`.
    public static func all(session: CADSession) -> [any AssistantTool] {
        [
            GetListingTool(session: session),
            FindGeometryTool(session: session),
            MeasureTool(session: session),
            RenderViewsTool(session: session),
            SetParameterTool(session: session),
            AddFeatureTool(session: session),
            EditFeatureTool(session: session),
            DeleteFeatureTool(session: session),
            RenameFeatureTool(session: session),
            SuppressFeatureTool(session: session),
            AddSketchTool(session: session),
            EditSketchTool(session: session),
            GetSketchTool(session: session),
            AddPartTool(session: session),
            RenamePartTool(session: session),
            DeletePartTool(session: session),
            AddInstanceTool(session: session),
            EditInstanceTool(session: session),
            DeleteInstanceTool(session: session),
        ]
    }
}
