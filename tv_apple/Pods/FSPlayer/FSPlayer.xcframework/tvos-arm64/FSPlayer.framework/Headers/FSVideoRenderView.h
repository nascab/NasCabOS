/*
 * FSVideoRenderView.h
 *
 * Copyright (c) 2023 debugly <qianlongxu@gmail.com>
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

// you can use below mthods, create ijk internal render view.

#import <FSPlayer/FSVideoRenderingProtocol.h>

NS_ASSUME_NONNULL_BEGIN

@interface FSVideoRenderView : NSObject

#if TARGET_OS_OSX
+ (UIView<FSVideoRenderingProtocol> *)createGLRenderView;
#endif

+ (UIView<FSVideoRenderingProtocol> *)createMetalRenderView NS_AVAILABLE(10_13, 11_0);

@end

NS_ASSUME_NONNULL_END
