#!/bin/sh
# App Store Connect 会校验嵌入 Framework 的 dSYM UUID。WebRTC-SDK、ass 等预编译库常不带 dSYM；
# 在 Embed 完成后对 .app/Frameworks 内的二进制运行 dsymutil，可在归档的 dSYMs 目录生成匹配 UUID 的包
#（符号化能力有限，但可通过 “Upload Symbols” 校验）。

set -eu

FRAMEWORKS_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
DSYM_DIR="${DWARF_DSYM_FOLDER_PATH:-}"

if [ -z "${DSYM_DIR}" ] || [ ! -d "${DSYM_DIR}" ]; then
  echo "note: DWARF_DSYM_FOLDER_PATH unset or missing, skip third-party dSYM generation."
  exit 0
fi

if [ ! -d "${FRAMEWORKS_DIR}" ]; then
  echo "note: frameworks dir missing (${FRAMEWORKS_DIR}), skip."
  exit 0
fi

emit_dsym() {
  _fw_name="$1"
  _bin_name="$2"
  _bin="${FRAMEWORKS_DIR}/${_fw_name}.framework/${_bin_name}"
  if [ -f "${_bin}" ]; then
    echo "Generating dSYM for ${_fw_name}.framework..."
    # 覆盖旧产物，避免 Archive 增量构建沿用错误 UUID
    rm -rf "${DSYM_DIR}/${_fw_name}.framework.dSYM"
    dsymutil "${_bin}" -o "${DSYM_DIR}/${_fw_name}.framework.dSYM"
  fi
}

emit_dsym "WebRTC" "WebRTC"
emit_dsym "ass" "ass"
emit_dsym "PDFium" "PDFium"

exit 0
