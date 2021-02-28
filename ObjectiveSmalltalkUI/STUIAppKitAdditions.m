//
//  STUIAppKitAdditions.m
//  ObjectiveSmalltalkUI
//
//  Created by Marcel Weiher on 28.02.21.
//

#import <AppKit/AppKit.h>
#import <ObjectiveSmalltalk/ObjectiveSmalltalk.h>



@implementation NSTextField(debug)

-(void)dumpOn:(MPWByteStream*)aStream
{
    [aStream printFormat:@"<%s:%p: ",object_getClassName(self),self];
    [aStream printFormat:@"frame: %@ ",NSStringFromRect(self.frame)];
    [aStream printFormat:@"stringValue: %@ ",self.stringValue];
    [aStream printFormat:@"textColor: %@ ",self.textColor];
    [aStream printFormat:@"backGroundColor: %@ ",self.backgroundColor];
    [aStream printFormat:@"drawsBackground: %d ",self.drawsBackground];
    [aStream printFormat:@"isBordered: %d ",self.isBordered];
    [aStream printFormat:@"isSelectable: %d ",self.isSelectable];
    [aStream printFormat:@"isOpaque: %d",self.isOpaque];
    
    [aStream printFormat:@">\n"];
}



@end


@implementation NSControl(streaming)

-defaultInputPort
{
    return [[[STMessagePortDescriptor alloc] initWithTarget:self key:nil protocol:@protocol(Streaming) sends:NO] autorelease];
}


-(void)writeObject:anObject
{
    self.objectValue = anObject;
}

-(void)writeTarget:(NSControl*)source
{
    self.objectValue = [source objectValue];
}

-(void)appendBytes:(const void*)bytes length:(long)len
{
    self.stringValue = [NSString stringWithCString:bytes length:len];
}

@end

@implementation NSGridView(sizeandviews)

+gridViewWithSize:(NSSize)size views:views {
    NSGridView *grid = [self gridViewWithViews:views];
    [grid setFrameSize:size];
    return grid;
}

@end
