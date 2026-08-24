import 'package:get/get.dart';

/// 将服务端 [ResponseUtil.error] 返回的 `code`（业务键）转为当前 App 语言的提示文案。
/// 与 [Accept-Language] 解耦，保证与 Flutter [LanguageService] 一致。
class ApiErrorLocalizer {
  ApiErrorLocalizer._();

  /// 服务端 `code` → GetX 翻译键（部分复用已有词条）。
  static const Map<String, String> _serverCodeToTrKey = {
    'file_custom_path_name_exists': 'file_custom_path_name_exists',
    'file_custom_path_path_exists': 'file_custom_path_path_exists',
    'auth.AUTHENTICATION_REQUIRED': 'api_code_auth_authentication_required',
    'auth.PERMISSION_DENIED': 'permission_denied',
    'file.INVALID_PARAMS': 'api_code_file_invalid_params',
    'common.NOT_FOUND': 'api_code_common_not_found',
    'common.FAILED': 'operation_failed',
    'common.ERROR': 'api_code_common_error',
    'encryptedSpace.PASSWORD_INCORRECT': 'api_code_encrypted_space_password_incorrect',
    'encryptedSpace.SIGN_FILE_MISSING': 'api_code_encrypted_space_sign_file_missing',
    'encryptedSpace.SPACE_DB_INVALID': 'api_code_encrypted_space_space_db_invalid',
    'encryptedSpace.SPACE_FOLDER_MISSING':
        'api_code_encrypted_space_space_folder_missing',
    'file.MISSING_PREVIOUS_CHUNKS': 'api_code_file_missing_previous_chunks',
    'file.CHUNK_MISMATCH': 'api_code_file_chunk_mismatch',
    'file.FILE_EXISTS': 'api_code_file_file_exists',
    'file.PATH_ALREADY_EXISTS': 'api_code_file_path_already_exists',
    'file.TARGET_IS_SOURCE': 'api_code_file_target_is_source',
    'file.TARGET_IS_SUBDIRECTORY': 'api_code_file_target_is_subdirectory',
    'notes.NOTEBOOK_NOT_SELECTED': 'api_code_notes_notebook_not_selected',
    'notes.NOTEBOOK_NOT_FOUND': 'api_code_notes_notebook_not_found',
    'notes.NOTEBOOK_INVALID': 'api_code_notes_notebook_invalid',
    'notes.NOTEBOOK_FOLDER_NOT_EMPTY':
        'api_code_notes_notebook_folder_not_empty',
    'notes.GROUP_NOT_EMPTY': 'api_code_notes_group_not_empty',
    'mountShare.PLUGIN_NOT_READY': 'mount_share_plugin_not_ready',
  };

  /// [apiErrorKey] 为响应 JSON 中的 `code` 字段（字符串业务键）。
  /// [serverMessage] 为服务端已翻译或未翻译的 `message`，作兜底。
  static String localize({
    required String? apiErrorKey,
    String? serverMessage,
  }) {
    final key = apiErrorKey?.trim();
    if (key != null && key.isNotEmpty) {
      final trKey = _serverCodeToTrKey[key];
      if (trKey != null) {
        final text = trKey.tr;
        if (text.isNotEmpty && text != trKey) return text;
      }
    }
    final raw = serverMessage?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return 'operation_failed'.tr;
  }
}
