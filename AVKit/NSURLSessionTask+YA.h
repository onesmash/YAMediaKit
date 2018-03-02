//
//  NSURLSessionTask+YA.h
//  YAMediaKitDemo
//
//  Created by 徐晖 on 2018/3/2.
//  Copyright © 2018年 徐晖. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface NSURLSessionTask (YA)

@property (nonatomic, strong) AVAssetResourceLoadingRequest *ya_AVAssetResourceLoadingRequest;
@property (nonatomic, assign) NSRange ya_range;

@end
