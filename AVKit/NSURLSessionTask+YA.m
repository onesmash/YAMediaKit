//
//  NSURLSessionTask+YA.m
//  YAMediaKitDemo
//
//  Created by 徐晖 on 2018/3/2.
//  Copyright © 2018年 徐晖. All rights reserved.
//

#import "NSURLSessionTask+YA.h"
#import <objc/runtime.h>

static char kAVAssetResourceLoadingRequestKey;
static char kDownloadRangeKey;

@implementation NSURLSessionTask (YA)

- (AVAssetResourceLoadingRequest *)ya_AVAssetResourceLoadingRequest
{
    return objc_getAssociatedObject(self, &kAVAssetResourceLoadingRequestKey);
}

- (void)setYa_AVAssetResourceLoadingRequest:(AVAssetResourceLoadingRequest *)ya_AVAssetResourceLoadingRequest
{
    objc_setAssociatedObject(self, &kAVAssetResourceLoadingRequestKey, ya_AVAssetResourceLoadingRequest, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSRange)ya_range
{
    NSValue *value = objc_getAssociatedObject(self, &kDownloadRangeKey);
    NSRange range;
    [value getValue:&range];
    return range;
}

- (void)setYa_range:(NSRange)ya_range
{
    objc_setAssociatedObject(self, &kDownloadRangeKey, [NSValue valueWithBytes:&ya_range objCType:@encode(NSRange)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
