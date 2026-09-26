import Foundation

/// An image a tool returns to the model, such as a rendered view.
public struct ToolImage: Sendable, Equatable {
    public let mediaType: String
    public let data: Data
    /// Text sent right before the image, saying what it shows.
    public let caption: String?

    public init(mediaType: String = "image/png", data: Data, caption: String? = nil) {
        self.mediaType = mediaType
        self.data = data
        self.caption = caption
    }
}
