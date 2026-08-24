#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
检测所有其他语言相对于 zh-CN 缺少的翻译 key
"""

import re
import os
from pathlib import Path
from typing import Dict, Set, Tuple

def extract_keys_from_file(file_path: str) -> Set[str]:
    """从 Dart 翻译文件中提取所有 key（支持单/双引号）"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    keys = set(re.findall(r'''["']([^"']+)["']\s*:''', content))
    return keys


def is_locale_bucket_key(key: str) -> bool:
    """GetX 语言包外层 locale 名（如 de_DE），不是翻译词条"""
    return bool(re.fullmatch(r'[a-z]{2}_[A-Z]{2}', key))

def extract_key_values(file_path: str) -> Dict[str, str]:
    """从 Dart 翻译文件中提取 key-value 对"""
    with open(file_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 匹配 'key': 'value' 格式，支持多行值
    pattern = r"'([^']+)'\s*:\s*(?:'((?:[^'\\]|\\.)*)'|r'((?:[^']|'[^)])*)')"
    matches = re.findall(pattern, content)
    
    result = {}
    for match in matches:
        key = match[0]
        value = match[1] if match[1] else match[2]
        result[key] = value
    
    return result

def get_language_files(languages_dir: str) -> Dict[str, str]:
    """获取所有语言文件及其名称"""
    language_files = {}
    
    for file in os.listdir(languages_dir):
        if file.endswith('.dart') and file not in ['zh_cn.dart','language_service.dart'] :
            # 从文件名推断语言名称
            lang_code = file.replace('.dart', '')
            language_files[lang_code] = os.path.join(languages_dir, file)
    
    return language_files

def compare_languages(zh_cn_file: str, language_files: Dict[str, str]) -> Tuple[Dict[str, Set[str]], Dict[str, int]]:
    """比较所有语言与 zh-CN 的差异"""
    zh_keys = extract_keys_from_file(zh_cn_file)
    
    zh_keys.discard('zh_CN')
    zh_keys = {k for k in zh_keys if not is_locale_bucket_key(k)}
    
    missing_keys = {}
    extra_keys = {}
    key_counts = {}
    
    for lang_code, file_path in language_files.items():
        lang_keys = extract_keys_from_file(file_path)
        lang_keys = {k for k in lang_keys if not is_locale_bucket_key(k)}
        missing = zh_keys - lang_keys
        extra = lang_keys - zh_keys
        missing_keys[lang_code] = missing
        extra_keys[lang_code] = extra
        key_counts[lang_code] = len(lang_keys)
    
    return missing_keys, extra_keys, key_counts, len(zh_keys)

def print_report(
    missing_keys: Dict[str, Set[str]],
    extra_keys: Dict[str, Set[str]],
    key_counts: Dict[str, int],
    zh_total: int,
):
    """打印报告"""
    print("=" * 80)
    print("翻译文件缺失 Key 检测报告")
    print("=" * 80)
    print(f"\n参考语言：zh-CN (总 key 数：{zh_total})")
    print("\n" + "-" * 80)
    
    # 按缺失数量排序
    sorted_langs = sorted(missing_keys.items(), key=lambda x: len(x[1]))
    
    for lang_code, missing in sorted_langs:
        count = key_counts[lang_code]
        extra = extra_keys.get(lang_code, set())
        percentage = (count / zh_total) * 100 if zh_total > 0 else 0
        print(f"\n{lang_code.upper()}:")
        print(f"  现有 key 数：{count}")
        print(f"  缺失 key 数：{len(missing)}")
        print(f"  多余 key 数：{len(extra)}")
        print(f"  完整度：{percentage:.1f}%")
        
        if missing:
            print(f"  缺失的 key 列表:")
            for key in sorted(missing):
                print(f"    - {key}")
        if extra:
            print(f"  多余 key 列表（zh-CN 中不存在）:")
            for key in sorted(extra):
                print(f"    - {key}")
    
    print("\n" + "=" * 80)
    print("检测完成")
    print("=" * 80)

def save_report(
    missing_keys: Dict[str, Set[str]],
    extra_keys: Dict[str, Set[str]],
    key_counts: Dict[str, int],
    zh_total: int,
    output_file: str,
):
    """保存报告到文件"""
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write("=" * 80 + "\n")
        f.write("翻译文件缺失 Key 检测报告\n")
        f.write("=" * 80 + "\n\n")
        f.write(f"参考语言：zh-CN (总 key 数：{zh_total})\n\n")
        f.write("-" * 80 + "\n")
        
        # 按缺失数量排序
        sorted_langs = sorted(missing_keys.items(), key=lambda x: len(x[1]))
        
        for lang_code, missing in sorted_langs:
            count = key_counts[lang_code]
            extra = extra_keys.get(lang_code, set())
            percentage = (count / zh_total) * 100 if zh_total > 0 else 0
            f.write(f"\n{lang_code.upper()}:\n")
            f.write(f"  现有 key 数：{count}\n")
            f.write(f"  缺失 key 数：{len(missing)}\n")
            f.write(f"  多余 key 数：{len(extra)}\n")
            f.write(f"  完整度：{percentage:.1f}%\n")
            
            if missing:
                f.write(f"  缺失的 key 列表:\n")
                for key in sorted(missing):
                    f.write(f"    - {key}\n")
            if extra:
                f.write(f"  多余 key 列表（zh-CN 中不存在）:\n")
                for key in sorted(extra):
                    f.write(f"    - {key}\n")
        
        f.write("\n" + "=" * 80 + "\n")
        f.write("检测完成\n")
        f.write("=" * 80 + "\n")

def main():
    # 设置路径
    script_dir = Path(__file__).parent
    languages_dir = script_dir  # 脚本就在 languages 目录下
    zh_cn_file = languages_dir / 'zh_cn.dart'
    output_file = script_dir / 'missing_keys_report.txt'
    
    if not zh_cn_file.exists():
        print(f"错误：找不到 zh-CN 翻译文件：{zh_cn_file}")
        return
    
    # 获取所有语言文件
    language_files = get_language_files(languages_dir)
    
    if not language_files:
        print("错误：没有找到其他语言文件")
        return
    
    print(f"找到 {len(language_files)} 个语言文件")
    print(f"参考文件：zh_cn.dart")
    print()
    
    # 比较语言
    missing_keys, extra_keys, key_counts, zh_total = compare_languages(
        str(zh_cn_file), language_files
    )
    
    # 打印报告到控制台
    print_report(missing_keys, extra_keys, key_counts, zh_total)
    
    # 保存报告到文件
    save_report(missing_keys, extra_keys, key_counts, zh_total, str(output_file))
    print(f"\n报告已保存到：{output_file}")

if __name__ == '__main__':
    main()
