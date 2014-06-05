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

@interface TOGridViewViewController() <TOGridViewDataSource, TOGridViewDelegate>

@property (nonatomic, strong) TOGridView *gridView;
@property (nonatomic, strong) NSMutableArray *numbers;

- (void)editButtonTapped:(id)sender;
- (void)addButtonTapped:(id)sender;

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
    UIView *view = [[UIView alloc] initWithFrame:[[UIScreen mainScreen] applicationFrame]];
    view.backgroundColor = [UIColor blackColor];
    
    self.view = view;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    //disable translucency for benchmarking performance
    self.navigationController.navigationBar.translucent = NO;
    
    self.numbers = [NSMutableArray new];
    for (NSInteger i=0; i < 256; i++)
        [self.numbers addObject:[NSNumber numberWithInt:i]];
    
	self.gridView = [[TOGridView alloc] initWithFrame:self.view.bounds withCellClass:[TOGridViewTestCell class]];
    self.gridView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    self.gridView.delegate      = self;
    self.gridView.dataSource    = self;
    self.gridView.crossfadeCellsOnRotation = YES;
    [self.view addSubview:self.gridView];
     
    self.gridView.backgroundColor = [UIColor colorWithWhite:0.93f alpha:1.0f];
    //_gridView.backgroundColor = [UIColor blackColor];
    
    UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 150)];
    headerView.backgroundColor = [UIColor colorWithWhite:0.87f alpha:1.0f];
    self.gridView.headerView = headerView;
    
    //Add a label to the header view
    UILabel *testLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,0,150,44)];
    testLabel.text = @"Header View";
    testLabel.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    testLabel.font = [UIFont boldSystemFontOfSize:18.0f];
    testLabel.backgroundColor = [UIColor clearColor];
    testLabel.textColor = [UIColor colorWithWhite:0.2f alpha:1.0f];
    testLabel.shadowColor = [UIColor whiteColor];
    testLabel.shadowOffset = CGSizeMake(0.0f, 1.0f);
    testLabel.textAlignment = UITextAlignmentCenter;
    [self.gridView.headerView addSubview:testLabel];
    testLabel.center = self.gridView.headerView.center;
    
    //add a slight bevel to the bototm of the header
    UIView *headerBevel = [[UIView alloc] initWithFrame:CGRectMake(0, self.gridView.headerView.frame.size.height-1.0f, self.gridView.headerView.frame.size.width, 1.0f)];
    headerBevel.backgroundColor = [UIColor colorWithWhite:0.8f alpha:1.0f];
    headerBevel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.gridView.headerView addSubview:headerBevel];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Add" style:UIBarButtonItemStylePlain target:self action:@selector(addButtonTapped:)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Edit" style:UIBarButtonItemStylePlain target:self action:@selector(editButtonTapped:)];
    self.navigationController.navigationBar.tintColor = [UIColor colorWithWhite:0.1f alpha:1.0f];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if (interfaceOrientation == UIInterfaceOrientationPortrait)
        return YES;
    
    return YES;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
    return UIStatusBarStyleDefault;
}

#pragma mark -
#pragma mark Delegate
- (CGSize)boundaryInsetsForGridView:(TOGridView *)gridView
{
    return CGSizeMake(-1.0f, 0.0f);
}

- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        if ((NSInteger)CGRectGetWidth(self.view.bounds) > 768)
            return CGSizeMake(385, 100);
        else
            return CGSizeMake(342, 100);
    }
    else
    {
        if ((NSInteger)CGRectGetWidth(self.view.bounds) > 480)
            return CGSizeMake(285, 70);
        else if ((NSInteger)CGRectGetWidth(self.view.bounds) == 480)
            return CGSizeMake(481, 70);
        else
            return CGSizeMake(CGRectGetWidth(self.view.bounds), 70);
    }
}

- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
    {
        if ((NSInteger)CGRectGetWidth(self.view.bounds) > 768)
            return 2;
        else
            return 3;
    }
    else
    {
        if ((NSInteger)CGRectGetWidth(self.view.bounds) > 480)
            return 2;
        else
            return 1;
    }
}

- (NSUInteger)heightOfRowsInGridView:(TOGridView *)gridView
{
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        return 100;
    
    return 70;
}

- (void)gridView:(TOGridView *)gridView didTapCellAtIndex:(NSUInteger)index
{
    [gridView unhighlightCellAtIndex:index animated:YES];
    NSLog(@"Cell %d tapped!", index);
}

- (void)gridView:(TOGridView *)gridView didLongTapCellAtIndex:(NSInteger)index
{
    [gridView unhighlightCellAtIndex:index animated:YES];
    NSLog(@"Cell %d long tapped!", index);
}

- (void)gridView: (TOGridView *)gridView didMoveCellAtIndex:(NSInteger)prevIndex toIndex:(NSInteger)newIndex
{
    //reshuffle the numbers in the data source to match the new order
    NSNumber *number = [self.numbers objectAtIndex:prevIndex];
    [self.numbers removeObject:number];
    [self.numbers insertObject:number atIndex:newIndex];
}

#pragma mark -
#pragma mark Data Source
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView
{
    return [self.numbers count];
}

- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)cellIndex
{
    TOGridViewTestCell *cell = (TOGridViewTestCell *)[gridView dequeReusableCell];
    
    NSInteger cellNum = [[self.numbers objectAtIndex:cellIndex] intValue];
    cell.textLabel.text = [NSString stringWithFormat:@"Cell %d", cellNum];
    
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
    if( self.gridView.editing == NO )
    {
        NSNumber *newNumber = [NSNumber numberWithInteger:0];
        [self.numbers insertObject:newNumber atIndex:0];
        [self.gridView insertCellAtIndex:0 animated:YES];
    }
    else
    {
        NSArray *selectedCellIndices = [self.gridView indicesOfSelectedCells];
        
        NSMutableArray *numbersToDelete = [NSMutableArray array];
        for (NSNumber *indexToDelete in selectedCellIndices)
            [numbersToDelete addObject:[self.numbers objectAtIndex:[indexToDelete integerValue]]];
        
        //remove the entries from the data source
        [self.numbers removeObjectsInArray:numbersToDelete];
        //animate the cells leaving the grid view
        [self.gridView deleteCellsAtIndices:selectedCellIndices animated:YES];
    }
}

-(void)editButtonTapped:(id)sender
{
    [self.gridView setEditing:(!_gridView.editing) animated:YES];
    
    if (self.gridView.editing)
    {
        self.navigationItem.rightBarButtonItem.title    = @"Done";
        self.navigationItem.leftBarButtonItem.title     = @"Delete";
    }
    else
    {
        self.navigationItem.rightBarButtonItem.title    = @"Edit";
        self.navigationItem.leftBarButtonItem.title     = @"Add";
    }
}

@end
