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
#import <objc/runtime.h>

#define kPathSuffix @"YAMedia/Video"

static char kVideoDirKey;

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
    if(![AVURLAsset isPlayableExtendedMIMEType:mimeType]) {
        mimeType = @"video/mp4";
    }
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
@property (nonatomic, strong) NSURLSession *urlSession;
@property (nonatomic, strong) YAVideoMeta *videoMeta;
@property (nonatomic, strong) YAMMapFile *mmapFile;
@property (nonatomic, strong) NSMutableIndexSet *availableDataRange;
@property (nonatomic, copy) NSURL *URL;
@property (atomic, assign) BOOL stopped;
@end

@implementation YAVideoDownloader

+ (NSString *)videoDir
{
    return objc_getAssociatedObject(self, &kVideoDirKey);
}

+ (void)setVideoDir:(NSString *)videoDir
{
    objc_setAssociatedObject(self, &kVideoDirKey, videoDir, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

+ (NSString *)tmpFilePath:(NSURL *)URL
{
    NSString *videoDir = [NSTemporaryDirectory() stringByAppendingPathComponent:kPathSuffix];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:videoDir]) {
        [fileManager createDirectoryAtPath:videoDir
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];
    }
    return [videoDir stringByAppendingPathComponent:[URL.absoluteString ya_md5]];
}

+ (NSString *)tmpMetaFilePath:(NSURL *)URL
{
    return [[self tmpFilePath:URL] stringByAppendingPathExtension:@"meta"];
}

+ (NSString *)cacheFilePath:(NSURL *)URL
{
    NSString *videoDir = self.videoDir.length ? self.videoDir : [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:kPathSuffix];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:videoDir]) {
        [fileManager createDirectoryAtPath:videoDir
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];
    }
    return [videoDir stringByAppendingPathComponent:[URL.absoluteString ya_md5]];
}

+ (NSString *)cacheMetaFilePath:(NSURL *)URL
{
    return [[self cacheFilePath:URL] stringByAppendingPathExtension:@"meta"];
}

+ (NSArray<NSString *> *)cleanAbleDir
{
    return @[[NSTemporaryDirectory() stringByAppendingPathComponent:kPathSuffix], self.videoDir.length ? self.videoDir : [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:kPathSuffix]];
}

+ (void)cleanCache
{
    for (NSString *path in [self cleanAbleDir]) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
}

+ (instancetype)downloaderWithURL:(NSURL *)URL
{
    return [[YAVideoDownloader alloc] initWithURL:URL];
}

+ (NSOperationQueue *)operationQueue
{
    static NSOperationQueue *queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        queue.name = @"io.onesmash.mediakit.downloader";
    });
    return queue;
}

- (instancetype)initWithURL:(NSURL *)URL
{
    self = [self init];
    if(self) {
        _URL = URL;
        _availableDataRange = [NSMutableIndexSet indexSet];
        _videoMeta = [[YAVideoMeta alloc] init];
        _urlSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[self.class operationQueue]];
        _stopped = NO;
        [self prepareVideoCache];
    }
    return self;
}

- (void)dealloc
{
    [self.mmapFile close];
    NSString *tmpCacheFilePath = [self tmpFilePath];
    NSString *cacheFilePath = [self cacheFilePath];
    NSString *metaFilePath = self.cacheMetaFilePath;
    NSString *tmpCacheMetaFilePath = [self tmpMetaFilePath];
    NSMutableIndexSet *availableDataRange = self.availableDataRange;
    YAVideoMeta *videoMeta = self.videoMeta;
    BOOL isDownloadFinished = self.videoMeta.size > 0 ? [self.availableDataRange containsIndexesInRange:NSMakeRange(0, self.videoMeta.size)] : NO;
    dispatch_async(dispatch_get_global_queue(0, 0), ^() {
        if(isDownloadFinished && (![[NSFileManager defaultManager] fileExistsAtPath:metaFilePath] || ![[NSFileManager defaultManager] fileExistsAtPath:cacheFilePath])) {
            [[NSFileManager defaultManager] copyItemAtPath:tmpCacheFilePath toPath:cacheFilePath error:nil];
            [NSKeyedArchiver archiveRootObject:videoMeta toFile:metaFilePath];
        }
        if(![[NSFileManager defaultManager] fileExistsAtPath:metaFilePath] || ![[NSFileManager defaultManager] fileExistsAtPath:cacheFilePath]) {
            YAVideoDownloadMeta *meta = [[YAVideoDownloadMeta alloc] init];
            meta.availableDataRange = availableDataRange;
            meta.videoMeta = videoMeta;
            [NSKeyedArchiver archiveRootObject:meta toFile:tmpCacheMetaFilePath];
        }
    });
    
}

- (void)stop
{
    self.stopped = YES;
    [self.urlSession invalidateAndCancel];
}

- (NSString *)tmpFilePath
{
    return [self.class tmpFilePath:self.URL];
}

- (NSString *)tmpMetaFilePath
{
    return [self.class tmpMetaFilePath:self.URL];
}

- (NSString *)cacheFilePath
{
    return [self.class cacheFilePath:self.URL];
}

- (NSString *)cacheMetaFilePath
{
    return [self.class cacheMetaFilePath:self.URL];
}

- (void)updateLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest withVideoMeta:(YAVideoMeta *)meta
{
    loadingRequest.contentInformationRequest.byteRangeAccessSupported = YES;
    loadingRequest.contentInformationRequest.contentType = meta.contentType;
    loadingRequest.contentInformationRequest.contentLength = meta.size;
}

- (void)updatePendingRequest:(NSURLSessionDataTask *)dataTask recvRange:(NSRange)range
{
    dataTask.ya_range = NSMakeRange(range.location + range.length, dataTask.ya_range.length - range.length);
}

- (void)updatePendingRequest:(NSURLSessionDataTask *)dataTask responseData:(NSData *)data
{
    AVAssetResourceLoadingRequest *loadingRequest = dataTask.ya_AVAssetResourceLoadingRequest;
    NSRange range = NSMakeRange(dataTask.ya_range.location, data.length);
    [self updatePendingRequest:dataTask recvRange:range];
    [self.mmapFile write:(const char*)data.bytes size:range.length offset:range.location];
    [self.availableDataRange addIndexesInRange:range];
    NSRange requestRange = [self requestRange:loadingRequest];
    NSMutableIndexSet *requestIndexSet = [NSMutableIndexSet indexSetWithIndexesInRange:requestRange];
    [requestIndexSet removeIndexes:self.availableDataRange];
    NSUInteger endIndex = requestIndexSet.firstIndex;
    if(endIndex == NSNotFound) {
        endIndex = requestRange.location + requestRange.length;
    }
    if(endIndex > loadingRequest.dataRequest.currentOffset) {
        NSUInteger size = endIndex - loadingRequest.dataRequest.currentOffset;
        const char* cacheData = [self.mmapFile read:size offset:loadingRequest.dataRequest.currentOffset];
        NSData *data = [NSData dataWithBytes:cacheData length:size];
        [loadingRequest.dataRequest respondWithData:data];
        if([self.availableDataRange containsIndexesInRange:NSMakeRange(0, self.videoMeta.size)]) {
            [self stop];
            [self.mmapFile flush:YES];
        }
    }
}

#pragma mark - Util

- (void)prepareVideoCache
{
    [self.class.operationQueue addOperationWithBlock:^() {
        if([[NSFileManager defaultManager] fileExistsAtPath:self.cacheFilePath] && [[NSFileManager defaultManager] fileExistsAtPath:self.cacheMetaFilePath]) {
            self.videoMeta = [NSKeyedUnarchiver unarchiveObjectWithFile:self.cacheMetaFilePath];
            _mmapFile = [[YAMMapFile alloc] initWithFilePath:self.cacheFilePath size:self.videoMeta.size openMode:YAMMapFileOpenModeRead];
            [self.availableDataRange addIndexesInRange:NSMakeRange(0, self.videoMeta.size)];
        } else if([[NSFileManager defaultManager] fileExistsAtPath:self.tmpFilePath] && [[NSFileManager defaultManager] fileExistsAtPath:self.tmpMetaFilePath]) {
            YAVideoDownloadMeta *meta = [NSKeyedUnarchiver unarchiveObjectWithFile:self.tmpMetaFilePath];
            if(meta.videoMeta.size > 0) {
                self.videoMeta = meta.videoMeta;
                self.availableDataRange = meta.availableDataRange;
                _mmapFile = [[YAMMapFile alloc] initWithFilePath:self.tmpFilePath size:self.videoMeta.size openMode:YAMMapFileOpenModeWriteAppend];
            }
        }
    }];
}

- (void)createTmpFile:(size_t)size
{
    if(!_mmapFile) {
        _mmapFile = [[YAMMapFile alloc] initWithFilePath:self.tmpFilePath size:size openMode:YAMMapFileOpenModeWrite];
        self.videoMeta.size = size;
    } else if(size != _mmapFile.size) {
        _mmapFile = [[YAMMapFile alloc] initWithFilePath:self.tmpFilePath size:size openMode:YAMMapFileOpenModeWrite];
        self.videoMeta.size = size;
    }
}

- (NSURLRequest *)buildRequestWithAVAssetResourceLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest requestRange:(NSRange)requestRange
{
    NSString *orignalScheme = [loadingRequest.request.URL.scheme stringByReplacingOccurrencesOfString:kDownloaderSupportSchemeSuffix withString:@""];
    NSURLComponents *actualURLComponents = [[NSURLComponents alloc] initWithURL:loadingRequest.request.URL resolvingAgainstBaseURL:NO];
    actualURLComponents.scheme = orignalScheme;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:actualURLComponents.URL];
    request.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    request.allHTTPHeaderFields = loadingRequest.request.allHTTPHeaderFields;
    NSString *range = [NSString stringWithFormat:@"bytes=%@-%@", @(requestRange.location), @(requestRange.location + requestRange.length - 1)];
    [request setValue:range forHTTPHeaderField:@"Range"];
    return request;
}

- (void)responseLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest withCacheData:(NSRange)range
{
    NSData *data = [NSData dataWithBytes:(void *)(self.mmapFile.base + range.location) length:range.length];
    [loadingRequest.dataRequest respondWithData:data];
    [loadingRequest finishLoading];
}

- (NSRange)requestRange:(AVAssetResourceLoadingRequest *)loadingRequest
{
    NSInteger requestOffset = loadingRequest.dataRequest.requestedOffset;
    NSInteger requestLength;
    if(loadingRequest.dataRequest.requestedLength == NSIntegerMax || (@available(iOS 9, *) && loadingRequest.dataRequest.requestsAllDataToEndOfResource)) {
        requestLength = self.videoMeta.size ? self.videoMeta.size - requestOffset : NSIntegerMax;
    } else {
        requestLength = loadingRequest.dataRequest.requestedLength;
    }
    return NSMakeRange(requestOffset, requestLength);
}

#pragma mark - AVAssetResourceLoaderDelegate
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest
{
    [self.class.operationQueue addOperationWithBlock:^() {
        NSRange requestRange = [self requestRange:loadingRequest];
        if([self.availableDataRange containsIndexesInRange:requestRange]) {
            [self updateLoadingRequest:loadingRequest withVideoMeta:self.videoMeta];
            [self responseLoadingRequest:loadingRequest withCacheData:requestRange];
        } else {
            if(self.stopped) return;
            NSMutableIndexSet *requestIndexSet = [NSMutableIndexSet indexSetWithIndexesInRange:requestRange];
            [requestIndexSet removeIndexes:self.availableDataRange];
            [requestIndexSet enumerateRangesUsingBlock:^(NSRange range, BOOL *stop) {
                NSURLRequest *request = [self buildRequestWithAVAssetResourceLoadingRequest:loadingRequest requestRange:range];
                NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request];
                task.ya_AVAssetResourceLoadingRequest = loadingRequest;
                task.ya_range = range;
                [task resume];
            }];
        }
    }];
    return YES;
}

- (void)resourceLoader:(AVAssetResourceLoader *)resourceLoader didCancelLoadingRequest:(AVAssetResourceLoadingRequest *)loadingRequest
{
}

#pragma mark - NSURLSessionDataDelegate

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition disposition))completionHandler
{
    NSInteger statusCode = [(NSHTTPURLResponse *)response statusCode];
    if(statusCode == 206 || statusCode == 200) {
        self.videoMeta = [YAVideoMeta videoMetaWithHTTPResponse:(NSHTTPURLResponse *)response];
        [self createTmpFile:self.videoMeta.size];
        dataTask.ya_AVAssetResourceLoadingRequest.response = response;
        [self updateLoadingRequest:dataTask.ya_AVAssetResourceLoadingRequest withVideoMeta:self.videoMeta];
    }
    completionHandler(NSURLSessionResponseAllow);
    if(dataTask.ya_AVAssetResourceLoadingRequest.isCancelled) {
        [dataTask cancel];
    }
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask
    didReceiveData:(NSData *)data
{
    [self updatePendingRequest:dataTask responseData:data];
    BOOL isFinished = NO;
    AVAssetResourceLoadingDataRequest *dataRequest = dataTask.ya_AVAssetResourceLoadingRequest.dataRequest;
    if(!(dataRequest.requestedLength == NSIntegerMax || (@available(iOS 9, *) && dataRequest.requestsAllDataToEndOfResource))) {
        isFinished = dataRequest.currentOffset >= dataRequest.requestedOffset + dataRequest.requestedLength;
    } else {
        isFinished = dataRequest.currentOffset >= self.videoMeta.size;
    }
    if(isFinished) {
        [dataTask.ya_AVAssetResourceLoadingRequest finishLoading];
        dataTask.ya_AVAssetResourceLoadingRequest = nil;
    }
    if(dataTask.ya_AVAssetResourceLoadingRequest.isCancelled) {
        [dataTask cancel];
    }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionDataTask *)dataTask
didCompleteWithError:(nullable NSError *)error
{
    if(dataTask.ya_AVAssetResourceLoadingRequest.isCancelled) return;
    if(error) {
        [dataTask.ya_AVAssetResourceLoadingRequest finishLoadingWithError:error];
    } else {
        [dataTask.ya_AVAssetResourceLoadingRequest finishLoading];
    }
    dataTask.ya_AVAssetResourceLoadingRequest = nil;
}

@end
