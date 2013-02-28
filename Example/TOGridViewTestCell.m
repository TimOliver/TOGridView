//
//  TOGridViewTestCell.m
//  TOGridViewExample
//
//  Created by Tim Oliver on 21/01/13.
//  Copyright (c) 2013 Timothy Oliver. All rights reserved.
//

#import "TOGridViewTestCell.h"

@implementation TOGridViewTestCell

@synthesize textLabel = _textLabel;

- (id)initWithFrame:(CGRect)frame
{
    if( self = [super initWithFrame: frame] )
    {
        self.opaque = YES;
        self.backgroundColor = [UIColor colorWithWhite: 0.96f alpha: 1.0f];
        
        UIImage *bg         = [[UIImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"CellBG" ofType: @"png"]];
        self.backgroundView = [[UIImageView alloc] initWithImage: [bg resizableImageWithCapInsets: UIEdgeInsetsMake(2, 2, 2, 2)]];
            
        UIImage *bgPressed              = [[UIImage alloc] initWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"CellBGPressed" ofType: @"png"]];
        self.highlightedBackgroundView  = [[UIImageView alloc] initWithImage: [bgPressed resizableImageWithCapInsets: UIEdgeInsetsMake(2, 2, 2, 2)]];
        
        self.selectedBackgroundView = self.highlightedBackgroundView;
        
        _textLabel = [[UILabel alloc] initWithFrame: CGRectMake( 10, (frame.size.height/2)-15, 100, 30)];
        _textLabel.textColor = [UIColor colorWithWhite: 0.2f alpha: 1.0f];
        _textLabel.backgroundColor = [UIColor colorWithWhite: 0.96f alpha: 1.0f];
        _textLabel.font = [UIFont boldSystemFontOfSize: 19.0f];
        _textLabel.shadowColor = [UIColor whiteColor];
        _textLabel.shadowOffset = CGSizeMake( 0, 1.0f);
        
        [self.contentView addSubview: _textLabel];
        
    }
    
    return self;
}
@end
