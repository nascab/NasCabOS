/*
 * FSAudioRenderingProtocol.h
 *
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

#ifndef FSAudioRenderingProtocol_h
#define FSAudioRenderingProtocol_h

#import <Foundation/Foundation.h>

#define FSAudioSpecS16      0x8010  /**< Signed 16-bit samples */

typedef void (*FSAudioCallback) (void *userdata, uint8_t * stream, int len);

@interface FSAudioSpec : NSObject

@property (nonatomic, assign) int freq;                   /**< DSP frequency -- samples per second */
@property (nonatomic, assign) uint16_t format;            /**< Audio data format */
@property (nonatomic, assign) uint8_t channels;           /**< Number of channels: 1 mono, 2 stereo */
@property (nonatomic, assign) uint8_t silence;            /**< Audio buffer silence value (calculated) */
@property (nonatomic, assign) uint16_t samples;           /**< Audio buffer size in samples (power of 2) */
@property (nonatomic, assign) uint16_t padding;           /**< NOT USED. Necessary for some compile environments */
@property (nonatomic, assign) uint32_t size;              /**< Audio buffer size in bytes (calculated) */
@property (nonatomic, assign) FSAudioCallback callback;
@property (nonatomic, assign) void *userdata;

@end

@protocol FSAudioRenderingProtocol <NSObject>

- (BOOL)isSupportAudioSpec:(FSAudioSpec *)aSpec err:(NSError **)outErr;
- (void)play;
- (void)pause;
- (void)flush;
- (void)stop;
- (void)close;
- (void)setPlaybackRate:(float)playbackRate;
- (void)setPlaybackVolume:(float)playbackVolume;
- (double)get_latency_seconds;

@property (nonatomic, readonly) FSAudioSpec * spec;
@property (nonatomic, assign) BOOL automaticallySetupAudioSession;

@end

#endif /* FSAudioRenderingProtocol_h */
