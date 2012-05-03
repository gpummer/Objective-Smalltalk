//
//  MPWScheme.h
//  MPWTalk
//
//  Created by Marcel Weiher on 6.1.10.
//  Copyright 2010 Marcel Weiher. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface MPWScheme : NSObject {

}

+scheme;
-evaluateIdentifier:anIdentifer withContext:aContext;
-bindingForName:(NSString*)variableName inContext:aContext;

@end
