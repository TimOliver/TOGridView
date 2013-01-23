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
    return CGSizeZero;
}

- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView
{
    if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return CGSizeMake(384, 100);
        else
            return CGSizeMake(341, 100);
    }
    else
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return CGSizeMake(320, 70);
        else
        {
            if( UI_USER_INTERFACE_SCREEN_IDIOM() == UIUserInterfaceScreenIdiomPhone4Inch )
                return CGSizeMake(284, 70);
            else
                return CGSizeMake(480, 70);
        }
    }
}

- (NSUInteger)numberOfCellsPerRowForGridView:(TOGridView *)gridView
{
    if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return 2;
        else
            return 3;
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

#pragma mark -
#pragma mark Data Source
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView
{
    return 65;
}

- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)cellIndex
{
    TOGridViewTestCell *cell = (TOGridViewTestCell *)[_gridView dequeReusableCell];
    
    cell.textLabel.text = [NSString stringWithFormat: @"Cell %d", cellIndex];
    return cell;
}

-(void)editButtonTapped:(id)sender
{
    [_gridView setEditing: !_gridView.editing animated: YES];
    
    if( _gridView.editing )
        self.navigationItem.rightBarButtonItem.title = @"Done";
    else
        self.navigationItem.rightBarButtonItem.title = @"Edit";
}

@end
