//
//  TOGridViewViewController.m
//  TOGridView
//
//  Created by Tim Oliver on 14/01/13.
//  Copyright 2013 Timothy Oliver. All rights reserved.
//

#import "TOGridViewViewController.h"
#import "UIDevice+ScreenIdioms.h"
#import <QuartzCore/QuartzCore.h>

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

	_gridView = [[TOGridView alloc] initWithFrame: self.view.bounds];
    _gridView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _gridView.delegate = self;
    _gridView.dataSource = self;
    [self.view addSubview: _gridView]; 
     
    UIView *backgroundView = [[UIView alloc] initWithFrame: self.view.bounds];
    backgroundView.backgroundColor = [UIColor scrollViewTexturedBackgroundColor];
    _gridView.backgroundView = backgroundView;
    
    UIView *headerView = [[UIView alloc] initWithFrame: CGRectMake(0, 0, CGRectGetWidth(self.view.bounds), 150)];
    headerView.backgroundColor = [UIColor whiteColor];
    _gridView.headerView = headerView;
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
    return CGSizeMake(0, 15);
}

- (CGSize)sizeOfCellsForGridView:(TOGridView *)gridView
{
    if( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad )
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return CGSizeMake(380, 50);
        else
            return CGSizeMake(335, 50);
    }
    else
    {
        if( UIInterfaceOrientationIsPortrait( self.interfaceOrientation ) )
            return CGSizeMake(320, 50);
        else
        {
            if( UI_USER_INTERFACE_SCREEN_IDIOM() == UIUserInterfaceScreenIdiomPhone4Inch )
                return CGSizeMake(282, 50);
            else
                return CGSizeMake(480, 50);
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
    return 60;
}

#pragma mark -
#pragma mark Data Source
- (NSUInteger)numberOfCellsInGridView:(TOGridView *)gridView
{
    return 80;
}

- (TOGridViewCell *)gridView:(TOGridView *)gridView cellForIndex:(NSInteger)cellIndex
{
    TOGridViewCell *cell = [_gridView dequeReusableCell];
    return cell;
}


@end
