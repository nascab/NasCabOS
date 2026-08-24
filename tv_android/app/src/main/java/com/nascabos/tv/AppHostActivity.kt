package com.nascabos.tv

/**
 * 宿主 Activity 通用能力，供 Fragment 在 MainActivity 或 FeatureHostActivity 中统一调用。
 */
interface AppHostActivity {
    fun setLoadingVisible(visible: Boolean)
    fun showError(message: String)
}
