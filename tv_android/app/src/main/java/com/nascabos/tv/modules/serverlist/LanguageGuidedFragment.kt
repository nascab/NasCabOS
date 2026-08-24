package com.nascabos.tv.modules.serverlist

import android.os.Bundle
import androidx.appcompat.app.AppCompatDelegate
import androidx.leanback.app.GuidedStepSupportFragment
import androidx.leanback.widget.GuidanceStylist
import androidx.leanback.widget.GuidedAction
import com.nascabos.tv.R
import com.nascabos.tv.core.i18n.LocaleManager

class LanguageGuidedFragment : GuidedStepSupportFragment() {
    override fun onProvideTheme(): Int = androidx.leanback.R.style.Theme_Leanback_GuidedStep

    override fun onCreateGuidance(savedInstanceState: Bundle?): GuidanceStylist.Guidance {
        return GuidanceStylist.Guidance(
            getString(R.string.language_title),
            null,
            getString(R.string.app_display_name),
            null,
        )
    }

    override fun onCreateActions(actions: MutableList<GuidedAction>, savedInstanceState: Bundle?) {
        val selectedId = selectedLanguageActionId()
        // Language order: en-US, zh-CN, ja-JP, ko-KR, es-ES, pt-BR, fr-FR, de-DE, ru-RU, id-ID, vi-VN, th-TH, ar-SA
        actions += GuidedAction.Builder(requireContext())
            .id(ID_SYSTEM)
            .title(getString(R.string.language_system))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_SYSTEM)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_EN)
            .title(getString(R.string.language_en))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_EN)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_ZH_CN)
            .title(getString(R.string.language_zh_cn))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_ZH_CN)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_JA)
            .title(getString(R.string.language_ja))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_JA)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_KO)
            .title(getString(R.string.language_ko))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_KO)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_ES)
            .title(getString(R.string.language_es))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_ES)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_PT)
            .title(getString(R.string.language_pt))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_PT)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_FR)
            .title(getString(R.string.language_fr))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_FR)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_DE)
            .title(getString(R.string.language_de))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_DE)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_RU)
            .title(getString(R.string.language_ru))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_RU)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_IN)
            .title(getString(R.string.language_in))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_IN)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_VI)
            .title(getString(R.string.language_vi))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_VI)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_TH)
            .title(getString(R.string.language_th))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_TH)
            .build()
        actions += GuidedAction.Builder(requireContext())
            .id(ID_AR)
            .title(getString(R.string.language_ar))
            .checkSetId(CHECK_SET_ID)
            .checked(selectedId == ID_AR)
            .build()
    }

    override fun onGuidedActionClicked(action: GuidedAction) {
        when (action.id) {
            ID_SYSTEM -> LocaleManager.setLanguageTag(null)
            ID_EN -> LocaleManager.setLanguageTag("en-US")
            ID_ZH_CN -> LocaleManager.setLanguageTag("zh-CN")
            ID_JA -> LocaleManager.setLanguageTag("ja-JP")
            ID_KO -> LocaleManager.setLanguageTag("ko-KR")
            ID_ES -> LocaleManager.setLanguageTag("es-ES")
            ID_PT -> LocaleManager.setLanguageTag("pt-BR")
            ID_FR -> LocaleManager.setLanguageTag("fr-FR")
            ID_DE -> LocaleManager.setLanguageTag("de-DE")
            ID_RU -> LocaleManager.setLanguageTag("ru-RU")
            ID_IN -> LocaleManager.setLanguageTag("id-ID")
            ID_VI -> LocaleManager.setLanguageTag("vi-VN")
            ID_TH -> LocaleManager.setLanguageTag("th-TH")
            ID_AR -> LocaleManager.setLanguageTag("ar-SA")
        }
        requireActivity().supportFragmentManager.popBackStack()
        requireActivity().window.decorView.post { requireActivity().recreate() }
    }

    private fun selectedLanguageActionId(): Long {
        val tags = AppCompatDelegate.getApplicationLocales().toLanguageTags().trim()
        if (tags.isEmpty()) return ID_SYSTEM
        return when {
            tags.startsWith("en", ignoreCase = true) -> ID_EN
            tags.startsWith("zh", ignoreCase = true) -> ID_ZH_CN
            tags.startsWith("ja", ignoreCase = true) -> ID_JA
            tags.startsWith("ko", ignoreCase = true) -> ID_KO
            tags.startsWith("es", ignoreCase = true) -> ID_ES
            tags.startsWith("pt", ignoreCase = true) -> ID_PT
            tags.startsWith("fr", ignoreCase = true) -> ID_FR
            tags.startsWith("de", ignoreCase = true) -> ID_DE
            tags.startsWith("ru", ignoreCase = true) -> ID_RU
            tags.startsWith("id", ignoreCase = true) -> ID_IN
            tags.startsWith("vi", ignoreCase = true) -> ID_VI
            tags.startsWith("th", ignoreCase = true) -> ID_TH
            tags.startsWith("ar", ignoreCase = true) -> ID_AR
            else -> ID_SYSTEM
        }
    }

    companion object {
        private const val ID_SYSTEM = 1L
        private const val ID_ZH_CN = 2L
        private const val ID_EN = 3L
        private const val ID_ES = 4L
        private const val ID_PT = 5L
        private const val ID_DE = 6L
        private const val ID_FR = 7L
        private const val ID_JA = 8L
        private const val ID_AR = 9L
        private const val ID_KO = 10L
        private const val ID_IN = 11L
        private const val ID_RU = 12L
        private const val ID_TH = 13L
        private const val ID_VI = 14L
        private const val CHECK_SET_ID = 20
    }
}
