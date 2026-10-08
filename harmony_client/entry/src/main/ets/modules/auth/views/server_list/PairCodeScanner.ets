import { scanBarcode, scanCore } from '@kit.ScanKit';
import { common } from '@kit.AbilityKit';

/**
 * 配对码二维码扫描，对应 Flutter pair_code_scanner_io.dart。
 * 扫描失败或用户取消时抛出异常，由调用方提示。
 */
export async function scanPairCodeQr(context: common.UIAbilityContext): Promise<string> {
  const options: scanBarcode.ScanOptions = {
    scanTypes: [scanCore.ScanType.QR_CODE],
    enableMultiMode: false,
    enableAlbum: true,
  };
  const result: scanBarcode.ScanResult = await scanBarcode.startScanForResult(context, options);
  return result.originalValue ?? '';
}
