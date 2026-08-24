; NSIS Installer Custom Script for NasCabOS Server
; 自定义安装脚本
; 
; 注意：NSIS 会自动检测系统语言并选择合适的语言
; 如果系统语言不在支持列表中，会回退到默认语言（英语）

; ========== 多语言字符串定义（使用 LangString，运行时按当前安装语言显示，避免中英混显）==========
; 与 electron-builder bundledLanguages 对齐；无翻译的语种用英文兜底。LCID: 2052=zh_CN 1033=en 1028=zh_TW 1031=de 1036=fr 3082=es 1041=ja 1042=ko 1040=it 1043=nl 1030=da 1053=sv 1044=nb 1035=fi 1049=ru 2070=pt_PT 1046=pt_BR 1045=pl 1058=uk 1029=cs 1051=sk 1038=hu 1025=ar 1055=tr 1054=th 1066=vi

LangString UNINSTALL_DELETE_DATA_QUESTION 2052 "是否要删除程序数据文件？"
LangString UNINSTALL_DELETE_DATA_QUESTION 1028 "是否要刪除程式資料檔案？"
LangString UNINSTALL_DELETE_DATA_QUESTION 1033 "Do you want to delete program data files?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1031 "Möchten Sie Programm-Datendateien löschen?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1036 "Voulez-vous supprimer les fichiers de données du programme ?"
LangString UNINSTALL_DELETE_DATA_QUESTION 3082 "¿Desea eliminar los archivos de datos del programa?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1041 "プログラムデータを削除しますか？"
LangString UNINSTALL_DELETE_DATA_QUESTION 1042 "프로그램 데이터 파일을 삭제하시겠습니까?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1040 "Vuoi eliminare i file di dati del programma?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1043 "Wilt u programmabestanden verwijderen?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1030 "Vil du slette programdatafiler?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1053 "Vill du ta bort programdatafiler?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1044 "Vil du slette programdatafiler?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1035 "Haluatko poistaa ohjelman tiedostot?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1049 "Хотите удалить файлы данных программы?"
LangString UNINSTALL_DELETE_DATA_QUESTION 2070 "Deseja eliminar os ficheiros de dados do programa?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1046 "Deseja excluir os arquivos de dados do programa?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1045 "Czy chcesz usunąć pliki danych programu?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1058 "Ви хочете видалити файли даних програми?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1029 "Chcete smazat datové soubory programu?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1051 "Chcete odstrániť dátové súbory programu?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1038 "Törölni szeretné a program adatfájlait?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1025 "هل تريد حذف ملفات بيانات البرنامج؟"
LangString UNINSTALL_DELETE_DATA_QUESTION 1055 "Program veri dosyalarını silmek istiyor musunuz?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1054 "คุณต้องการลบไฟล์ข้อมูลโปรแกรมหรือไม่?"
LangString UNINSTALL_DELETE_DATA_QUESTION 1066 "Bạn có muốn xóa các tệp dữ liệu chương trình không?"

LangString UNINSTALL_DELETE_DATA_WARNING 2052 "注意：删除后将无法恢复，请谨慎选择！"
LangString UNINSTALL_DELETE_DATA_WARNING 1028 "注意：刪除後將無法復原，請謹慎選擇！"
LangString UNINSTALL_DELETE_DATA_WARNING 1033 "Warning: This action cannot be undone!"
LangString UNINSTALL_DELETE_DATA_WARNING 1031 "Warnung: Diese Aktion kann nicht rückgängig gemacht werden!"
LangString UNINSTALL_DELETE_DATA_WARNING 3082 "Advertencia: ¡Esta acción no se puede deshacer!"
LangString UNINSTALL_DELETE_DATA_WARNING 1036 "Attention : Cette action ne peut pas être annulée !"
LangString UNINSTALL_DELETE_DATA_WARNING 1041 "警告：この操作は元に戻せません！"
LangString UNINSTALL_DELETE_DATA_WARNING 1042 "경고: 이 작업은 취소할 수 없습니다!"
LangString UNINSTALL_DELETE_DATA_WARNING 1040 "Attenzione: Questa azione non può essere annullata!"
LangString UNINSTALL_DELETE_DATA_WARNING 1043 "Waarschuwing: Deze actie kan niet ongedaan worden gemaakt!"
LangString UNINSTALL_DELETE_DATA_WARNING 1030 "Advarsel: Denne handling kan ikke fortrydes!"
LangString UNINSTALL_DELETE_DATA_WARNING 1053 "Varning: Denna åtgärd kan inte ångras!"
LangString UNINSTALL_DELETE_DATA_WARNING 1044 "Advarsel: Denne handlingen kan ikke angres!"
LangString UNINSTALL_DELETE_DATA_WARNING 1035 "Varoitus: Tätä toimintoa ei voi peruuttaa!"
LangString UNINSTALL_DELETE_DATA_WARNING 1049 "Предупреждение: Это действие нельзя отменить!"
LangString UNINSTALL_DELETE_DATA_WARNING 2070 "Aviso: Esta ação não pode ser desfeita!"
LangString UNINSTALL_DELETE_DATA_WARNING 1046 "Aviso: Esta ação não pode ser desfeita!"
LangString UNINSTALL_DELETE_DATA_WARNING 1045 "Ostrzeżenie: Tej czynności nie można cofnąć!"
LangString UNINSTALL_DELETE_DATA_WARNING 1058 "Попередження: Цю дію не можна скасувати!"
LangString UNINSTALL_DELETE_DATA_WARNING 1029 "Varování: Tuto akci nelze vrátit zpět!"
LangString UNINSTALL_DELETE_DATA_WARNING 1051 "Upozornenie: Túto akciu nemožno vrátiť späť!"
LangString UNINSTALL_DELETE_DATA_WARNING 1038 "Figyelmeztetés: Ezt a műveletet nem lehet visszavonni!"
LangString UNINSTALL_DELETE_DATA_WARNING 1025 "تحذير: لا يمكن التراجع عن هذا الإجراء!"
LangString UNINSTALL_DELETE_DATA_WARNING 1055 "Uyarı: Bu işlem geri alınamaz!"
LangString UNINSTALL_DELETE_DATA_WARNING 1054 "คำเตือน: การดำเนินการนี้ไม่สามารถยกเลิกได้!"
LangString UNINSTALL_DELETE_DATA_WARNING 1066 "Cảnh báo: Không thể hoàn tác thao tác này!"

LangString UNINSTALL_DELETE_DATA_YESNO 2052 "点击'是'删除数据文件，点击'否'保留数据文件。"
LangString UNINSTALL_DELETE_DATA_YESNO 1028 "點擊「是」刪除資料檔案，點擊「否」保留。"
LangString UNINSTALL_DELETE_DATA_YESNO 1033 "Click 'Yes' to delete, 'No' to keep."
LangString UNINSTALL_DELETE_DATA_YESNO 1031 "Klicken Sie 'Ja' zum Löschen, 'Nein' zum Behalten."
LangString UNINSTALL_DELETE_DATA_YESNO 3082 "Haga clic en 'Sí' para eliminar, 'No' para conservar."
LangString UNINSTALL_DELETE_DATA_YESNO 1036 "Cliquez sur 'Oui' pour supprimer, 'Non' pour conserver."
LangString UNINSTALL_DELETE_DATA_YESNO 1041 "削除するには'はい'、保持するには'いいえ'をクリックしてください。"
LangString UNINSTALL_DELETE_DATA_YESNO 1042 "삭제하려면 '예', 보관하려면 '아니요'를 클릭하십시오."
LangString UNINSTALL_DELETE_DATA_YESNO 1040 "Clicca 'Sì' per eliminare, 'No' per mantenere."
LangString UNINSTALL_DELETE_DATA_YESNO 1043 "Klik op 'Ja' om te verwijderen, 'Nee' om te behouden."
LangString UNINSTALL_DELETE_DATA_YESNO 1030 "Klik på 'Ja' for at slette, 'Nej' for at beholde."
LangString UNINSTALL_DELETE_DATA_YESNO 1053 "Klicka på 'Ja' för att ta bort, 'Nej' för att behålla."
LangString UNINSTALL_DELETE_DATA_YESNO 1044 "Klikk 'Ja' for å slette, 'Nei' for å beholde."
LangString UNINSTALL_DELETE_DATA_YESNO 1035 "Valitse 'Kyllä' poistaaksesi, 'Ei' säilyttääksesi."
LangString UNINSTALL_DELETE_DATA_YESNO 1049 "Нажмите 'Да' для удаления, 'Нет' для сохранения."
LangString UNINSTALL_DELETE_DATA_YESNO 2070 "Clique em 'Sim' para eliminar, 'Não' para manter."
LangString UNINSTALL_DELETE_DATA_YESNO 1046 "Clique em 'Sim' para excluir, 'Não' para manter."
LangString UNINSTALL_DELETE_DATA_YESNO 1045 "Kliknij 'Tak', aby usunąć, 'Nie', aby zachować."
LangString UNINSTALL_DELETE_DATA_YESNO 1058 "Натисніть 'Так' для видалення, 'Ні' для збереження."
LangString UNINSTALL_DELETE_DATA_YESNO 1029 "Klikněte na 'Ano' pro smazání, 'Ne' pro zachování."
LangString UNINSTALL_DELETE_DATA_YESNO 1051 "Kliknite na 'Áno' na odstránenie, 'Nie' na zachovanie."
LangString UNINSTALL_DELETE_DATA_YESNO 1038 "Kattintson az 'Igen' gombra a törléshez, a 'Nem' gombra a megőrzéshez."
LangString UNINSTALL_DELETE_DATA_YESNO 1025 "انقر 'نعم' للحذف، 'لا' للاحتفاظ."
LangString UNINSTALL_DELETE_DATA_YESNO 1055 "'Evet' silmek için, 'Hayır' tutmak için tıklayın."
LangString UNINSTALL_DELETE_DATA_YESNO 1054 "คลิก 'ใช่' เพื่อลบ 'ไม่' เพื่อเก็บ"
LangString UNINSTALL_DELETE_DATA_YESNO 1066 "Nhấp 'Có' để xóa, 'Không' để giữ."

LangString UNINSTALL_DELETING 2052 "正在删除数据文件..."
LangString UNINSTALL_DELETING 1028 "正在刪除資料檔案..."
LangString UNINSTALL_DELETING 1033 "Deleting data files..."
LangString UNINSTALL_DELETING 1031 "Datendateien werden gelöscht..."
LangString UNINSTALL_DELETING 3082 "Eliminando archivos de datos..."
LangString UNINSTALL_DELETING 1036 "Suppression des fichiers de données..."
LangString UNINSTALL_DELETING 1041 "データを削除しています..."
LangString UNINSTALL_DELETING 1042 "데이터 파일을 삭제 중입니다..."
LangString UNINSTALL_DELETING 1040 "Eliminazione file di dati..."
LangString UNINSTALL_DELETING 1043 "Bestanden verwijderen..."
LangString UNINSTALL_DELETING 1030 "Sletter datafiler..."
LangString UNINSTALL_DELETING 1053 "Tar bort datafiler..."
LangString UNINSTALL_DELETING 1044 "Sletter datafiler..."
LangString UNINSTALL_DELETING 1035 "Poistetaan tiedostoja..."
LangString UNINSTALL_DELETING 1049 "Удаление файлов данных..."
LangString UNINSTALL_DELETING 2070 "A eliminar ficheiros de dados..."
LangString UNINSTALL_DELETING 1046 "Excluindo arquivos de dados..."
LangString UNINSTALL_DELETING 1045 "Usuwanie plików danych..."
LangString UNINSTALL_DELETING 1058 "Видалення файлів даних..."
LangString UNINSTALL_DELETING 1029 "Mažu se datové soubory..."
LangString UNINSTALL_DELETING 1051 "Odstraňujú sa dátové súbory..."
LangString UNINSTALL_DELETING 1038 "Adatfájlok törlése..."
LangString UNINSTALL_DELETING 1025 "جاري حذف ملفات البيانات..."
LangString UNINSTALL_DELETING 1055 "Veri dosyaları siliniyor..."
LangString UNINSTALL_DELETING 1054 "กำลังลบไฟล์ข้อมูล..."
LangString UNINSTALL_DELETING 1066 "Đang xóa các tệp dữ liệu..."

LangString UNINSTALL_KEEPING 2052 "正在保留数据文件..."
LangString UNINSTALL_KEEPING 1028 "正在保留資料檔案..."
LangString UNINSTALL_KEEPING 1033 "Keeping data files..."
LangString UNINSTALL_KEEPING 1031 "Datendateien werden behalten..."
LangString UNINSTALL_KEEPING 3082 "Conservando archivos de datos..."
LangString UNINSTALL_KEEPING 1036 "Conservation des fichiers de données..."
LangString UNINSTALL_KEEPING 1041 "データを保持しています..."
LangString UNINSTALL_KEEPING 1042 "데이터 파일을 보관 중입니다..."
LangString UNINSTALL_KEEPING 1040 "Mantenimento file di dati..."
LangString UNINSTALL_KEEPING 1043 "Bestanden behouden..."
LangString UNINSTALL_KEEPING 1030 "Beholder datafiler..."
LangString UNINSTALL_KEEPING 1053 "Behåller datafiler..."
LangString UNINSTALL_KEEPING 1044 "Beholder datafiler..."
LangString UNINSTALL_KEEPING 1035 "Säilytetään tiedostoja..."
LangString UNINSTALL_KEEPING 1049 "Сохранение файлов данных..."
LangString UNINSTALL_KEEPING 2070 "A manter ficheiros de dados..."
LangString UNINSTALL_KEEPING 1046 "Mantendo arquivos de dados..."
LangString UNINSTALL_KEEPING 1045 "Zachowywanie plików danych..."
LangString UNINSTALL_KEEPING 1058 "Збереження файлів даних..."
LangString UNINSTALL_KEEPING 1029 "Zachovávám datové soubory..."
LangString UNINSTALL_KEEPING 1051 "Zachovávajú sa dátové súbory..."
LangString UNINSTALL_KEEPING 1038 "Adatfájlok megőrzése..."
LangString UNINSTALL_KEEPING 1025 "الاحتفاظ بملفات البيانات..."
LangString UNINSTALL_KEEPING 1055 "Veri dosyaları korunuyor..."
LangString UNINSTALL_KEEPING 1054 "กำลังเก็บรักษาไฟล์ข้อมูล..."
LangString UNINSTALL_KEEPING 1066 "Đang giữ các tệp dữ liệu..."

; 强制仅当前用户安装，跳过“为所有人安装/仅为当前用户”选择页（与 electron-builder 模板中 customInstallmode 一致）
!macro customInstallmode
  StrCpy $isForceCurrentInstall "1"
!macroend

; 保持默认安装目录，不再从历史安装记录回填自定义路径
!macro customInit
!macroend

!macro customUnInstall
  ; 由安装程序触发的升级/重装时，electron-builder 会传入 --updated，此时 ${isUpdated} 为真，不询问是否删除数据
  ${if} ${isUpdated}
    DetailPrint "Update/reinstall detected, keeping data files..."
    Goto ContinueUninstall
  ${endif}

  ; 完全卸载：询问用户是否删除程序数据文件（使用 LangString 按当前语言显示）
  MessageBox MB_YESNO|MB_ICONQUESTION "$(UNINSTALL_DELETE_DATA_QUESTION)$\r$\n$\r$\n$(UNINSTALL_DELETE_DATA_WARNING)$\r$\n$\r$\n$(UNINSTALL_DELETE_DATA_YESNO)" IDYES DeleteData IDNO KeepData

  DeleteData:
    DetailPrint "$(UNINSTALL_DELETING)"
    RMDir /r "$APPDATA\nascab_os_server"
    RMDir /r "$LOCALAPPDATA\nascab_os_server"
    Goto ContinueUninstall

  KeepData:
    DetailPrint "$(UNINSTALL_KEEPING)"
    Goto ContinueUninstall

  ContinueUninstall:
    ; 继续标准卸载流程
!macroend
