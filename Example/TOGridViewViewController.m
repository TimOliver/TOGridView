//
//  TOGridViewViewController.m
//  TOGridView
//
//  Created by Tim Oliver on 14/01/13.
//  Copyright 2013 Timothy Oliver. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "TOGridViewViewController.h"
#import "UIDevice+ScreenIdioms.h"
#import "TOGridViewTestCell.h"

@interface TOGridViewViewController()

- (void)editButtonTapped: (id)sender;
- (void)addButtonTapped: (id)sender;

@end

@implementation TOGridViewViewController

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle
- (void)loadView
{
    UIView *view = [[UIView alloc] initWithFrame: [[UIScreen mainScreen] applicationFrame] ];
    view.backgroundColor = [UIColor blackColor];
    
    self.view = view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _numbers = [NSMutableArray new];
    for( NSInteger i=0; i < 1024; i++ )
        [_numbers addObject: [NSNumber numberWithInt:i]];
    
	_gridView = [[TOGridView alloc] initWithFrame: self.view.bounds withCellClass: [TOGridViewTestCell class]];
    _gridView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _gridView.delegate = self;
    _gridView.dataSource = self;
    [self.view addSubview: _gridView]; 
     
    _gridView.backgroundColor = [UIColor colorWithWhite: 0.93f alpha:1.0f];
    //_gridView.backgroundColor = [UIColor blackColor];
    
    UIView *headerView = [[UIView alloc] initWithFrame: CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 150)];
    headerView.backgroundColor = [UIColor colorWithWhite:0.87f alpha:1.0f];
    _gridView.headerView = headerView;
    
    //Add a label to the header view
    UILabel *testLabel = [[UILabel alloc] initWithFrame: CGRectMake(0,0,150,44)];
    testLabel.text = @"Header View";
    testLabel.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    testLabel.font = [UIFont boldSystemFontOfSize: 18.0f];
    testLabel.backgroundColor = [UIColor clearColor];
    testLabel.textColor = [UIColor colorWithWhite: 0.2f alpha: 1.0f];
    testLabel.shadowColor = [UIColor whiteColor];
    testLabel.shadowOffset = CGSizeMake( 0.0f, 1.0f );
    testLabel.textAlignment = UITextAlignmentCenter;
    [_gridView.headerView addSubview: testLabel];
    testLabel.center = _gridView.headerView.center;
    
    //add a slight bevel to the bototm of the header
    UIView *headerBevel = [[UIView alloc] initWithFrame: CGRectMake(0, _gridView.headerView.frame.size.height-1.0f, _gridView.headerView.frame.size.width, 1.0f)];
    headerBevel.backgroundColor = [UIColor colorWithWhite: 0.8f alpha: 1.0f];
    headerBevel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [_gridView.headerView addSubview: headerBevel];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle: @"Add" style: UIBarButtonItemStylePlain target: self action: @selector(addButtonTapped:)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle: @"Edit" style: UIBarButtonItemStylePlain target: self action: @selector(editButtonTapped:)];
    self.navigationController.navigationBar.tintColor = [UIColor colorWithWhite:0.1f alpha:1.0f];
    
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if( interfaceOrientation == UIInterfaceOrientationPortrait )
        return YES;
    
    return YES;
}

#pragma mark -
#pragma mark Delegate
- (CGSize)innerPaddingForGridView:(TOGridView *)gridView
{
    return CGSizeMake(-1.0f, 0.0f);
}

- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView
{
    if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return CGSizeMake(100, 100);
        else
            return CGSizeMake(100, 100);
    }
    else
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return CGSizeMake(322, 70);
        else
        {
            if( UI_USER_INTERFACE_SCREEN_IDIOM() == UIUserInterfaceScreenIdiomPhone4Inch )
                return CGSizeMake(285, 70);
            else
                return CGSizeMake(481, 70);
        }
    }
}

- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView
{
    if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return 7;
        else
            return 10;
    }
    else
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return 1;
        else
        {
            if( UI_USER_INTERFACE_SCREEN_IDIOM() == UIUserInterfaceScreenIdiomPhone4Inch )
                return 2;
            else
                return 1;
        }
    }
}

- (NSUInteger)heightOfRowsInGridView:(TOGridView *)gridView
{
    if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
        return 100;
    
    return 70;
}

- (void)gridView:(TOGridView *)gridView didTapCellAtIndex:(NSUInteger)index
{
    [gridView unhighlightCellAtIndex: index animated: YES];
    NSLog( @"Cell %d tapped!", index );
}

- (void)gridView:(TOGridView *)gridView didLongTapCellAtIndex:(NSInteger)index
{
    [gridView unhighlightCellAtIndex: index animated: YES];
    NSLog( @"Cell %d long tapped!", index );
}

- (void)gridView: (TOGridView *)gridView didMoveCellAtIndex:(NSInteger)prevIndex toIndex:(NSInteger)newIndex
{
    //reshuffle the numbers in the data source to match the new order
    NSNumber *number = [_numbers objectAtIndex: prevIndex];
    [_numbers removeObject: number];
    [_numbers insertObject: number atIndex: newIndex];
}

#pragma mark -
#pragma mark Data Source
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView
{
    return [_numbers count];
}

- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)cellIndex
{
    TOGridViewTestCell *cell = (TOGridViewTestCell *)[_gridView dequeReusableCell];
    
    //NSInteger cellNum = [[_numbers objectAtIndex: cellIndex] intValue];
    cell.textLabel.text = @"Test cell";//[NSString stringWithFormat: @"Cell %d", cellNum];
    
    return cell;
}

- (BOOL)gridView:(TOGridView *)gridView canMoveCellAtIndex:(NSInteger)cellIndex
{
    return YES;
}

#pragma mark -
#pragma mark Button Callbacks
- (void)addButtonTapped:(id)sender
{
    if( _gridView.editing == NO )
    {
        NSNumber *newNumber = [NSNumber numberWithInteger: 0];
        [_numbers insertObject: newNumber atIndex: 0];
        [_gridView insertCellAtIndex: 0 animated: YES];
    }
    else
    {
        NSArray *selectedCellIndices = [_gridView indicesOfSelectedCells];
        
        NSMutableArray *numbersToDelete = [NSMutableArray array];
        for( NSNumber *indexToDelete in selectedCellIndices )
            [numbersToDelete addObject: [_numbers objectAtIndex: [indexToDelete integerValue]]];
        
        //remove the entries from the data source
        [_numbers removeObjectsInArray: numbersToDelete];
        //animate the cells leaving the grid view
        [_gridView deleteCellsAtIndices: selectedCellIndices animated: YES];
    }
}

-(void)editButtonTapped:(id)sender
{
    [_gridView setEditing: !_gridView.editing animated: YES];
    
    if( _gridView.editing )
    {
        self.navigationItem.rightBarButtonItem.title = @"Done";
        self.navigationItem.leftBarButtonItem.title = @"Delete";
    }
    else
    {
        self.navigationItem.rightBarButtonItem.title = @"Edit";
        self.navigationItem.leftBarButtonItem.title = @"Add";
    }
}

@end
