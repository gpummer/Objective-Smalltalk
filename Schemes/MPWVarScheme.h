//
//  MPWVarScheme.h
//  MPWTalk
//
//  Created by Marcel Weiher on 25.12.09.
//  Copyright 2009 Marcel Weiher. All rights reserved.
//

#import "MPWScheme.h"

@class MPWEvaluator;

@interface MPWVarScheme : MPWScheme {
}

@property (nonatomic, strong ) MPWEvaluator *context;

@end
