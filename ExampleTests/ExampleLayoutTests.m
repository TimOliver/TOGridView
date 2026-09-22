#import <XCTest/XCTest.h>
#import "TOGridViewViewController.h"
#import "TOGridViewTestCell.h"

@interface ExampleLayoutTests : XCTestCase
@end

@implementation ExampleLayoutTests

- (void)testGridFitsPhoneAndResizableIPadWidths
{
    TOGridViewViewController *controller = [TOGridViewViewController new];
    [controller loadViewIfNeeded];
    TOGridView *grid = [controller valueForKey:@"gridView"];
    for (NSNumber *width in @[@320, @393, @600, @768, @1024, @1366]) {
        controller.view.frame = CGRectMake(0, 0, width.doubleValue, 900);
        [controller.view setNeedsLayout];
        [controller.view layoutIfNeeded];
        XCTAssertTrue(CGRectEqualToRect(grid.frame, controller.view.bounds));
        XCTAssertGreaterThanOrEqual(grid.numberOfCellsPerRow, 1);
        XCTAssertTrue(isfinite(grid.cellSize.width));
        XCTAssertGreaterThan(grid.cellSize.width, 0);
        XCTAssertGreaterThanOrEqual(grid.cellSize.height, 72);
        for (NSInteger index = 0; index < grid.numberOfCellsPerRow; index++) {
            CGRect frame = [grid rectOfCellAtIndex:index];
            XCTAssertTrue(isfinite(frame.origin.x));
            XCTAssertGreaterThanOrEqual(CGRectGetMinX(frame), 0);
            XCTAssertLessThanOrEqual(CGRectGetMaxX(frame), width.doubleValue);
        }
        CGRect last = [grid rectOfCellAtIndex:grid.numberOfCellsPerRow - 1];
        XCTAssertEqualWithAccuracy(CGRectGetMaxX(last), width.doubleValue, 0.01);
    }
}

- (void)testLargeTextIncreasesRowHeightAndReducesColumns
{
    UIViewController *parent = [UIViewController new];
    TOGridViewViewController *controller = [TOGridViewViewController new];
    [parent addChildViewController:controller];
    [parent.view addSubview:controller.view];
    [controller didMoveToParentViewController:parent];
    controller.view.frame = CGRectMake(0, 0, 1024, 900);
    [controller.view layoutIfNeeded];
    TOGridView *grid = [controller valueForKey:@"gridView"];
    CGFloat previousHeight = grid.cellSize.height;
    NSInteger previousColumns = grid.numberOfCellsPerRow;
    UITraitCollection *traits = [UITraitCollection traitCollectionWithPreferredContentSizeCategory:UIContentSizeCategoryAccessibilityExtraExtraExtraLarge];
    [parent setOverrideTraitCollection:traits forChildViewController:controller];
    [controller.view setNeedsLayout];
    [controller.view layoutIfNeeded];
    XCTAssertGreaterThan(grid.cellSize.height, previousHeight);
    XCTAssertLessThan(grid.numberOfCellsPerRow, previousColumns);
}

- (void)testSingleColumnSpacingIsZero
{
    TOGridViewViewController *controller = [TOGridViewViewController new];
    [controller loadViewIfNeeded];
    controller.view.frame = CGRectMake(0, 0, 320, 700);
    [controller.view layoutIfNeeded];
    TOGridView *grid = [controller valueForKey:@"gridView"];
    XCTAssertEqual(grid.numberOfCellsPerRow, 1);
    XCTAssertEqual([[grid valueForKey:@"widthBetweenCells"] integerValue], 0);
}

@end
