import XCTest
import UIKit

// Built in Swift 6 mode: UIKit callbacks must be compatible with main-actor state.
@MainActor
private final class SwiftGridProvider: NSObject, TOGridViewDataSource, TOGridViewDelegate {
    var count = 12

    func numberOfCells(in gridView: TOGridView) -> UInt { UInt(count) }
    func gridView(_ gridView: TOGridView, cellFor index: Int) -> TOGridViewCell {
        gridView.dequeueReusableCell()
    }
    func sizeOfCells(for gridView: TOGridView) -> CGSize { CGSize(width: 160, height: 80) }
    func numberOfCellsPerRow(for gridView: TOGridView) -> UInt { 2 }
}

@MainActor
final class SwiftAPICompatibilityTests: XCTestCase {
    func testTypedCollectionsOptionalsAndEnumImport() {
        let grid = TOGridView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), cellClass: nil)
        let provider = SwiftGridProvider()
        grid.dataSource = provider
        grid.delegate = provider
        grid.reloadGrid()

        let cells: [TOGridViewCell] = grid.visibleCellViews
        let selected: [NSNumber] = grid.indicesOfSelectedCells()
        let missing: TOGridViewCell? = grid.cell(for: 100)
        let decoration: UIView? = grid.dequeueReusableDecorationView()
        XCTAssertFalse(cells.isEmpty)
        XCTAssertTrue(selected.isEmpty)
        XCTAssertNil(missing)
        XCTAssertNil(decoration)

        grid.scrollToCell(at: 2, to: .top, animated: false, completed: nil)
        grid.headerView = nil
        grid.footerView = nil
        grid.backgroundView = nil
        grid.dataSource = nil
        grid.delegate = nil
    }
}
