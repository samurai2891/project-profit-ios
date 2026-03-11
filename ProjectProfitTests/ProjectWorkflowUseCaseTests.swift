import SwiftData
import XCTest
@testable import ProjectProfit

@MainActor
final class ProjectWorkflowUseCaseTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var dataStore: ProjectProfit.DataStore!
    private var useCase: ProjectWorkflowUseCase!

    override func setUp() {
        super.setUp()
        container = try! TestModelContainer.create()
        context = ModelContext(container)
        dataStore = ProjectProfit.DataStore(modelContext: context)
        dataStore.loadData()
        useCase = ProjectWorkflowUseCase(modelContext: context)
    }

    override func tearDown() {
        useCase = nil
        dataStore = nil
        context = nil
        container = nil
        super.tearDown()
    }

    func testCreateProjectPersistsInputAndNormalizesInvalidPlannedEndDate() {
        let startDate = makeDate(year: 2026, month: 5, day: 20)
        let invalidPlannedEndDate = makeDate(year: 2026, month: 5, day: 10)

        let project = useCase.createProject(
            input: makeInput(
                name: "新規案件",
                description: "説明",
                startDate: startDate,
                plannedEndDate: invalidPlannedEndDate
            )
        )
        dataStore.loadData()

        XCTAssertEqual(project.name, "新規案件")
        XCTAssertEqual(project.projectDescription, "説明")
        XCTAssertEqual(project.startDate, startDate)
        XCTAssertNil(project.plannedEndDate)
        XCTAssertEqual(dataStore.projects.count, 1)
    }

    func testUpdateProjectPersistsEditableFieldsAndClearsInvalidCompletedAt() {
        let project = dataStore.addProject(name: "更新前", description: "old")
        let startDate = makeDate(year: 2026, month: 4, day: 20)
        let invalidCompletedAt = makeDate(year: 2026, month: 4, day: 10)

        useCase.updateProject(
            id: project.id,
            input: makeInput(
                name: "更新後",
                description: "new",
                status: .completed,
                startDate: startDate,
                completedAt: invalidCompletedAt,
                plannedEndDate: nil
            )
        )
        dataStore.loadData()

        let updated = try! XCTUnwrap(dataStore.getProject(id: project.id))
        XCTAssertEqual(updated.name, "更新後")
        XCTAssertEqual(updated.projectDescription, "new")
        XCTAssertEqual(updated.status, .completed)
        XCTAssertEqual(updated.startDate, startDate)
        XCTAssertNil(updated.completedAt)
    }

    func testDeleteProjectHardDeletesProjectWithoutHistoricalReferences() {
        let project = dataStore.addProject(name: "削除対象", description: "")

        useCase.deleteProject(id: project.id)
        dataStore.loadData()

        XCTAssertNil(dataStore.getProject(id: project.id))
        XCTAssertTrue(dataStore.projects.isEmpty)
    }

    func testDeleteProjectArchivesProjectWithHistoricalReferences() {
        let project = dataStore.addProject(name: "参照あり", description: "")
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        _ = dataStore.addTransaction(
            type: .expense,
            amount: 12_000,
            date: makeDate(year: 2026, month: 4, day: 1),
            categoryId: categoryId,
            memo: "archive fallback",
            allocations: [(projectId: project.id, ratio: 100)]
        )

        useCase.deleteProject(id: project.id)
        dataStore.loadData()

        let archived = try! XCTUnwrap(dataStore.getProject(id: project.id))
        XCTAssertEqual(archived.isArchived, true)
    }

    func testDeleteProjectsArchivesReferencedAndDeletesUnreferencedProjects() {
        let referenced = dataStore.addProject(name: "参照あり", description: "")
        let unreferenced = dataStore.addProject(name: "参照なし", description: "")
        let untouched = dataStore.addProject(name: "残す", description: "")
        let categoryId = try! XCTUnwrap(dataStore.activeCategories.first(where: { $0.type == .expense })?.id)
        _ = dataStore.addTransaction(
            type: .expense,
            amount: 8_000,
            date: makeDate(year: 2026, month: 4, day: 1),
            categoryId: categoryId,
            memo: "batch delete",
            allocations: [(projectId: referenced.id, ratio: 100)]
        )

        useCase.deleteProjects(ids: [referenced.id, unreferenced.id])
        dataStore.loadData()

        XCTAssertEqual(dataStore.getProject(id: referenced.id)?.isArchived, true)
        XCTAssertNil(dataStore.getProject(id: unreferenced.id))
        XCTAssertNotNil(dataStore.getProject(id: untouched.id))
    }

    private func makeInput(
        name: String = "案件",
        description: String = "",
        status: ProjectStatus = .active,
        startDate: Date? = nil,
        completedAt: Date? = nil,
        plannedEndDate: Date? = nil
    ) -> ProjectUpsertInput {
        ProjectUpsertInput(
            name: name,
            description: description,
            status: status,
            startDate: startDate,
            completedAt: completedAt,
            plannedEndDate: plannedEndDate
        )
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}
