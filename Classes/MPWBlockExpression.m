//
//  MPWBlockExpression.m
//  Arch-S
//
//  Created by Marcel Weiher on 11/22/04.
//  Copyright 2004 Marcel Weiher. All rights reserved.
//

#import "MPWBlockExpression.h"
#import "MPWBlockContext.h"
#import <MPWFoundation/NSNil.h>
#import "MPWIdentifier.h"
#import "MPWStatementList.h"
#import "MPWScriptedMethod.h"

@implementation MPWBlockExpression
{
    NSArray *capturedVariables;
}

idAccessor( statements, setStatements )
idAccessor( declaredArguments, setDeclaredArguments )
lazyAccessor(NSArray *, capturedVariables, setCapturedVariables, computeCapturedVariables )

-initWithStatements:newStatements arguments:newArgNames
{
	self=[super init];
	[self setStatements:newStatements];
	[self setDeclaredArguments:newArgNames];
	return self;
}

-statementArray
{
    id actualStatements = [self statements];
    while ( [actualStatements isKindOfClass:[MPWStatementList class]]) {
        actualStatements=[actualStatements statements];
    }
    return actualStatements;
}

+blockWithStatements:newStatements arguments:newArgNames
{
	return [[[self alloc] initWithStatements:newStatements arguments:newArgNames] autorelease];
}

-evaluateIn:aContext
{
	return [MPWBlockContext blockContextWithBlock:self context:aContext];
}

-(void)addToVariablesWritten:(NSMutableSet*)variablesWritten
{
	[statements addToVariablesWritten:variablesWritten];
}

-(void)addToVariablesRead:(NSMutableSet*)variablesRead
{
	[statements addToVariablesRead:variablesRead];
}



-(NSArray*)implicitUsedArguments
{
    NSMutableArray *implicits=[NSMutableArray array];
    for ( MPWIdentifier *identifier in [self variablesRead]) {
        if ( [[identifier identifierName] hasPrefix:@"$"] ) {
            [implicits addObject:[identifier identifierName]];
        }
    }
    return implicits;
}

-(NSArray*)addUnusedImplicitArguments:(NSArray*)usedImplicitarguments
{
    int maxArgNo=-1;
    for (NSString *implicitArgName in usedImplicitarguments) {
        int argNo=[[implicitArgName substringFromIndex:1] intValue];
        maxArgNo=MAX(maxArgNo,argNo);
    }
    NSMutableArray *args=[NSMutableArray array];
    for (int i=0;i<=maxArgNo;i++) {
        [args addObject:[NSString stringWithFormat:@"$%d",i]];
    }
    return args;
}

-(NSArray*)arguments
{
    NSArray *arguments=[self declaredArguments];
    if ( arguments.count == 0) {
        arguments=[self implicitUsedArguments];
        arguments=[self addUnusedImplicitArguments:arguments];
    }
    return arguments;
}

-(void)accumulateBlocks:(NSMutableArray*)blocks
{
    for ( id statement in [self statementArray] ) {
        [statement accumulateBlocks:blocks];
    }
    [blocks addObject:self];
}

-(NSArray*)capturedVariablesFromMethod:(MPWScriptedMethod*)method
{
    MPWStatementList *s=[self statements];
    NSMutableSet *variablesReferencedInBlock=[NSMutableSet set];
    [s addToVariablesRead:variablesReferencedInBlock];
    [s addToVariablesWritten:variablesReferencedInBlock];
    
    
    return [variablesReferencedInBlock allObjects];
}

-(NSArray*)computeCapturedVariables
{
    NSAssert( self.method , @"need method to compute captures");
    return [self capturedVariablesFromMethod:self.method];
}

-(int)numberOfCaptures
{
    return self.method ? (int)self.capturedVariables.count : 0;
}

-(bool)hasCaptures
{
    return self.numberOfCaptures > 0;
}

-(bool)needsToBeOnStack
{
    return self.hasCaptures;
}

-(NSString*)description
{
    return [NSString stringWithFormat:@"<%@:%p: statements: %@ arguments: %@>",[self class],self,statements,[self arguments]];
}


-(void)dealloc
{
	[statements release];
	[declaredArguments release];
    [capturedVariables release];
    [_capturedVariableOffets release];
    [_blockFunctionSymbol release];
    [_blockDescriptorSymbol release];
	[super dealloc];
}

@end

#import "STCompiler.h"
#import "MPWClassDefinition.h"



@implementation MPWBlockExpression(testing)

+(MPWClassDefinition*)_classDefinitionFor:(NSString*)code
{
    STCompiler *compiler = [STCompiler compiler];
    MPWClassDefinition *theClass = [compiler compile:code];
    return theClass;
}

+(void)testComputeBlockCaptures
{
    
    MPWClassDefinition *theClass = [self _classDefinitionFor:@"class __STTestBlockCaptureComputation1 {  -main:args {  var a. a := 10. { a - 10. } value. } }"];
    MPWScriptedMethod *method=theClass.methods.firstObject;
    EXPECTNOTNIL( method, @"got a method");
    NSArray *blocks = method.blocks;
    INTEXPECT(blocks.count, 1, @"numbr of blocks");
    MPWBlockExpression *block = blocks.firstObject;
    NSArray *captured=[block capturedVariablesFromMethod:method];
    INTEXPECT( captured.count, 1, @"number of captures");
    IDEXPECT( [captured.firstObject name], @"a", @"name of capture");
}

+(void)testIsOnStack
{
    MPWClassDefinition *theClass = [self _classDefinitionFor:@"class __STTestBlockCaptureComputation1 {  -first {  { 10. } value. }  -second:a { { a -10. } value. } }"];
    INTEXPECT(theClass.methods.count,2,@"number of methods");
    MPWScriptedMethod *first=theClass.methods.firstObject;
    MPWScriptedMethod *second=theClass.methods.lastObject;
    MPWBlockExpression *noCaptureBlock = first.blocks.firstObject;
    MPWBlockExpression *captureBlock = second.blocks.firstObject;
    EXPECTFALSE( noCaptureBlock.hasCaptures, @"first block has no captures");
    EXPECTFALSE( noCaptureBlock.needsToBeOnStack, @"first block doesn't need to be on stack");
    EXPECTTRUE( captureBlock.hasCaptures, @"2nd block has  captures");
    EXPECTTRUE( captureBlock.needsToBeOnStack, @"2nd block needs to be on stack");

}

+testSelectors
{
    return @[
        @"testComputeBlockCaptures",
        @"testIsOnStack",
    ];
}

@end

