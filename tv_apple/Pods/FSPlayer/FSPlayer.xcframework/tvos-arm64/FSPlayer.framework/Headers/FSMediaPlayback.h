/*
 * FSMediaPlayback.h
 *
 * Copyright (c) 2013 Bilibili
 * Copyright (c) 2013 Zhang Rui <bbcallen@gmail.com>
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
#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
typedef NSView UIView;
#endif
#import <FSPlayer/FSVideoRenderingProtocol.h>
#import <FSPlayer/ff_subtitle_preference.h>

typedef NS_ENUM(NSInteger, FSPlayerPlaybackState) {
    FSPlayerPlaybackStateStopped,
    FSPlayerPlaybackStatePlaying,
    FSPlayerPlaybackStatePaused,
    FSPlayerPlaybackStateInterrupted,
    FSPlayerPlaybackStateSeekingForward,
    FSPlayerPlaybackStateSeekingBackward
};

typedef NS_ENUM(NSInteger, FSPlayerPlaybackSchedule) {
    FSPlayerPlaybackScheduleIdle = 0,
    FSPlayerPlaybackScheduleInitialized,
    FSPlayerPlaybackSchedulePreparing,
    FSPlayerPlaybackSchedulePrepared,
    FSPlayerPlaybackScheduleStarted,
    FSPlayerPlaybackSchedulePaused,
    FSPlayerPlaybackScheduleCompleted,
    FSPlayerPlaybackScheduleStopped,
    FSPlayerPlaybackScheduleError
};

typedef NS_OPTIONS(NSUInteger, FSPlayerLoadState) {
    FSPlayerLoadStateUnknown        = 0,
    FSPlayerLoadStatePlayable       = 1 << 0,
    FSPlayerLoadStatePlaythroughOK  = 1 << 1, // Playback will be automatically started in this state when shouldAutoplay is YES
    FSPlayerLoadStateStalled        = 1 << 2, // Playback will be automatically paused in this state, if started
};

typedef NS_ENUM(NSInteger, FSFinishReason) {
    FSFinishReasonPlaybackEnded,
    FSFinishReasonPlaybackError,
    FSFinishReasonUserExited
};

typedef enum FSAudioChannel {
    FSAudioChannelStereo = 0,
    FSAudioChannelRight = 1,
    FSAudioChannelLeft = 2
} FSAudioChannel;

@protocol FSMediaPlayback;

#pragma mark FSMediaPlayback

@protocol FSMediaPlayback <NSObject>

- (NSURL *)contentURL __deprecated_msg("Use -content instead");
- (NSString *)content;
- (void)prepareToPlay;

- (void)play;
- (void)pause;
- (void)stop;
- (BOOL)isPlaying;
- (void)shutdown;
#if TARGET_OS_IOS
- (void)setPauseInBackground:(BOOL)pause;
#endif
//PS:外挂字幕，最多可挂载512个。
//挂载并激活字幕；本地网络均可
- (BOOL)loadThenActiveSubtitle:(NSURL*)url;
//仅挂载不激活字幕；本地网络均可
- (BOOL)loadSubtitleOnly:(NSURL*)url;
//批量挂载不激活字幕；本地网络均可
- (BOOL)loadSubtitlesOnly:(NSArray<NSURL*>*)urlArr;

@property(nonatomic, readonly)  UIView <FSVideoRenderingProtocol>*view;
@property(nonatomic)            NSTimeInterval currentPlaybackTime;
//音频额外延迟，供用户调整
@property(nonatomic)            float currentAudioExtraDelay;
//字幕额外延迟，供用户调整
@property(nonatomic)            float currentSubtitleExtraDelay;
//单位：ms
@property(nonatomic, readonly)  NSTimeInterval duration;
//单位：s
@property(nonatomic, readonly)  NSTimeInterval playableDuration;
@property(nonatomic, readonly)  NSInteger bufferingProgress;

@property(nonatomic, readonly)  BOOL isPreparedToPlay;
@property(nonatomic, readonly)  FSPlayerPlaybackState playbackState;
@property(nonatomic, readonly)  FSPlayerPlaybackSchedule playbackSchedule;
@property(nonatomic, readonly)  FSPlayerLoadState loadState;
@property(nonatomic, readonly) int isSeekBuffering;
@property(nonatomic, readonly) int isAudioSync;
@property(nonatomic, readonly) int isVideoSync;

@property(nonatomic, readonly) int64_t numberOfBytesTransferred;

@property(nonatomic, readonly) CGSize naturalSize;
@property(nonatomic, readonly) NSInteger videoZRotateDegrees;

@property(nonatomic) FSScalingMode scalingMode;
@property(nonatomic) BOOL shouldAutoplay;

@property (nonatomic) BOOL allowsMediaAirPlay;
@property (nonatomic) BOOL isDanmakuMediaAirPlay;
@property (nonatomic, readonly) BOOL airPlayMediaActive;

@property (nonatomic) float playbackRate;
//from 0.0 to 1.0
@property (nonatomic) float playbackVolume;

@property (nonatomic) int playbackLoop;

#if TARGET_OS_IOS
- (UIImage *)thumbnailImageAtCurrentTime;
#endif

//subtitle preference
@property(nonatomic) FSSubtitlePreference subtitlePreference;
//load spped (byte)
- (int64_t)currentDownloadSpeed;

- (void)exchangeSelectedStream:(int)streamIdx;
// FS_VAL_TYPE__VIDEO, FS_VAL_TYPE__AUDIO, FS_VAL_TYPE__SUBTITLE
- (void)closeCurrentStream:(NSString *)streamType;
- (void)enableAccurateSeek:(BOOL)open;
- (void)stepToNextFrame;
- (FSAudioChannel)getAudioChanne;
- (void)setAudioChannel:(FSAudioChannel)config;
- (NSArray <NSString *> *)getInputFormatExtensions;
- (int)startFastRecord:(NSString *)filePath;
- (int)stopFastRecord;
- (int)startExactRecord:(NSString *)filePath;
- (int)stopExactRecord;
//get video - master diff
- (float)currentVMDiff;
#pragma mark Notifications

#ifdef __cplusplus
#define FS_EXTERN extern "C" __attribute__((visibility ("default")))
#else
#define FS_EXTERN extern __attribute__((visibility ("default")))
#endif

// -----------------------------------------------------------------------------
//  MPMediaPlayback.h

// Posted when the prepared state changes of an object conforming to the MPMediaPlayback protocol changes.
// This supersedes MPMoviePlayerContentPreloadDidFinishNotification.
FS_EXTERN NSString *const FSPlayerIsPreparedToPlayNotification;

// -----------------------------------------------------------------------------
//  MPMoviePlayerController.h
//  Movie Player Notifications

// Posted when the scaling mode changes.
FS_EXTERN NSString* const FSPlayerScalingModeDidChangeNotification;

// Posted when movie playback ends or a user exits playback.
FS_EXTERN NSString* const FSPlayerDidFinishNotification;
FS_EXTERN NSString* const FSPlayerDidFinishReasonUserInfoKey; // NSNumber (FSFinishReason)

// Posted when the playback state changes, either programatically or by the user.
FS_EXTERN NSString* const FSPlayerPlaybackStateDidChangeNotification;

// Posted when the network load state changes.
FS_EXTERN NSString* const FSPlayerLoadStateDidChangeNotification;

// Posted when the movie player begins or ends playing video via AirPlay.
FS_EXTERN NSString* const FSPlayerIsAirPlayVideoActiveDidChangeNotification;

// Posted when the buffering changes.
FS_EXTERN NSString* const FSPlayerBufferingDidChangeNotification;

// Posted when the current playback time changes.
FS_EXTERN NSString* const FSPlayerCurrentPlaybackTimeDidChangeNotification;

// -----------------------------------------------------------------------------
// Movie Property Notifications

// Calling -prepareToPlay on the movie player will begin determining movie properties asynchronously.
// These notifications are posted when the associated movie property becomes available.
FS_EXTERN NSString* const FSPlayerNaturalSizeAvailableNotification;

//video's z rotate degrees
FS_EXTERN NSString* const FSPlayerZRotateAvailableNotification;
FS_EXTERN NSString* const FSPlayerNoCodecFoundNotification;
// -----------------------------------------------------------------------------
//  Extend Notifications

FS_EXTERN NSString *const FSPlayerVideoDecoderOpenNotification;
FS_EXTERN NSString *const FSPlayerFirstVideoFrameRenderedNotification;
FS_EXTERN NSString *const FSPlayerFirstAudioFrameRenderedNotification;
FS_EXTERN NSString *const FSPlayerFirstAudioFrameDecodedNotification;
FS_EXTERN NSString *const FSPlayerFirstVideoFrameDecodedNotification;
FS_EXTERN NSString *const FSPlayerOpenInputNotification;
FS_EXTERN NSString *const FSPlayerFindStreamInfoNotification;
FS_EXTERN NSString *const FSPlayerComponentOpenNotification;

FS_EXTERN NSString *const FSPlayerDidSeekCompleteNotification;
FS_EXTERN NSString *const FSPlayerDidSeekCompleteTargetKey;
FS_EXTERN NSString *const FSPlayerDidSeekCompleteErrorKey;
FS_EXTERN NSString *const FSPlayerDidAccurateSeekCompleteCurPos;
FS_EXTERN NSString *const FSPlayerAccurateSeekCompleteNotification;
FS_EXTERN NSString *const FSPlayerSeekAudioStartNotification;
FS_EXTERN NSString *const FSPlayerSeekVideoStartNotification;

FS_EXTERN NSString *const FSPlayerSelectedStreamDidChangeNotification;
FS_EXTERN NSString *const FSPlayerAfterSeekFirstVideoFrameDisplayNotification;
//when received this fatal notifi,need stop player,otherwize read frame and play to end.
FS_EXTERN NSString *const FSPlayerVideoDecoderFatalNotification; /*useinfo's code is decoder's err code.*/
FS_EXTERN NSString *const FSPlayerRecvWarningNotification; /*warning notifi.*/
FS_EXTERN NSString *const FSPlayerWarningReasonUserInfoKey; /*useinfo's key,value is int.*/
//user info's state key:1 means begin,2 means end.
FS_EXTERN NSString *const FSPlayerHDRAnimationStateChanged;
//select stream failed user info key
FS_EXTERN NSString *const FSPlayerSelectingStreamIDUserInfoKey;
//pre selected stream user info key
FS_EXTERN NSString *const FSPlayerPreSelectingStreamIDUserInfoKey;
//select stream failed err code key
FS_EXTERN NSString *const FSPlayerSelectingStreamErrUserInfoKey;
//select stream failed.
FS_EXTERN NSString *const FSPlayerSelectingStreamDidFailed;
//icy meta changed.
FS_EXTERN NSString *const FSPlayerICYMetaChangedNotification;

@end

#pragma mark FSMediaUrlOpenDelegate

// Must equal to the defination in ijkavformat/ijkavformat.h
typedef NS_ENUM(NSInteger, FSMediaEvent) {

    // Notify Events
    FSMediaEvent_WillHttpOpen         = 1,       // attr: url
    FSMediaEvent_DidHttpOpen          = 2,       // attr: url, error, http_code
    FSMediaEvent_WillHttpSeek         = 3,       // attr: url, offset
    FSMediaEvent_DidHttpSeek          = 4,       // attr: url, offset, error, http_code
    // Control Message
    FSMediaCtrl_WillTcpOpen           = 0x20001, // FSMediaUrlOpenData: no args
    FSMediaCtrl_DidTcpOpen            = 0x20002, // FSMediaUrlOpenData: error, family, ip, port, fd
    FSMediaCtrl_WillHttpOpen          = 0x20003, // FSMediaUrlOpenData: url, segmentIndex, retryCounter
    FSMediaCtrl_WillLiveOpen          = 0x20005, // FSMediaUrlOpenData: url, retryCounter
    FSMediaCtrl_WillConcatSegmentOpen = 0x20007, // FSMediaUrlOpenData: url, segmentIndex, retryCounter
};

#define FSMediaEventAttrKey_url            @"url"
#define FSMediaEventAttrKey_host           @"host"
#define FSMediaEventAttrKey_error          @"error"
#define FSMediaEventAttrKey_time_of_event  @"time_of_event"
#define FSMediaEventAttrKey_http_code      @"http_code"
#define FSMediaEventAttrKey_offset         @"offset"
#define FSMediaEventAttrKey_file_size      @"file_size"

// event of FSMediaUrlOpenEvent_xxx
@interface FSMediaUrlOpenData: NSObject

- (id)initWithUrl:(NSString *)url
            event:(FSMediaEvent)event
     segmentIndex:(int)segmentIndex
     retryCounter:(int)retryCounter;

@property(nonatomic, readonly) FSMediaEvent event;
@property(nonatomic, readonly) int segmentIndex;
@property(nonatomic, readonly) int retryCounter;

@property(nonatomic, retain) NSString *url;
@property(nonatomic, assign) int fd;
@property(nonatomic, strong) NSString *msg;
@property(nonatomic) int error; // set a negative value to indicate an error has occured.
@property(nonatomic, getter=isHandled)    BOOL handled;     // auto set to YES if url changed
@property(nonatomic, getter=isUrlChanged) BOOL urlChanged;  // auto set to YES by url changed

@end

@protocol FSMediaUrlOpenDelegate <NSObject>

- (void)willOpenUrl:(FSMediaUrlOpenData*) urlOpenData;

@end

@protocol FSMediaNativeInvokeDelegate <NSObject>

- (int)invoke:(FSMediaEvent)event attributes:(NSDictionary *)attributes;

@end
