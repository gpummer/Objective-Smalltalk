//
//  MPWMachOReader.h
//  ObjSTNative
//
//  Created by Marcel Weiher on 09.09.22.
//

#import <MPWFoundation/MPWFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MPWMachOReader : NSObject

-(instancetype)initWithData:(NSData*)machodata;
-(BOOL)isHeaderValid;
-(int)filetype;
-(int)cputype;
-(int)numLoadCommands;
-(NSArray<NSString*>*)stringTable;
-(int)numSymbols;

-(NSString*)symbolNameAt:(int)which;
-(long)symbolOffsetAt:(int)which;
-(bool)isSymbolGlobalAt:(int)which;
-(NSData*)textSection;

@end

NS_ASSUME_NONNULL_END
