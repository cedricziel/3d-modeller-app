import Foundation
import SwiftUIAssistant

public enum CADSkills {
    /// The skills bundled with the tools. They ship with the app, so a broken one is a bug the tests catch.
    public static let library: SkillLibrary = {
        guard let directory = Bundle.module.url(forResource: "Skills", withExtension: nil) else {
            fatalError("The bundled skills folder is missing.")
        }
        do {
            return try SkillLibrary(directory: directory)
        } catch {
            fatalError("A bundled skill is broken: \(error)")
        }
    }()
}
