//
//  YAVideoDownloader.h
//  YAMediaKitDemo
//
//  Created by 徐晖 on 2018/3/2.
//  Copyright © 2018年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#define kDownloaderSupportSchemeSuffix @"-stream"

@interface YAVideoDownloader : NSObject <AVAssetResourceLoaderDelegate>
@property (class, nonatomic, copy) NSString *videoDir;
@property (class, nonatomic, strong, readonly) NSOperationQueue *operationQueue;
+ (NSArray<NSString *> *)cleanAbleDir;
+ (void)cleanCache;
+ (instancetype)downloaderWithURL:(NSURL *)URL;

- (void)stop;

@end
