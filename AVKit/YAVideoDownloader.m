//
//  YAVideoDownloader.m
//  YAMediaKitDemo
//
//  Created by 徐晖 on 2018/3/2.
//  Copyright © 2018年 徐晖. All rights reserved.
//

#import "YAVideoDownloader.h"
#import "NSURLSessionTask+YA.h"
#import <YAKit/YAMMapFile.h>
#import <YAKit/YAKit.h>
#import <MobileCoreServices/MobileCoreServices.h>

@interface NSHTTPURLResponse (VideoCache)
- (long long)ya_videoSize;
- (NSString *)ya_contentType;
@end

@implementation NSHTTPURLResponse (VideoCache)
- (long long)ya_videoSize
{
    NSString *range = [[self allHeaderFields] objectForKey:@"Content-Range"];
    if (range) {
        NSArray *ranges = [range componentsSeparatedByString:@"/"];
        if (ranges.count > 0) {
            NSString *lengthString = [[ranges lastObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            return [lengthString longLongValue];
        }
    } else {
        return [self expectedContentLength];
    }
    return 0;
}

- (NSString *)ya_contentType
{
    NSString *mimeType = [self MIMEType];
    CFStringRef contentType = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, (__bridge CFStringRef)(mimeType), NULL);
    return CFBridgingRelease(contentType);
}
@end

@protocol YAVideoMeta <NSObject>
@property (nonatomic, assign) NSInteger size;
@property (nonatomic, copy) NSString *contentType;
@end

@interface YAVideoMeta : YAModel <YAVideoMeta>

@end

@implementation YAVideoMeta
@synthesize size;
@synthesize contentType;

+ (void)registerAllKeyProtocols
{
    [self registerKeyProtocol:@protocol(YAVideoMeta)];
}

+ (YAVideoMeta *)videoMetaWithHTTPResponse:(NSHTTPURLResponse *)response
{
    YAVideoMeta *meta = [[YAVideoMeta alloc] init];
    meta.size = [response ya_videoSize];
    meta.contentType = [response ya_contentType];
    return meta;
    
}

@end

@protocol YAVideoDownloadMeta <NSObject>
@property (nonatomic, strong) NSMutableIndexSet *availableDataRange;
@property (nonatomic, strong) YAVideoMeta *videoMeta;
@end

@interface YAVideoDownloadMeta : YAModel <YAVideoDownloadMeta>

@end

@implementation YAVideoDownloadMeta
@synthesize availableDataRange;
@synthesize videoMeta;

+ (void)registerAllKeyProtocols
{
    [self registerKeyProtocol:@protocol(YAVideoDownloadMeta)];
}

@end

@interface YAVideoDownloader () <NSURLSessionDataDelegate>
@property (nonatomic, copy) NSString *metaFilePath;
@property (nonatomic, copy) NSString *tmpFilePath;
@property (nonatomic, copy) NSString *cacheFilePath;
@property (nonatomic, copy) NSString *cacheMetaFilePath;
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) YAVideoMeta *videoMeta;
@property (nonatomic, strong) YAMMapFile *mmapFile;
@property (nonatomic, strong) NSMutableIndexSet *availableDataRange;
@end

@implementation YAVideoDownloader



@end
