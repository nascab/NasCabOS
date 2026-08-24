package com.nascabos.tv.core.i18n

import android.content.Context
import android.content.SharedPreferences
import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

object LocaleManager {
    private const val PREFS_NAME = "locale_prefs"
    private const val KEY_LANGUAGE_TAG = "language_tag"
    
    private var sharedPreferences: SharedPreferences? = null
    
    fun init(context: Context) {
        sharedPreferences = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }
    
    fun setLanguageTag(languageTag: String?) {
        val tag = languageTag?.trim().orEmpty()
        val locales = if (tag.isEmpty()) LocaleListCompat.getEmptyLocaleList() else LocaleListCompat.forLanguageTags(tag)
        AppCompatDelegate.setApplicationLocales(locales)
        
        // 持久化存储语言设置
        sharedPreferences?.edit()?.putString(KEY_LANGUAGE_TAG, tag)?.apply()
    }
    
    fun getSavedLanguageTag(): String? {
        return sharedPreferences?.getString(KEY_LANGUAGE_TAG, null)
    }
    
    fun restoreSavedLanguage() {
        val savedTag = getSavedLanguageTag()
        if (!savedTag.isNullOrBlank()) {
            val locales = LocaleListCompat.forLanguageTags(savedTag)
            AppCompatDelegate.setApplicationLocales(locales)
        }
    }
}
