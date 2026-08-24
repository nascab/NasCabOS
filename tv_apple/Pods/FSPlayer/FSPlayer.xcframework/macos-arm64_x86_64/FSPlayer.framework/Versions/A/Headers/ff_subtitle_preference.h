/*
 *  ff_subtitle_preference.h
 *
 * Copyright (c) 2024 debugly <qianlongxu@gmail.com>
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


#ifndef ff_subtitle_preference_hpp
#define ff_subtitle_preference_hpp

#include <stdio.h>
#include <string.h>
#include <stdlib.h>

typedef struct FSSubtitlePreference {
    float Scale; //字体缩放,默认 1.0
    float BottomMargin;//距离底部距离[0.0, 1.0]
    
    int ForceOverride;//强制使用以下样式
    char FontName[256];//字体名称
    //RGBA,in ass,0 means opaque
    uint32_t PrimaryColour;//主要填充颜色
    uint32_t SecondaryColour;//卡拉OK模式下的预填充
    uint32_t BackColour;//字体阴影色
    uint32_t OutlineColour;//字体边框颜色
    float Outline;//Outline 边框宽度
    char FontsDir[1024];//存放字体的文件夹路径（当字体没有安装到系统里时指定）
} FSSubtitlePreference;

static inline FSSubtitlePreference fs_subtitle_default_preference(void)
{
    return (FSSubtitlePreference){1.0, 0.025, 0, "", 0xFFFFFF00, 0x00FFFF00, 0x00000080, 0, 1, ""};
}

static inline uint32_t fs_str_to_uint32_color(char *token)
{
    char *sep = strrchr(token,'H');
    if (sep) {
        char *color = sep + 1;
        if (color) {
            return (uint32_t)strtol(color, NULL, 16);
        }
    }
    return 0;
}

static inline void fs_uint32_color_to_str(uint32_t color, char *buff, int size)
{
    bzero(buff, size);
    buff[0] = '&';
    buff[1] = 'H';
    
    uint32_t a = color & 0xFF;
    uint32_t r = color >> 8  & 0xFF;
    uint32_t g = color >> 16 & 0xFF;
    uint32_t b = color >> 24 & 0xFF;
    
    sprintf(buff + 2, "%02X", b);
    sprintf(buff + 4, "%02X", g);
    sprintf(buff + 6, "%02X", r);
    sprintf(buff + 8, "%02X", a);
}

static inline int FSSubtitlePreferenceIsEqual(FSSubtitlePreference* p1,FSSubtitlePreference* p2)
{
    if (!p1 || !p2) {
        return 0;
    }
    if (p1->ForceOverride != p2->ForceOverride ||
        p1->Scale != p2->Scale ||
        p1->PrimaryColour != p2->PrimaryColour ||
        p1->SecondaryColour != p2->SecondaryColour ||
        p1->BackColour != p2->BackColour ||
        p1->OutlineColour != p2->OutlineColour ||
        p1->Outline != p2->Outline ||
        p1->BottomMargin != p2->BottomMargin ||
        strcmp(p1->FontName, p2->FontName) ||
        strcmp(p1->FontsDir, p2->FontsDir)
        ) {
        return 0;
    }
    return 1;
}


#endif /* ff_subtitle_preference_hpp */
