/*
 * FSPlayerKit.h
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

#ifndef FSPlayerKit_h
#define FSPlayerKit_h


#if TARGET_OS_IOS || TARGET_OS_TV
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

#import <FSPlayer/FSMediaPlayback.h>
#import <FSPlayer/FSMonitor.h>
#import <FSPlayer/FSOptions.h>
#import <FSPlayer/FSPlayer.h>
#import <FSPlayer/FSMediaModule.h>
#import <FSPlayer/FSNotificationManager.h>
#import <FSPlayer/FSKVOController.h>
#import <FSPlayer/FSVideoRenderingProtocol.h>
#import <FSPlayer/FSVideoRenderView.h>
#import <FSPlayer/FSAudioRenderingProtocol.h>
#import <FSPlayer/FSAudioRendering.h>
#endif /* FSPlayerKit_h */
