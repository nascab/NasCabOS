import { util } from '@kit.ArkTS';
import { deviceInfo } from '@kit.BasicServicesKit';
import { i18n } from '@kit.LocalizationKit';
import { PreferencesStore } from '../storage/PreferencesStore';
import { CacheKeys } from '../storage/CacheKeys';
import { DeviceFingerprintJson } from '../../common/JsonTypes';

export class DeviceFingerprint {
  static getOrCreateStorageId(): string {
    const store = PreferencesStore.getInstance();
    const existing = store.getString(CacheKeys.DEVICE_FINGERPRINT_SEED, '')?.trim();
    if (existing && existing.length > 0) {
      return existing;
    }
    const newId = util.generateRandomUUID();
    void store.setString(CacheKeys.DEVICE_FINGERPRINT_SEED, newId);
    return newId;
  }

  static getOrCreateVideoPlayerDeviceId(): string {
    const store = PreferencesStore.getInstance();
    const existing = store.getString(CacheKeys.VIDEO_PLAYER_DEVICE_ID, '')?.trim();
    if (existing && existing.length > 0) {
      return existing;
    }
    const newId = util.generateRandomUUID();
    void store.setString(CacheKeys.VIDEO_PLAYER_DEVICE_ID, newId);
    return newId;
  }

  static getDeviceFingerprintPayload(): DeviceFingerprintJson {
    const locale = i18n.System.getSystemLocale();
    const language = locale.split(/[-_]/)[0] ?? '';
    const now = new Date();
    const timezoneOffset = -now.getTimezoneOffset();
    const timezoneName = Intl.DateTimeFormat().resolvedOptions().timeZone ?? '';

    const payload = new DeviceFingerprintJson();
    payload.user_agent = `NasCabOS Harmony/HarmonyOS`;
    payload.platform = 'HarmonyOS';
    payload.os_version = deviceInfo.osFullName ?? deviceInfo.displayVersion ?? '';
    payload.device_model = deviceInfo.productModel ?? '';
    payload.device_name = deviceInfo.marketName ?? payload.device_model;
    payload.language = language;
    payload.timezone_offset = timezoneOffset;
    payload.timezone_name = timezoneName;
    payload.storage_id = DeviceFingerprint.getOrCreateStorageId();
    payload.storage_type = 'Preferences';
    return payload;
  }
}
