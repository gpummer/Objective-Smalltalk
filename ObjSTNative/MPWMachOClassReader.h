//
//  MPWMachOClassReader.h
//  ObjSTNative
//
//  Created by Marcel Weiher on 08.10.22.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class MPWMachOReader,MPWMachORelocationPointer;

@interface MPWMachOClassReader : NSObject

-(instancetype)initWithReader:(MPWMachOReader*)reader;
-(NSArray<MPWMachORelocationPointer*>*)classes;

@end

NS_ASSUME_NONNULL_END
