//
//  MPWMachOWriter.m
//  ObjSTNative
//
//  Created by Marcel Weiher on 14.09.22.
//
// http://www.cilinder.be/docs/next/NeXTStep/3.3/nd/DevTools/14_MachO/MachO.htmld/index.html
//

#import "MPWMachOWriter.h"
#import <mach-o/loader.h>
#import <nlist.h>
#import <mach-o/reloc.h>
#import <mach-o/arm64/reloc.h>
#import "Mach_O_Structs.h"
#import "MPWMachOSection.h"
#import "MPWMachOSectionWriter.h"

@interface MPWMachOWriter()

@property (nonatomic, assign) int numLoadCommands;
@property (nonatomic, assign) int cputype;
@property (nonatomic, assign) int filetype;
@property (nonatomic, assign) int loadCommandSize;
@property (nonatomic, assign) long totalSegmentSize;
@property (nonatomic, strong) NSMutableDictionary *stringTableOffsets;
@property (nonatomic, strong) MPWByteStream *stringTableWriter;

@property (nonatomic, strong) NSMutableDictionary *globalSymbolOffsets;
@property (nonatomic, strong) NSDictionary *externalSymbols;

@property (nonatomic, strong) MPWMachOSectionWriter *textSectionWriter;
@property (nonatomic, strong) NSMutableArray<MPWMachOSectionWriter*>* sectionWriters;

//@property (nonatomic, strong) NSMutableDictionary *relocationEntries;



@end


@implementation MPWMachOWriter
{
    symtab_entry *symtab;
    int symtabCount;
    int symtabCapacity;
}


-(void)addSectionWriter:(MPWMachOSectionWriter*)newWriter
{
    int sectionNumber = (int)self.sectionWriters.count + 1;
    newWriter.sectionNumber = sectionNumber;
    newWriter.symbolWriter = self;

    [self.sectionWriters addObject:newWriter];
}

-(NSArray<MPWMachOSectionWriter*>*)activeSectionWriters
{
    NSMutableArray *active=[NSMutableArray array];
    for (MPWMachOSectionWriter *writer in self.sectionWriters) {
        if ( writer.isActive) {
            [active addObject:writer];
        }
    }
    return active;
}

-(MPWMachOSectionWriter*)addSectionWriterWithSegName:(NSString*)segname sectName:(NSString*)sectname flags:(int)flags
{
    if (!self.sectionWriters) {
        self.sectionWriters = [NSMutableArray array];
    }
    MPWMachOSectionWriter *writer=[MPWMachOSectionWriter stream];
    writer.segname = segname;
    writer.sectname = sectname;
    writer.flags = flags;
    [self addSectionWriter:writer];
    return writer;
}

-(void)growSymtab
{
    symtabCapacity *= 2;
    symtab_entry *newSymtab = calloc( symtabCapacity , sizeof(symtab_entry));
    if ( symtab ) {
        memcpy( newSymtab, symtab, symtabCount * sizeof(symtab_entry));
        free(symtab);
    }
    symtab = newSymtab;
}

-(instancetype)initWithTarget:(id)aTarget
{
    self=[super initWithTarget:aTarget];
    if ( self ) {
        self.cputype = CPU_TYPE_ARM64;
        self.filetype = MH_OBJECT;
        self.stringTableWriter = [MPWByteStream stream];
        [self.stringTableWriter appendBytes:"" length:1];
        self.stringTableOffsets=[NSMutableDictionary dictionary];
        self.globalSymbolOffsets=[NSMutableDictionary dictionary];
        self.textSectionWriter = [self addSectionWriterWithSegName:@"__TEXT" sectName:@"__text" flags:S_ATTR_PURE_INSTRUCTIONS | S_ATTR_SOME_INSTRUCTIONS];
        [self addSectionWriterWithSegName:@"__DATA" sectName:@"_objectclasslist" flags:0];
        symtabCapacity = 10;
        [self growSymtab];
        
        
    }
    return self;
}


-(void)writeHeader
{
    struct mach_header_64 header={};
    header.magic = MH_MAGIC_64;
    header.cputype = self.cputype;
    header.filetype = self.filetype;
    header.ncmds = self.numLoadCommands;
    header.sizeofcmds = self.loadCommandSize;
    [self appendBytes:&header length:sizeof header];

}

-(int)segmentOffset
{
    return self.loadCommandSize + sizeof(struct mach_header_64);
}

-(int)symbolTableOffset
{
    return [self segmentOffset] + self.totalSegmentSize;
}


-(int)numSymbols
{
    return symtabCount;
}

-(int)symbolTableSize
{
    return [self numSymbols] * sizeof(symtab_entry);
}

-(int)stringTableOffset
{
    return [self symbolTableOffset] + [self symbolTableSize];
}

-(int)segmentCommandSize
{
    return sizeof(struct segment_command_64) + ([self activeSectionWriters].count * sizeof(struct section_64));
}

-(void)writeSegmentLoadCommand
{
    long segmentOffset = [self segmentOffset];
    NSArray *writers = [self activeSectionWriters];
    long sectionOffset = segmentOffset;
    long segmentSize = 0;
    for ( MPWMachOSectionWriter *writer in writers) {
        writer.offset = sectionOffset;
        segmentSize += writer.totalSize;
        sectionOffset += writer.totalSize;
    }
    self.totalSegmentSize = segmentSize;
    
    struct segment_command_64 segment={};
    segment.cmd = LC_SEGMENT_64;
    segment.cmdsize = [self segmentCommandSize];
    segment.nsects = [self sectionWriters].count;
    segment.fileoff=segmentOffset;
    segment.filesize=segmentSize;
    segment.vmsize = segmentSize;
    segment.initprot = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE;
    segment.maxprot = VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE;
    [self appendBytes:&segment length:sizeof segment];

    for ( MPWMachOSectionWriter *writer in writers) {
        [writer writeSectionLoadCommandOnWriter:self];
    }
}


-(void)writeSymbolTableLoadCommand
{
    struct symtab_command symtab={};
    symtab.cmd = LC_SYMTAB;
    symtab.cmdsize = sizeof symtab;
    symtab.nsyms = [self numSymbols];
    symtab.symoff = [self symbolTableOffset];
    symtab.stroff = [self stringTableOffset];
    symtab.strsize = (int)[self.stringTableWriter length];
    [self appendBytes:&symtab length:sizeof symtab];
}

-(void)addTextSectionData:(NSData*)data
{
    [self.textSectionWriter writeData:data];
}

-(void)writeSections
{
//    NSLog(@"sections to write: %@",self.activeSectionWriters);
    NSAssert2(self.length == [self segmentOffset], @"Actual symbol table offset %ld does not match computed %d", (long)self.length,[self symbolTableOffset]);
    NSLog(@"write %ld bytes length now %ld",self.textSectionWriter.length,self.length);
    for ( MPWMachOSectionWriter *sectionWriter in [self activeSectionWriters]) {
        [sectionWriter writeSectionDataOn:self];
    }
    NSLog(@"after writing %ld bytes length now %ld",self.textSectionWriter.length,self.length);
//     [self writeData:self.textSection];
}

-(void)writeStringTable
{
    [self writeData:(NSData*)[self.stringTableWriter target]];
}

-(int)stringTableOffsetOfString:(NSString*)theString
{
    int offset = [self.stringTableOffsets[theString] intValue];
    if ( !offset ) {
        offset=(int)[self.stringTableWriter length];
        [self.stringTableWriter writeObject:theString];
        [self.stringTableWriter appendBytes:"" length:1];
        self.stringTableOffsets[theString]=@(offset);
    }
    return offset;
}

-(void)generateStringTable
{
    for (NSString* symbol in self.globalSymbolOffsets.allKeys) {
        [self stringTableOffsetOfString:symbol];
    }
}

-(int)addGlobalSymbol:(NSString*)symbol atOffset:(int)offset type:(int)theType section:(int)theSection
{
    int entryIndex = 0;
    NSNumber *offsetEntry = self.globalSymbolOffsets[symbol];
    if ( offsetEntry == nil ) {
        entryIndex = symtabCount;
        self.globalSymbolOffsets[symbol]=@(symtabCount);
        symtab_entry entry={};
        entry.type = theType;
        entry.section = theSection;      // TEXT section
        entry.string_offset=[self stringTableOffsetOfString:symbol];
        entry.address = offset;
        if ( symtabCount >= symtabCapacity ) {
            [self growSymtab];
        }
        symtab[symtabCount++]=entry;

    } else {
        entryIndex = [offsetEntry intValue];
    }
    return entryIndex;
}

-(int)addGlobalSymbol:(NSString*)symbol atOffset:(int)offset
{
    return [self addGlobalSymbol:symbol atOffset:offset type:0xf section:1];
}

-(void)writeSymbolTable
{
    NSAssert2(self.length == [self symbolTableOffset], @"Actual symbol table offset %ld does not match computed %d", (long)self.length,[self symbolTableOffset]);
    [self appendBytes:symtab length:symtabCount * sizeof(symtab_entry)];
}


-(NSData*)data
{
    return (NSData*)self.target;
}

-(void)writeFile
{
    self.numLoadCommands = 2;
    self.loadCommandSize = sizeof(struct symtab_command) + [self segmentCommandSize];
//    self.loadCommandSize += sizeof(struct section_64);
    [self writeHeader];
    [self generateStringTable];
    [self writeSegmentLoadCommand];
    [self writeSymbolTableLoadCommand];
    [self writeSections];
    [self writeSymbolTable];
    [self writeStringTable];
}

-(void)dealloc
{
    free( symtab );
    [super dealloc];
}

@end


#import <MPWFoundation/DebugMacros.h>
#import "MPWMachOReader.h"
#import "MPWMachOClassReader.h"

@implementation MPWMachOWriter(testing) 

+(void)testCanWriteHeader
{
    MPWMachOWriter *writer = [self stream];
    [writer writeHeader];
    
    NSData *macho=[writer data];
    MPWMachOReader *reader = [[[MPWMachOReader alloc] initWithData:macho] autorelease];
    EXPECTTRUE([reader isHeaderValid], @"header valid");
    INTEXPECT([reader cputype],CPU_TYPE_ARM64,@"cputype");
    INTEXPECT([reader filetype],MH_OBJECT,@"filetype");
    INTEXPECT([reader numLoadCommands],0,@"number load commands");
}

+(void)testCanWriteGlobalSymboltable
{
    MPWMachOWriter *writer = [self stream];
    [writer addGlobalSymbol:@"_add" atOffset:10];
    NSData *machineCode = [self frameworkResource:@"add" category:@"aarch64"];
    [writer addTextSectionData: machineCode];
//    INTEXPECT(writer.textSectionSize,8,@"bytes in text section");
    
    [writer writeFile];
    
    NSData *macho=[writer data];
//    [macho writeToFile:@"/tmp/generated.macho" atomically:YES];
    MPWMachOReader *reader = [[[MPWMachOReader alloc] initWithData:macho] autorelease];
    
    EXPECTTRUE([reader isHeaderValid],@"valid header");
    INTEXPECT([reader numLoadCommands],2,@"number of load commands");
    INTEXPECT([reader numSymbols],1,@"number of symbols");
    NSArray *strings = [reader stringTable];
    EXPECTTRUE([reader isSymbolGlobalAt:0],@"first symbol _add is global");
    IDEXPECT([reader symbolNameAt:0],@"_add",@"first symbol _add is global");
    INTEXPECT([reader symbolOffsetAt:0],10,@"offset of _add");
    IDEXPECT( strings.lastObject, @"_add", @"last string in string table");
    INTEXPECT( strings.count, 1, @"number of strings");
    IDEXPECT( strings, (@[@"_add"]), @"string table");
    IDEXPECT( [[reader textSection] sectionData],machineCode, @"machine code from text section");
}

+(void)testCanWriteStringsToStringTable
{
    MPWMachOWriter *writer = [self stream];
    INTEXPECT( [writer stringTableOffsetOfString:@"_add"],1,@"offset");
    INTEXPECT( [writer stringTableOffsetOfString:@"_sub"],6,@"offset");
    INTEXPECT( [writer stringTableOffsetOfString:@"_add"],1,@"repeat");
}

+(void)testWriteLinkableAddFunction
{
    MPWMachOWriter *writer = [self stream];
    [writer addGlobalSymbol:@"_add" atOffset:10];
    NSData *machineCode = [self frameworkResource:@"add" category:@"aarch64"];
    [writer addTextSectionData:machineCode];
    [writer writeFile];
    NSData *macho=[writer data];
    [macho writeToFile:@"/tmp/add.o" atomically:YES];
    
}

+(void)testWriteFunctionWithRelocationEntries
{
    MPWMachOWriter *writer = [self stream];
    
    [writer.textSectionWriter addRelocationEntryForSymbol:@"_other" atOffset:12];
    NSData *machineCode = [self frameworkResource:@"add" category:@"aarch64"];
    [writer addTextSectionData:machineCode];
    [writer writeFile];
    NSData *macho=[writer data];
    [macho writeToFile:@"/tmp/reloc.o" atomically:YES];

    MPWMachOReader *reader = [[[MPWMachOReader alloc] initWithData:macho] autorelease];
    INTEXPECT([[reader textSection] numRelocEntries],1,@"number of undefined symbol reloc entries");
    INTEXPECT([[reader textSection] relocEntryOffset],216,@"offset of undefined symbol reloc entries");
    IDEXPECT( [[reader textSection] nameOfRelocEntryAt:0],@"_other",@"name");
    INTEXPECT( [[reader textSection] offsetOfRelocEntryAt:0],12,@"address");
    INTEXPECT([[reader textSection] typeOfRelocEntryAt:0],ARM64_RELOC_BRANCH26,@"reloc entry type");
}

+(void)testWriteClass
{
    MPWMachOWriter *writer = [self stream];
 
    MPWMachOSectionWriter *classNameWriter = [writer addSectionWriterWithSegName:@"__TEXT" sectName:@"__objc_classname" flags:0];
    [writer addTextSectionData:[self frameworkResource:@"add" category:@"aarch64"]];
    [classNameWriter writeString:@"TestClass"];
    [classNameWriter appendBytes:"" length:1];
    [writer writeFile];
    NSData *macho=[writer data];
    [macho writeToFile:@"/tmp/class.o" atomically:YES];

    
    MPWMachOReader *machoReader = [[[MPWMachOReader alloc] initWithData:macho] autorelease];
    INTEXPECT( machoReader.numSections, 3,@"number of sections");
    for (int i=1;i<machoReader.numSections;i++) {
        MPWMachOSection *s=[machoReader sectionAtIndex:i];
        NSLog(@"section %@, segname='%@' sectname='%@'",s,s.segmentName,s.sectionName);
    }
//    NSArray *classptrs = machoReader.classPointers;
    MPWMachOSection *classnameSection=[machoReader objcClassNameSection];
    EXPECTNOTNIL(classnameSection, @"have a class name section");
    INTEXPECT( [classnameSection strings].count, 1, @"Objective-C classname");
//    INTEXPECT( classptrs.count, 1,@"number of classes");
//    MPWMachORelocationPointer *classptr = classptrs.firstObject;
//    MPWMachOClassReader *classreader=[[[self alloc] initWithPointer:machoReader.classPointers[0]] autorelease];
}


+(NSArray*)testSelectors
{
   return @[
       @"testCanWriteHeader",
       @"testCanWriteStringsToStringTable",
       @"testCanWriteGlobalSymboltable",
//       @"testWriteLinkableAddFunction",
       @"testWriteFunctionWithRelocationEntries",
       @"testWriteClass",
		];
}

@end
