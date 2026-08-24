/*
 * FSVideoRenderingProtocol.h
 *
 * Copyright (c) 2017 Bilibili
 * Copyright (c) 2017 raymond <raymondzheng1412@gmail.com>
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

#ifndef FSVideoRenderingProtocol_h
#define FSVideoRenderingProtocol_h

#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#import <CoreGraphics/CGImage.h>
typedef NSFont UIFont;
typedef NSColor UIColor;
typedef NSImage UIImage;
typedef NSView UIView;
#else
#import <UIKit/UIKit.h>
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FSScalingMode) {
    FSScalingModeAspectFit,  // Uniform scale until one dimension fits
    FSScalingModeAspectFill, // Uniform scale until the movie fills the visible bounds. One dimension may have clipped contents
    FSScalingModeFill        // Non-uniform scale. Both render dimensions will exactly match the visible bounds
};

typedef struct SDL_TextureOverlay SDL_TextureOverlay;
@interface FSOverlayAttach : NSObject

//{w,h} is video frame normal size not alignmetn,maybe not equal to {pixelW,pixelH}.
@property(nonatomic) int w;
@property(nonatomic) int h;
//cvpixebuffer pixel memory size;
@property(nonatomic) int pixelW;
@property(nonatomic) int pixelH;

@property(nonatomic) float fps;
@property(nonatomic) int sarNum;
@property(nonatomic) int sarDen;
//degrees
@property(nonatomic) int autoZRotate;
@property(nonatomic) int hasAlpha;

@property(nonatomic) CVPixelBufferRef _Nullable videoPicture;
@property(nonatomic) NSArray * _Nullable videoTextures;

@property(nonatomic) SDL_TextureOverlay * _Nullable overlay;
@property(nonatomic) id _Nullable subTexture;

@end

static inline uint32_t fs_ass_color_to_int(UIColor *color) {
#if TARGET_OS_OSX
    if (![color.colorSpaceName isEqualToString:NSDeviceRGBColorSpace] && ![color.colorSpaceName isEqualToString:NSCalibratedRGBColorSpace]) {
        color = [color colorUsingColorSpaceName:NSDeviceRGBColorSpace];
    }
#endif
    CGFloat r,g,b,a;
    [color getRed:&r green:&g blue:&b alpha:&a];
    
    r *= 255;
    g *= 255;
    b *= 255;
    //in ass,0 means opaque
    a = 1-a;
    a *= 255;
    return (uint32_t)a + ((uint32_t)b << 8) + ((uint32_t)g << 16) + ((uint32_t)r << 24);
}

static inline UIColor * fs_ass_int_to_color(uint32_t rgba) {
    CGFloat r,g,b,a;
    a = 1 - (float)(rgba & 0xFF) / 255.0;
    b = (float)(rgba >> 8  & 0xFF) / 255.0;
    g = (float)(rgba >> 16 & 0xFF) / 255.0;
    r = (float)(rgba >> 24 & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:a];
}

typedef enum _FSSDLRotateType {
    FSRotateNone,
    FSRotateX,
    FSRotateY,
    FSRotateZ
} FSRotateType;

typedef struct _FSSDLRotatePreference FSRotatePreference;
struct _FSSDLRotatePreference {
    FSRotateType type;
    float degrees;
};

typedef struct _FSColorConvertPreference FSColorConvertPreference;
struct _FSColorConvertPreference {
    float brightness;
    float saturation;
    float contrast;
};

typedef struct _FSSDLDARPreference FSDARPreference;
struct _FSSDLDARPreference {
    float ratio; //ratio is width / height;
};

typedef enum : NSUInteger {
    FSSnapshotTypeOrigin, //keep original video size,without subtitle and video effect
    FSSnapshotTypeScreen, //current glview's picture as you see
    FSSnapshotTypeEffect_Origin,//keep original video size,with subtitle,without video effect
    FSSnapshotTypeEffect_Subtitle_Origin //keep original video size,with subtitle and video effect
} FSSnapshotType;

@protocol FSVideoRenderingDelegate;

@protocol FSVideoRenderingProtocol <NSObject>

@property(nullable, nonatomic, weak) id <FSVideoRenderingDelegate> displayDelegate;

@property(nonatomic) FSScalingMode scalingMode;
#if TARGET_OS_IOS
@property(nonatomic) CGFloat scaleFactor;
#endif
/*
 if you update these preference blow, when player paused,
 you can call -[setNeedsRefreshCurrentPic] method let current picture refresh right now.
 */
// rotate preference
@property(nonatomic) FSRotatePreference rotatePreference;
// color conversion preference
@property(nonatomic) FSColorConvertPreference colorPreference;
// user defined display aspect ratio
@property(nonatomic) FSDARPreference darPreference;
// not render picture and subtitle,but holder overlay content.
@property(atomic) BOOL preventDisplay;
// hdr video show 'Gray mask' animation
@property(nonatomic) BOOL showHdrAnimation;
// refresh current video picture and subtitle (when player paused change video pic preference, you can invoke this method)
- (void)setNeedsRefreshCurrentPic;

// display the overlay.
- (BOOL)displayAttach:(FSOverlayAttach *)attach;

#if !TARGET_OS_OSX
- (UIImage *)snapshot;
#else
- (CGImageRef)snapshot:(FSSnapshotType)aType;
#endif
- (NSString *)name;
- (id)context;

@optional;
- (void)setBackgroundColor:(uint8_t)r g:(uint8_t)g b:(uint8_t)b;
- (void)registerRefreshCurrentPicObserver:(nullable dispatch_block_t)block;

@end

@protocol FSVideoRenderingDelegate <NSObject>

- (void)videoRenderingDidDisplay:(id<FSVideoRenderingProtocol>)renderer attach:(FSOverlayAttach *)attach;

@end

NS_ASSUME_NONNULL_END

#endif /* FSVideoRenderingProtocol_h */
