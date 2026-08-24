'use strict';

/**
 * 从 listSupportedBackends() 获取可用的后端名称列表。
 * 返回如 ['cpu', 'coreml'] 或 ['cpu', 'dml'] 等。
 */
function getAvailableBackendNames() {
  try {
    const onnx = require('onnxruntime-node');
    if (typeof onnx.listSupportedBackends === 'function') {
      const backends = onnx.listSupportedBackends();
      if (Array.isArray(backends) && backends.length > 0) {
        return backends.map(b => (b && b.name) || String(b));
      }
    }
  } catch {}
  return ['cpu'];
}

/**
 * 检查是否允许优先使用 GPU 加速。
 * 读取环境变量 AI_GPU_PREFER：'0' 或未设置时禁用 GPU，其他值启用。
 */
function isGpuPreferEnabled() {
  const raw = process.env.AI_GPU_PREFER;
  return raw !== '0';
}

/**
 * 根据运行时实际加载的 ONNX 后端自动选择最优 Execution Provider。
 * 受 AI_GPU_PREFER 环境变量控制：关闭时只返回 ['cpu']。
 * cpu 始终放在数组末尾作为最终回退。
 */
function getBestExecutionProviders() {
  if (!isGpuPreferEnabled()) {
    return ['cpu'];
  }
  const backends = getAvailableBackendNames();
  const gpuBackends = backends.filter(b => b !== 'cpu');
  return [...gpuBackends, 'cpu'];
}

/**
 * 获取运行时实际加载的 ONNX Runtime 后端列表（已格式化）。
 * 返回值如 "cpu, coreml" 或 "cpu"。
 */
function getLoadedBackends() {
  return getAvailableBackendNames().join(', ');
}

module.exports = { getBestExecutionProviders, getLoadedBackends };
