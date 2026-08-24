import { L10n } from '../localization/L10n';
import { ApiEnvelope, JsonCodec } from '../../common/JsonTypes';

export class APIResponse<T> {
  success: boolean;
  data: T | undefined;
  message: string | undefined;
  code: number | undefined;
  rawResponse: ApiEnvelope | undefined;

  constructor(
    success: boolean,
    data: T | undefined,
    message: string | undefined,
    code: number | undefined,
    rawResponse: ApiEnvelope | undefined
  ) {
    this.success = success;
    this.data = data;
    this.message = message;
    this.code = code;
    this.rawResponse = rawResponse;
  }

  static success<T>(data: T, message?: string, code?: number, raw?: ApiEnvelope): APIResponse<T> {
    return new APIResponse<T>(true, data, message, code, raw);
  }

  static failure<T>(message: string, code?: number, raw?: ApiEnvelope): APIResponse<T> {
    return new APIResponse<T>(false, undefined, message, code, raw);
  }

  static fromJSON<T>(
    httpCode: number,
    json: ApiEnvelope,
    dataParser?: (data: Object, code: number) => T
  ): APIResponse<T> {
    const apiSuccess = json.success === true || json.code === 0;
    let message = json.message;
    const rawCode = APIResponse.stringValue(json.code);

    if (rawCode === 'service.NASCAB_SESSION_EXPIRED') {
      message = L10n.serviceSessionExpired;
    }

    let data: T | undefined = undefined;
    if (apiSuccess && dataParser && json.data !== undefined) {
      data = dataParser(json.data, httpCode);
    } else if (json.data !== undefined) {
      data = json.data as T;
    }

    return new APIResponse<T>(apiSuccess, data, message, httpCode, json);
  }

  private static stringValue(v: number | string | undefined): string | undefined {
    if (v === undefined || v === null) {
      return undefined;
    }
    if (typeof v === 'string') {
      return v;
    }
    return `${v}`;
  }
}
