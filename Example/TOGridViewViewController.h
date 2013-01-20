//
//  TOGridViewViewController.h
//  TOGridView
//
//  Created by Tim Oliver on 14/01/13.
//  Copyright 2013 Timothy Oliver. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "TOGridView.h"


@interface TOGridViewViewController : UIViewController <TOGridViewDataSource, TOGridViewDelegate> {
    TOGridView *_gridView;
}

@end
