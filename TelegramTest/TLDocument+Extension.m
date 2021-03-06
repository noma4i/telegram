//
//  TLDocument+Extension.m
//  Telegram
//
//  Created by keepcoder on 15.12.14.
//  Copyright (c) 2014 keepcoder. All rights reserved.
//

#import "TLDocument+Extension.h"

@implementation TLDocument (Extensions)

-(NSString *)file_name {
    
    __block NSString *fileName = @"";
    
    [self.attributes enumerateObjectsUsingBlock:^(TLDocumentAttribute *obj, NSUInteger idx, BOOL *stop) {
        
        if([obj isKindOfClass:[TL_documentAttributeFilename class]]) {
            fileName = obj.file_name;
            *stop = YES;
        }
        
    }];
    
    return fileName;
}

-(BOOL)isSticker {
    __block BOOL isSticker = NO;
    
    [self.attributes enumerateObjectsUsingBlock:^(TLDocumentAttribute *obj, NSUInteger idx, BOOL *stop) {
        
        if([obj isKindOfClass:[TL_documentAttributeSticker class]]) {
            isSticker = YES;
            *stop = YES;
        }
        
    }];
    
    return isSticker;
}
-(NSSize)imageSize {
    __block NSSize size = NSZeroSize;
    
    [self.attributes enumerateObjectsUsingBlock:^(TLDocumentAttribute *obj, NSUInteger idx, BOOL *stop) {
        
        if([obj isKindOfClass:[TL_documentAttributeImageSize class]]) {
            size = NSMakeSize(obj.w,obj.h);
            *stop = YES;
        }
        
    }];
    
    return size;
}

-(BOOL)isExist {
    return self.n_id != 0 && self.access_hash != 0;
}

@end
