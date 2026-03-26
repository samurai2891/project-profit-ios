import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class DistributionTemplateManagementQueryUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!

    override func setUp() {
        super.setUp()
        FeatureFlags.clearOverrides()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
    }

    override func tearDown() {
        FeatureFlags.clearOverrides()
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testSnapshotMatchesCurrentBusinessIdAndProjectOrdering() throws {
        let queryUseCase = DistributionTemplateManagementQueryUseCase(modelContext: context)

        let zProject = PPProject(name: "Z案件")
        let aProject = PPProject(name: "A案件")
        let mProject = PPProject(name: "M案件")
        context.insert(zProject)
        context.insert(aProject)
        context.insert(mProject)
        try context.save()

        let snapshot = try queryUseCase.snapshot()

        XCTAssertEqual(snapshot.businessId, dataStore.businessProfile?.id)
        XCTAssertEqual(snapshot.sortedProjects.map(\.name).prefix(3), ["A案件", "M案件", "Z案件"])
    }

    func testProjectNameMatchesCurrentLookup() throws {
        let queryUseCase = DistributionTemplateManagementQueryUseCase(modelContext: context)
        let project = PPProject(name: "配賦先案件")
        context.insert(project)
        try context.save()

        let snapshot = try queryUseCase.snapshot()

        XCTAssertEqual(
            queryUseCase.projectName(id: project.id, snapshot: snapshot),
            "配賦先案件"
        )
        XCTAssertNil(queryUseCase.projectName(id: UUID(), snapshot: snapshot))
    }
}
