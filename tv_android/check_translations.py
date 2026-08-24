#!/usr/bin/env python3
import os
import xml.etree.ElementTree as ET
from pathlib import Path

def parse_strings_xml(file_path):
    """解析 strings.xml 文件，返回 key 集合"""
    keys = set()
    if not os.path.exists(file_path):
        return keys
    
    try:
        tree = ET.parse(file_path)
        root = tree.getroot()
        
        for child in root:
            if child.tag == 'string' and 'name' in child.attrib:
                keys.add(child.attrib['name'])
            elif child.tag == 'plurals' and 'name' in child.attrib:
                keys.add(child.attrib['name'])
        
        return keys
    except Exception as e:
        print(f"Error parsing {file_path}: {e}")
        return keys

def main():
    base_path = Path(__file__).parent / "app/src/main/res"
    zh_cn_path = base_path / "values-zh-rCN/strings.xml"
    
    if not zh_cn_path.exists():
        print(f"中文翻译文件不存在: {zh_cn_path}")
        return
    
    zh_cn_keys = parse_strings_xml(zh_cn_path)
    print(f"中文翻译文件包含 {len(zh_cn_keys)} 个 key\n")
    
    language_dirs = [
        d for d in os.listdir(base_path) 
        if d.startswith("values-") and d != "values-zh-rCN"
    ]
    
    for lang_dir in sorted(language_dirs):
        lang_code = lang_dir.replace("values-", "")
        strings_path = base_path / lang_dir / "strings.xml"
        
        if not strings_path.exists():
            print(f"[{lang_code}] 翻译文件不存在")
            continue
        
        lang_keys = parse_strings_xml(strings_path)
        missing_keys = zh_cn_keys - lang_keys
        extra_keys = lang_keys - zh_cn_keys
        
        print(f"[{lang_code}]")
        print(f"  总 key 数: {len(lang_keys)}")
        if missing_keys:
            print(f"  缺少 {len(missing_keys)} 个 key:")
            for key in sorted(missing_keys):
                print(f"    - {key}")
        else:
            print(f"  所有 key 都已翻译 ✓")
        
        if extra_keys:
            print(f"  额外有 {len(extra_keys)} 个 key (中文没有):")
            for key in sorted(extra_keys):
                print(f"    + {key}")
        print()

if __name__ == "__main__":
    main()
