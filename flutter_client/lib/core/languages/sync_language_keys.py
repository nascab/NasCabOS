#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""以 zh_cn 为基准同步各语言文件：补全缺失 key、删除 zh 中不存在的废弃 key。"""

import re
from pathlib import Path

LANG_DIR = Path(__file__).parent
ZH_FILE = LANG_DIR / 'zh_cn.dart'
EN_FILE = LANG_DIR / 'en_us.dart'

# zh 中不存在、代码未使用，从其他语言文件中移除
ORPHAN_KEYS = frozenset({
    'home_status_app_docker',
    'home_status_app_terminal',
})

PLAYER_ENGINE_KEYS = (
    'player_playback_engine',
    'player_engine_fvp',
    'player_engine_media3',
)

PLAYER_SUBTITLE_KEYS = (
    'player_subtitle_delete',
    'player_subtitle_delete_success',
)

OPENLIST_KEYS = (
    'file_mount_menu_openlist',
    'openlist_mount_help_tooltip',
    'openlist_mount_driver_doc_hint',
    'openlist_mount_driver_doc_help',
    'openlist_mount_create',
    'openlist_mount_edit',
    'openlist_mount_delete_confirm',
    'openlist_mount_driver',
    'openlist_mount_driver_config',
    'openlist_mount_oauth_help',
    'openlist_mount_oauth_hint',
    'openlist_mount_required',
    'openlist_mount_pick_folder',
    'openlist_mount_field_required',
    'openlist_mount_start_sent',
    'openlist_field_refresh_token',
    'openlist_field_access_token',
    'openlist_field_token',
    'openlist_field_cookie',
    'openlist_field_cookies',
    'openlist_field_mail_cookies',
    'openlist_field_client_id',
    'openlist_field_client_secret',
    'openlist_field_app_id',
    'openlist_field_app_secret',
    'openlist_field_username',
    'openlist_field_user_name',
    'openlist_field_password',
    'openlist_field_email',
    'openlist_field_phone',
    'openlist_field_authorization',
    'openlist_field_captcha_sign',
    'openlist_field_access_key',
    'openlist_field_secret_access_key',
    'openlist_field_access_key_id',
    'openlist_field_endpoint',
    'openlist_field_region',
    'openlist_field_bucket',
    'openlist_field_session_token',
    'openlist_field_custom_host',
    'openlist_field_force_path_style',
    'openlist_field_shareUrl',
    'openlist_field_share_code',
    'openlist_field_share_pwd',
    'openlist_field_share_id',
    'openlist_field_share_ids',
    'openlist_field_share_name',
    'openlist_field_sharekey',
    'openlist_field_receive_code',
    'openlist_field_redirect_uri',
    'openlist_field_owner',
    'openlist_field_safe_password',
    'openlist_field_sign_key',
    'openlist_field_qrcode_token',
    'openlist_field_qrcode_source',
)


def extract_keys(content: str) -> set[str]:
    return set(re.findall(r'''["']([^"']+)["']\s*:''', content))


def extract_key_line_blocks(content: str, keys: set[str]) -> dict[str, list[str]]:
    lines = content.splitlines()
    blocks: dict[str, list[str]] = {}
    i = 0
    while i < len(lines):
        m = re.match(r'''^\s*["']([^"']+)["']\s*:\s*(.*)$''', lines[i])
        if m and m.group(1) in keys:
            key = m.group(1)
            block = [lines[i]]
            tail = m.group(2).strip()
            if not tail or (not tail.endswith(',') and not tail.startswith("'") and not tail.startswith('"')):
                j = i + 1
                while j < len(lines):
                    block.append(lines[j])
                    if lines[j].rstrip().endswith(','):
                        break
                    j += 1
                i = j
            elif tail and not tail.rstrip().endswith(','):
                j = i + 1
                while j < len(lines):
                    block.append(lines[j])
                    if lines[j].rstrip().endswith(','):
                        break
                    j += 1
                i = j
            blocks[key] = block
        i += 1
    return blocks


def extract_openlist_section(content: str) -> str:
    """从 en_us 截取 file_mount_menu_openlist .. openlist_field_qrcode_source 整段。"""
    lines = content.splitlines()
    start = end = None
    for i, line in enumerate(lines):
        if start is None and re.search(r'''["']file_mount_menu_openlist["']\s*:''', line):
            start = i
        if start is not None and re.search(r'''["']file_mount_status_running["']\s*:''', line):
            end = i
            break
    if start is None or end is None:
        raise ValueError('openlist section not found')
    return '\n'.join(lines[start:end]) + '\n'


def repair_openlist_section(content: str, section: str) -> str:
    """替换已损坏的 openlist 插入段（若存在）。"""
    lines = content.splitlines(keepends=True)
    out: list[str] = []
    skipping = False
    for line in lines:
        if re.search(r'''["']file_mount_menu_openlist["']\s*:''', line):
            skipping = True
            out.append(section)
            if not section.endswith('\n'):
                pass
            continue
        if skipping:
            if re.search(r'''["']file_mount_status_running["']\s*:''', line):
                skipping = False
                out.append(line)
            continue
        out.append(line)
    return ''.join(out)


def remove_orphan_keys(content: str) -> str:
    lines = content.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    while i < len(lines):
        m = re.match(r'''^\s*["']([^"']+)["']\s*:''', lines[i])
        if m and m.group(1) in ORPHAN_KEYS:
            j = i + 1
            while j < len(lines) and not re.match(r'''^\s*["'][^"']+["']\s*:''', lines[j]):
                j += 1
            i = j
            continue
        out.append(lines[i])
        i += 1
    return ''.join(out)


def has_key(content: str, key: str) -> bool:
    return bool(re.search(rf'''["']{re.escape(key)}["']\s*:''', content))


def insert_after_anchor(content: str, anchor_key: str, insert_text: str, before_key: str | None = None) -> str:
    if not insert_text.strip():
        return content
    lines = content.splitlines(keepends=True)
    out: list[str] = []
    inserted = False
    for i, line in enumerate(lines):
        out.append(line)
        if inserted:
            continue
        if re.search(rf'''["']{re.escape(anchor_key)}["']\s*:''', line):
            if before_key and i + 1 < len(lines):
                nxt = lines[i + 1]
                if re.search(rf'''["']{re.escape(before_key)}["']\s*:''', nxt):
                    out.append(insert_text)
                    if not insert_text.endswith('\n'):
                        out.append('\n')
                    inserted = True
    if not inserted:
        raise ValueError(f'anchor not found: {anchor_key}')
    return ''.join(out)


def blocks_to_text(blocks: dict[str, list[str]], keys: tuple[str, ...]) -> str:
    parts: list[str] = []
    for key in keys:
        if key in blocks:
            parts.extend(blocks[key])
            if not blocks[key][-1].endswith('\n'):
                parts.append('\n')
    return ''.join(parts)


def sync_file(target: Path, source_blocks: dict[str, list[str]]) -> bool:
    content = target.read_text(encoding='utf-8')
    original = content
    content = remove_orphan_keys(content)

    # player subtitle
    sub_blocks = {k: source_blocks[k] for k in PLAYER_SUBTITLE_KEYS if k in source_blocks}
    if sub_blocks and not all(has_key(content, k) for k in PLAYER_SUBTITLE_KEYS):
        text = blocks_to_text(source_blocks, PLAYER_SUBTITLE_KEYS)
        if not has_key(content, 'player_subtitle_delete'):
            content = insert_after_anchor(
                content,
                'player_subtitle_upload_success',
                text,
                before_key='player_no_subtitle',
            )

    # player engine
    eng_blocks = {k: source_blocks[k] for k in PLAYER_ENGINE_KEYS if k in source_blocks}
    if eng_blocks and not all(has_key(content, k) for k in PLAYER_ENGINE_KEYS):
        text = blocks_to_text(source_blocks, PLAYER_ENGINE_KEYS)
        if not has_key(content, 'player_playback_engine'):
            content = insert_after_anchor(
                content,
                'player_loop',
                text,
                before_key='player_loop_sequence',
            )

    # openlist / file mount
    openlist_section = extract_openlist_section(EN_FILE.read_text(encoding='utf-8'))
    if has_key(content, 'file_mount_menu_openlist'):
        content = repair_openlist_section(content, openlist_section)
    elif not has_key(content, 'file_mount_menu_openlist'):
        content = insert_after_anchor(
            content,
            'file_mount_menu_manage',
            openlist_section,
            before_key='file_mount_status_running',
        )

    if content != original:
        target.write_text(content, encoding='utf-8')
        return True
    return False


def main():
    zh_keys = extract_keys(ZH_FILE.read_text(encoding='utf-8'))
    zh_keys.discard('zh_CN')

    all_sync_keys = set(PLAYER_ENGINE_KEYS) | set(PLAYER_SUBTITLE_KEYS) | set(OPENLIST_KEYS)
    en_content = EN_FILE.read_text(encoding='utf-8')
    source_blocks = extract_key_line_blocks(en_content, all_sync_keys)

    missing_in_en = all_sync_keys - set(source_blocks.keys())
    if missing_in_en:
        raise SystemExit(f'en_us missing blocks: {missing_in_en}')

    updated = []
    for dart in sorted(LANG_DIR.glob('*.dart')):
        if dart.name in ('zh_cn.dart', 'en_us.dart', 'language_service.dart'):
            continue
        if sync_file(dart, source_blocks):
            updated.append(dart.name)

    # en_us: only remove orphans
    en = remove_orphan_keys(en_content)
    if en != en_content:
        EN_FILE.write_text(en, encoding='utf-8')
        updated.append('en_us.dart (orphan cleanup)')

    print('Updated:', ', '.join(updated) if updated else 'none')


if __name__ == '__main__':
    main()
