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
