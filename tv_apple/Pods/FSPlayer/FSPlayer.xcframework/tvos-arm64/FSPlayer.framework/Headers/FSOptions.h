/*
 * FSOptions.h
 *
 * Copyright (c) 2013-2015 Bilibili
 * Copyright (c) 2013-2015 Zhang Rui <bbcallen@gmail.com>
 * Copyright (c) 2019 debugly <qianlongxu@gmail.com>
 *
 * This file is part of FSPlayer.
 *
 * FSPlayer is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 3 of the License, or (at your option) any later version.
 *
 * FSPlayer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with FSPlayer; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
 */

#import <Foundation/Foundation.h>

typedef enum FSOptionCategory {
    kIJKFFOptionCategoryFormat = 1,
    kIJKFFOptionCategoryCodec  = 2,
    kIJKFFOptionCategorySws    = 3,
    kIJKFFOptionCategoryPlayer = 4,
    kIJKFFOptionCategorySwr    = 5,
} FSOptionCategory;

struct IjkMediaPlayer;

NS_ASSUME_NONNULL_BEGIN

@interface FSOptions : NSObject

+ (FSOptions *)optionsByDefault;

- (void)applyTo:(struct IjkMediaPlayer *)mediaPlayer;

- (void)setOptionValue:(NSString * _Nullable)value
                forKey:(NSString *)key
            ofCategory:(FSOptionCategory)category;

- (void)setOptionIntValue:(int64_t)value
                   forKey:(NSString *)key
               ofCategory:(FSOptionCategory)category;


- (void)setFormatOptionValue:       (NSString * _Nullable)value forKey:(NSString *)key;
- (void)setCodecOptionValue:        (NSString * _Nullable)value forKey:(NSString *)key;
- (void)setSwsOptionValue:          (NSString * _Nullable)value forKey:(NSString *)key;
- (void)setPlayerOptionValue:       (NSString * _Nullable)value forKey:(NSString *)key;

- (void)setFormatOptionIntValue:    (int64_t)value forKey:(NSString *)key;
- (void)setCodecOptionIntValue:     (int64_t)value forKey:(NSString *)key;
- (void)setSwsOptionIntValue:       (int64_t)value forKey:(NSString *)key;
- (void)setPlayerOptionIntValue:    (int64_t)value forKey:(NSString *)key;

@property(nonatomic) BOOL showHudView;
//default is auto; you can set to NO means force use opengl.
@property(nonatomic) BOOL metalRenderer;
//append extra protocol whitelist
@property(nonatomic, copy) NSString *protocolWhitelist;
//setup audio session use AVAudioSessionCategoryPlayback, observer and handle interrupt event on iOS platform
@property(nonatomic) BOOL automaticallySetupAudioSession;
//default is 0, when the value is 0, it is not turned on.
@property(nonatomic) NSTimeInterval currentPlaybackTimeNotificationInterval API_AVAILABLE(macosx(10.12), ios(10.0), watchos(3.0), tvos(10.0));

@end
NS_ASSUME_NONNULL_END
