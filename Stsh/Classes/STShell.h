//
//  MPWStsh.h
//  MPWShellScriptKit
//
//  Created by Marcel Weiher on 26/01/2006.
//  Copyright 2006 Marcel Weiher. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MPWFoundation/MPWObject.h>

@class MPWByteStream,STEvaluator,STCompiler,NSRunLoop;

@interface STShell : MPWObject {
    MPWByteStream  *Stdout,*Stdin,*Stderr;
    BOOL   readingFile;
    BOOL   echo;
	STEvaluator*		_evaluator;
	id		retval;
    NSString *prompt;
    char  cstrPrompt[200];
    int   completionLimit;
    NSRunLoop *runLoop;
    NSThread *runLoopThread;
}

-initWithArgs:args;
-(STCompiler*)evaluator;
-retval;
-(void)setRetval:newRetval;
-(void)run;

@property (nonatomic,strong) NSArray *args;
@property (nonatomic,strong) NSMutableArray *history;
@property (nonatomic,strong) NSString *commandName;
@property (strong) NSException *lastException;

@end

