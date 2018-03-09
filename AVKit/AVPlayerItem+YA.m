//
//  AVPlayerItem+YA.m
//  YAMediaKitDemo
//
//  Created by 徐晖 on 2018/3/2.
//  Copyright © 2018年 徐晖. All rights reserved.
//

#import "AVPlayerItem+YA.h"
#import "YAVideoDownloader.h"
#import <YAKit/NSObject+YASwizzle.h>
#import <objc/runtime.h>

static char kDownloaderKey;

@implementation AVPlayerItem (YA)

+ (void)load
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self ya_swizzleMethod:NSSelectorFromString(@"dealloc") withMethod:@selector(AVPlayerItem_dealloc)];
    });
}

+ (instancetype)ya_playerItemWithURL:(NSURL *)URL
{
    if([URL.scheme.lowercaseString hasPrefix:@"http"]) {
        NSURLComponents *cacheSupportURLComponents = [[NSURLComponents alloc] initWithURL:URL resolvingAgainstBaseURL:NO];
        cacheSupportURLComponents.scheme = [NSString stringWithFormat:@"%@%@", cacheSupportURLComponents.scheme, kDownloaderSupportSchemeSuffix];
        YAVideoDownloader *downloader = [YAVideoDownloader downloaderWithURL:cacheSupportURLComponents.URL];
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:cacheSupportURLComponents.URL options:nil];
        [asset.resourceLoader setDelegate:downloader queue:dispatch_get_main_queue()];
        AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
        item.ya_downloader = downloader;
        return item;
    } else {
        return [AVPlayerItem playerItemWithURL:URL];
    }
}

- (void)AVPlayerItem_dealloc
{
    [self.ya_downloader stop];
    [self AVPlayerItem_dealloc];
}

- (YAVideoDownloader *)ya_downloader
{
    return objc_getAssociatedObject(self, &kDownloaderKey);
}

- (void)setYa_downloader:(YAVideoDownloader *)ya_downloader
{
    objc_setAssociatedObject(self, &kDownloaderKey, ya_downloader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end
