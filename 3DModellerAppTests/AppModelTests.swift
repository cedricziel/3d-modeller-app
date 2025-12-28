import Testing
import Combine
@testable import _D_Modeller

@Suite("AppModel Tests")
@MainActor
struct AppModelTests {

    // MARK: - Initial State Tests

    @Test
    func testInitialShowAssistantIsTrue() {
        let appModel = AppModel()
        #expect(appModel.showAssistant == true)
    }

    @Test
    func testInitialSelectedToolIsSelect() {
        let appModel = AppModel()
        #expect(appModel.selectedTool == .select)
    }

    // MARK: - Toggle Tests

    @Test
    func testToggleShowAssistant() {
        let appModel = AppModel()
        #expect(appModel.showAssistant == true)

        appModel.showAssistant.toggle()
        #expect(appModel.showAssistant == false)

        appModel.showAssistant.toggle()
        #expect(appModel.showAssistant == true)
    }

    @Test
    func testSetShowAssistantDirectly() {
        let appModel = AppModel()

        appModel.showAssistant = false
        #expect(appModel.showAssistant == false)

        appModel.showAssistant = true
        #expect(appModel.showAssistant == true)
    }

    // MARK: - Published Property Tests

    @Test
    func testShowAssistantPublishesChanges() {
        let appModel = AppModel()
        var receivedValues: [Bool] = []

        let cancellable = appModel.$showAssistant.sink { value in
            receivedValues.append(value)
        }

        appModel.showAssistant = false
        appModel.showAssistant = true

        // Initial value + 2 changes = 3 values
        #expect(receivedValues == [true, false, true])

        cancellable.cancel()
    }

    @Test
    func testSelectedToolPublishesChanges() {
        let appModel = AppModel()
        var receivedValues: [AppModel.EditingTool] = []

        let cancellable = appModel.$selectedTool.sink { value in
            receivedValues.append(value)
        }

        appModel.selectedTool = .move
        appModel.selectedTool = .rotate
        appModel.selectedTool = .scale

        #expect(receivedValues == [.select, .move, .rotate, .scale])

        cancellable.cancel()
    }

    // MARK: - Editing Tool Tests

    @Test
    func testEditingToolAllCases() {
        let allCases = AppModel.EditingTool.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.select))
        #expect(allCases.contains(.move))
        #expect(allCases.contains(.rotate))
        #expect(allCases.contains(.scale))
    }

    @Test
    func testEditingToolIcons() {
        #expect(AppModel.EditingTool.select.icon == "arrow.up.left.and.arrow.down.right")
        #expect(AppModel.EditingTool.move.icon == "arrow.up.and.down.and.arrow.left.and.right")
        #expect(AppModel.EditingTool.rotate.icon == "arrow.triangle.2.circlepath")
        #expect(AppModel.EditingTool.scale.icon == "arrow.up.left.and.arrow.down.right.circle")
    }

    @Test
    func testEditingToolLabels() {
        #expect(AppModel.EditingTool.select.label == "Select")
        #expect(AppModel.EditingTool.move.label == "Move")
        #expect(AppModel.EditingTool.rotate.label == "Rotate")
        #expect(AppModel.EditingTool.scale.label == "Scale")
    }

    @Test
    func testEditingToolShortcuts() {
        #expect(AppModel.EditingTool.select.shortcut == "Q")
        #expect(AppModel.EditingTool.move.shortcut == "W")
        #expect(AppModel.EditingTool.rotate.shortcut == "E")
        #expect(AppModel.EditingTool.scale.shortcut == "R")
    }

    @Test
    func testEditingToolIdentifiable() {
        let tool = AppModel.EditingTool.move
        #expect(tool.id == "move")
    }
}
