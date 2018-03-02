//
//  AVPlayerItem+YA.h
//  YAMediaKitDemo
//
//  Created by 徐晖 on 2018/3/2.
//  Copyright © 2018年 徐晖. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "YAVideoDownloader.h"

@interface AVPlayerItem (YA)

@property (nonatomic, strong) YAVideoDownloader *ya_downloader;

+ (instancetype)ya_playerItemWithURL:(NSURL *)URL;

@end
