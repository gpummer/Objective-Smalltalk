//
//  STBundle.m
//  ObjectiveSmalltalk
//
//  Created by Marcel Weiher on 05.08.20.
//

#import "STBundle.h"
#import "STCompiler.h"
#import "MPWSchemeScheme.h"
#import "MPWMethodStore.h"

@interface STBundle()

@property (nonatomic,strong) MPWBinding *binding;
@property (readonly) NSString *path;

@end


@implementation STBundle
{
    NSDictionary      *info;
    STCompiler     *interpreter;
    NSDictionary      *methodDict;
    MPWWriteBackCache *cachedResources;
    MPWWriteBackCache *cachedSources;
}

lazyAccessor(NSDictionary*, info, setInfo, readInfo)
lazyAccessor(STCompiler*, interpreter, setInterpreter, createInterpreter)
lazyAccessor(NSDictionary*, methodDict, setMethodDict, methodDictForSourceFiles)
lazyAccessor(MPWWriteBackCache*, cachedResources, setCachedResources, createCachedResources)
lazyAccessor(MPWWriteBackCache*, cachedSources, setCachedSources, createCachedSources)

CONVENIENCEANDINIT( bundle, WithBinding:newBinding )
{
    self=[super init];
    self.binding=newBinding;
    self.saveSource = YES;
    return self;
}

CONVENIENCEANDINIT( bundle, WithPath:(NSString*)newPath )
{
    MPWDiskStore *ds=[MPWDiskStore store];
    MPWBinding *binding=[ds bindingForReference:[MPWGenericReference referenceWithPath:newPath] inContext:nil];
    return [self initWithBinding:binding];
}

-(NSString*)path
{
    return [self.binding path];
}

-(NSURL*)url
{
    return [NSURL fileURLWithPath:self.path];
}

-(MPWBinding*)refForSubDir:(NSString*)subdir
{
    return [[self binding] referenceByAppendingReference:subdir];
}

-(id <MPWHierarchicalStorage>)storeForSubDir:(NSString*)subdir
{
    return [[self refForSubDir:subdir] asScheme];
}

-(id <MPWHierarchicalStorage>)resources
{
    return [self storeForSubDir:@"Resources"];
}

-(id <MPWHierarchicalStorage>)sourceDir
{
    return [self storeForSubDir:@"Sources"];
}


-(BOOL)isPresentOnDisk
{
    MPWBinding *binding=[self binding];
    @try {
        BOOL exists = [binding isBound];
        return exists;
    } @catch ( NSException *exception ) {
        return NO;
    }
}

-(id <MPWReferencing>)sourceRef
{
    return [self refForSubDir:@"Sources"];
//    NSString *path=[[self path] stringByAppendingPathComponent:@"Resources"];
//    return path;
}

-(id <MPWReferencing>)resourceRef
{
    NSString *path=[[self path] stringByAppendingPathComponent:@"Resources"];
    return path;
}

-(MPWWriteBackCache*)createCachedResources
{

    id <MPWStorage,MPWHierarchicalStorage> base = self.resources;
    MPWWriteBackCache *cache=[MPWWriteBackCache storeWithSource:base];
    cache.autoFlush=NO;
    return cache;
}

-(MPWWriteBackCache*)createCachedSources
{
    id <MPWStorage,MPWHierarchicalStorage> base = self.sourceDir;
    MPWWriteBackCache *cache=[MPWWriteBackCache storeWithSource:base];
    cache.autoFlush=NO;
    return cache;
}


-(NSArray<NSString*>*)sourceNames
{
    NSArray<NSString*>* allFiles = (NSArray<NSString*>*)[[(NSArray<NSString*>*)[[[[[self sourceDir] at:@"."] contents] collect] path] collect] lastPathComponent];
    return [[allFiles select] __hasSuffix:@"st"];
}

-(NSDictionary*)readInfo
{
    return [NSJSONSerialization JSONObjectWithData:[self storeForSubDir:@"."][@"Info.json"] options:0 error:nil];
}

-(void)configureInterpreter:(STCompiler*)newInterpreter
{
    [[newInterpreter schemes] setSchemeHandler:self.cachedResources   forSchemeName:@"rsrc"];
    [newInterpreter bindValue:[MPWByteStream Stdout] toVariableNamed:@"stdout"];
}

-(STCompiler*)createInterpreter
{
    STCompiler *compiler = [STCompiler compiler];
    [self configureInterpreter:compiler];
    return compiler;
}

-(id)resultOfCompilingSourceFileNamed:(NSString*)sourceName
{
    id statements=nil;
    @autoreleasepool {
        STCompiler *compiler=self.interpreter;
        id <MPWHierarchicalStorage> sources=[self cachedSources];
        NSData *stSource = sources[sourceName];
        statements=[[compiler compile:stSource] retain];
    }
    return [statements autorelease];
}

-(void)compileSourceFile:(NSString*)sourceName
{
    @autoreleasepool {
        [self.interpreter evaluate:[self resultOfCompilingSourceFileNamed:sourceName]];
    }
}

-(void)compileAllSourceFiles
{
    for ( NSString *filename in [self sourceNames] ) {
        @autoreleasepool {
            [self compileSourceFile:filename];
        }
    }
}

-(NSDictionary*)methodDictForSourceFiles
{
    [self compileAllSourceFiles];
    return [self.interpreter externalScriptDict];
}

-(void)writeToStore:(id <MPWStorage>)target
{
    [self methodDict];
    [target mkdirAt:@""];
    [target mkdirAt:@"Sources"];
    if ( self.saveSource ) {
        [[self.interpreter methodStore] fileoutToStore:[target relativeStoreAt:@"Sources"]];
    }
    [target mkdirAt:@"Resources"];
    id <MPWStorage> resourceTarget=[target relativeStoreAt:@"Resources"];
    target[@"Info.json"] = [self storeForSubDir:@"."][@"Info.json"];
    NSArray *children=[[self resources] childrenOfReference:@""];
    id <MPWStorage> resourceSource=[self resources];
    for ( id child in children ) {
        resourceTarget[child] = resourceSource[child];
    }
}



-(void)save
{
    NSError *outError=nil;
    [self.cachedResources flush];
    NSFileManager *fm=[NSFileManager defaultManager];
    [fm createDirectoryAtURL:self.url withIntermediateDirectories:YES attributes:nil error:&outError];
    if ( self.saveSource) {
        NSURL *sourcesDir=[NSURL URLWithString:@"Sources" relativeToURL:self.url];
        [fm createDirectoryAtURL:sourcesDir withIntermediateDirectories:YES attributes:nil error:&outError];
        [[self.interpreter methodStore] fileoutToStore:self.sourceDir];
    }
}

@end


#import <MPWFoundation/DebugMacros.h>

@implementation STBundle(testing)

+(instancetype)_testBundle
{
    NSString *testBundlePath=[[NSBundle bundleForClass:self] pathForResource:@"test" ofType:@"stb"];
    STBundle *bundle=[self bundleWithPath:testBundlePath];
    EXPECTNOTNIL(testBundlePath, @"bundle url");
    return bundle;
}

+(void)testBasicCreation
{
    STBundle *bundle=[self _testBundle];
    IDEXPECT([[bundle path] lastPathComponent],@"test.stb",@"bundle URL ivar");
}

+(void)testGetResource
{
    STBundle *bundle=[self _testBundle];
    NSData *png=[bundle resources][@"objst.png"];
    EXPECTNOTNIL(png, @"got the png");
    INTEXPECT(png.length, 4908, @"and it is the png I expected");
}

+(void)testGetSource
{
    STBundle *bundle=[self _testBundle];
    NSData *source=[bundle sourceDir][@"STBundleLoadedTestClass2.st"];
    EXPECTNOTNIL(source, @"got the source");
    INTEXPECT(source.length, 91, @"and it is the source I expected");
}

+(void)testGetAllSourceNames
{
    STBundle *bundle=[self _testBundle];
    NSArray<NSString*> *names=[bundle sourceNames];
    INTEXPECT(names.count, 2, @"number of source files");
    NSData *s1=[bundle sourceDir][names[0]];
    IDEXPECT(names[0], @"STBundleLoadedTestClass1.st", @"what is it?");
    INTEXPECT(s1.length,92,@"source file 1");
}

+(void)testReadInfo
{
    STBundle *bundle=[self _testBundle];
    NSDictionary *info=[bundle readInfo];
    IDEXPECT(info[@"site"], @"ObjectiveSTSite",@"site class name");
}

+(void)testGetInfo
{
    STBundle *bundle=[self _testBundle];
    NSDictionary *info=[bundle info];
    IDEXPECT(info[@"site"], @"ObjectiveSTSite",@"site class name");
}

+(void)testGetInterpreter
{
    STBundle *bundle=[self _testBundle];
    STCompiler *interpreter=[bundle interpreter];
    IDEXPECT( [interpreter evaluateScriptString:@"3+4"], @(7), @"interpreter works");
    NSData *png=[interpreter evaluateScriptString:@"rsrc:objst.png"];
    EXPECTNOTNIL(png, @"got the png");
    INTEXPECT(png.length, 4908, @"and it is the png I expected");

}

+(void)testCompileSources
{
    STBundle *bundle=[self _testBundle];
    NSDictionary *methodDict=[bundle methodDict];
    INTEXPECT( methodDict.count, 2, @"number of classes in methodDict");
}

+(void)testExistsOnDisk
{
    STBundle *bundleThatExists=[self _testBundle];
    EXPECTTRUE(bundleThatExists.isPresentOnDisk, @"isPresentOnDisk for one that exists");
    STBundle *bundleThatDoesNotExist=[self bundleWithPath:@"/bizzarePath/thisshouldntexist.stb"];
    EXPECTFALSE(bundleThatDoesNotExist.isPresentOnDisk, @"isPresentOnDisk for one that does not exist");
}

+(NSArray*)testSelectors
{
    return @[
        @"testBasicCreation",
        @"testGetResource",
        @"testGetSource",
        @"testGetAllSourceNames",
        @"testReadInfo",
        @"testGetInfo",
        @"testGetInterpreter",
        @"testCompileSources",
        @"testExistsOnDisk",
    ];
}
@end
