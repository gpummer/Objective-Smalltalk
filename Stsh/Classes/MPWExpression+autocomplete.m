//
//  MPWExpression+autocomplete.m
//  ObjectiveSmalltalk
//
//  Created by Marcel Weiher on 5/13/14.
//
//

#import "MPWExpression+autocomplete.h"
#import "MPWEvaluator.h"
#import "MPWMessageExpression.h"
#import "MPWIdentifierExpression.h"
#import "MPWAssignmentExpression.h"
#import "MPWStatementList.h"
#import "MPWEvaluator.h"
#import "MPWScheme.h"
#import "MPWMethodMirror.h"
#import "MPWObjectMirror.h"
#import "MPWClassMirror.h"
#import "MPWLiteralExpression.h"
#import "MPWStCompiler.h"

@implementation MPWStCompiler(completion)

-(NSArray*)completionsForString:(NSString*)s
{
    NSString *dummy=@"";
    MPWExpression *e=[self compile:s];
    return [e completionsForString:s withEvaluator:self resultName:&dummy];
}

@end


@implementation MPWExpression(completion)

-(NSSet *)lessInterestingMessageNames
{
    static NSSet *lessInteresting=nil;
    if (!lessInteresting) {
        lessInteresting=[[NSSet alloc] initWithArray:
                         @[
                           @"dealloc",
                           @"finalize",
                           @"copy",
                           @"copyWithZone:",
                           @"hash",
                           @"isEqual:",
                           @"release",
                           @"autorelease",
                           @"retain",
                           @"retainCount",
                           @"isKindOfClass:",
                           @"initWithCoder:",
                           @"encodeWithCoder:",
                           @"classForCoder",
                           @"valueForKey:",
                           @"takeValue:forKey:",
                           @"setValue:forKey",
                           @"self",
                           @"zone",
                           ]];
    }
    return lessInteresting;
}

-(NSArray *)sortMessageNamesByImportance:(NSArray *)incomingMessageNames
{
    NSMutableArray *firstTier=[NSMutableArray array];
    NSMutableArray *secondTier=[NSMutableArray array];
    for ( NSString *messageName in incomingMessageNames) {
        if ( [messageName hasPrefix:@"_"] ||
            [messageName hasPrefix:@"accessibility"] ||
            [[self lessInterestingMessageNames] containsObject:messageName] )
        {
            [secondTier addObject:messageName];
        } else {
            [firstTier addObject:messageName];
        }
    }
    
    return [firstTier arrayByAddingObjectsFromArray:secondTier];
}


-(NSArray *)messageNamesForObject:value matchingPrefix:(NSString*)prefix
{
    NSMutableSet *alreadySeen=[NSMutableSet set];
    NSMutableArray *messages=[NSMutableArray array];
    MPWObjectMirror *om=[MPWObjectMirror mirrorWithObject:value];
    MPWClassMirror *cm=[om classMirror];
    while ( cm ){
        for (MPWMethodMirror *mm in [cm methodMirrors]) {
            NSString *methodName = [mm name];
            
            if ( (!prefix || [prefix length]==0 || [methodName hasPrefix:prefix]) &&
                ![alreadySeen containsObject:methodName]) {
                [messages addObject:methodName];
                [alreadySeen addObject:methodName];
            }
        }
        cm=[cm superclassMirror];
    }
    return [self sortMessageNamesByImportance:messages];
}

-(NSArray*)completionsForString:(NSString*)s withEvaluator:(MPWEvaluator*)evaluator resultName:(NSString **)resultName
{
    return @[];
}




@end

@implementation MPWIdentifierExpression(completion)



-(NSArray *)schemesToCheck
{
    return @[ @"default", @"class", @"scheme"];
}

-(NSArray *)identifiersInEvaluator:(MPWEvaluator*)evaluator matchingPrefix:(NSString*)prefix  schemeNames:(NSArray *)schemeNames
{
    NSMutableArray *completions=[NSMutableArray array];
    for ( NSString *schemeName in schemeNames) {
        NSArray *nakedNames=[[evaluator schemeForName:schemeName] completionsForPartialName:prefix inContext:evaluator];
        [completions addObjectsFromArray:nakedNames];
    }
    return completions;
}

-(NSArray*)completionsForString:(NSString*)s withEvaluator:(MPWEvaluator*)evaluator resultName:(NSString **)resultName
{
    MPWBinding* binding=[[evaluator localVars] objectForKey:[self name]];
    id value=[binding value];
    NSArray *completions;
    if ( value ) {
//        NSLog(@"have value, s='%@'",s);
        if ( [s hasSuffix:@" "]) {
//            NSLog(@"get message names");
            completions=[self messageNamesForObject:value matchingPrefix:nil];
        } else {
            completions=@[ @" "];
        }
    } else {
        NSArray *schemesToCheck = [self schemesToCheck];
        if ( [self scheme] ) {
            schemesToCheck=@[ [self scheme] ];
        }
        completions=[self identifiersInEvaluator:evaluator matchingPrefix:[self name] schemeNames:schemesToCheck];
        *resultName=[self name];
    }
//    NSLog(@"completions: '%@'",completions);
    return completions;
}

@end

@implementation MPWMessageExpression(completion)



-(NSArray*)completionsForString:(NSString*)s withEvaluator:(MPWEvaluator*)evaluator resultName:(NSString **)resultName
{
    id evaluatedReceiver = [[self receiver] evaluateIn:evaluator];
    NSArray *completions=nil;
    if ( [s hasSuffix:@" "] ) {
        id value=[self evaluateIn:evaluator];
        completions=[self messageNamesForObject:value matchingPrefix:nil];
//    } else if ( [evaluatedReceiver respondsToSelector:[self selector]]) {
//        completions = [self messageNamesForObject:evaluatedReceiver matchingPrefix:name];
//        *resultName=name;
    } else {
        NSString *name=[self messageNameForCompletion];
        if ( [name hasSuffix:@":"]) {
            NSRange exprRange=[s rangeOfString:name];
            name=[name stringByAppendingString:[s substringFromIndex:exprRange.location+exprRange.length]];
        }
        *resultName=name;
        completions=[self messageNamesForObject:evaluatedReceiver matchingPrefix:name];
        if ( [completions count] == 1 && [[completions firstObject] isEqualToString:name]) {
            completions=@[];
        }
        if ( [completions count] == 0 && [evaluatedReceiver respondsToSelector:[self selector]]) {
            completions=@[@" "];
        }
    }
//    NSLog(@"completions for '%@'/'%@' -> %@",s,[self messageNameForCompletion],completions);
    return completions;
}


@end

@implementation MPWAssignmentExpression(completion)

-(NSArray*)completionsForString:(NSString*)s withEvaluator:(MPWEvaluator*)evaluator resultName:(NSString **)resultName
{
    return [[self rhs] completionsForString:s withEvaluator:evaluator resultName:resultName];
}

@end

@implementation MPWStatementList(completion)

-(NSArray*)completionsForString:(NSString*)s withEvaluator:(MPWEvaluator*)evaluator resultName:(NSString **)resultName
{
    return [[[self statements] lastObject] completionsForString:s withEvaluator:evaluator resultName:resultName];
}

@end

@implementation MPWLiteralExpression(completion)

-(NSArray*)completionsForString:(NSString*)s withEvaluator:(MPWEvaluator*)evaluator resultName:(NSString **)resultName
{
    return [self messageNamesForObject:[self theLiteral] matchingPrefix:nil];
}

@end


@interface MPWAutocompletionTests : NSObject {}

@end

@implementation MPWAutocompletionTests

+completionsForString:(NSString*)s
{
    NSString *res=nil;
    MPWStCompiler *c=[MPWStCompiler compiler];
    MPWExpression *e=[c compile:s];
    return [e completionsForString:s withEvaluator:c resultName:&res];
}

+(void)testMessageCompletions
{
    IDEXPECT([self completionsForString:@"3 inte"], (@[@"integerValue"]), @"");
    IDEXPECT([self completionsForString:@"3 int"], (@[@"integerValue", @"intValue"]), @"");
    IDEXPECT([self completionsForString:@"3 inter"], (@[]), @"");
    IDEXPECT([self completionsForString:@"3 intValue"], (@[ @" "]), @"");
    
    IDEXPECT([self completionsForString:@"3 insertValue:"], (@[ @"insertValue:atIndex:inPropertyWithKey:", @"insertValue:inPropertyWithKey:" ] ), @"");
}

+testSelectors
{
    return @[
             @"testMessageCompletions"
             ];
}

@end
