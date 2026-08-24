#include "utils.h"

#include <flutter_windows.h>
#include <io.h>
#include <stdio.h>
#include <windows.h>

#include <iostream>

namespace {

constexpr wchar_t kSingleInstanceMutexName[] = L"Global\\NasCabOS_SingleInstance";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kExecutableName[] = L"NasCabOS.exe";
constexpr wchar_t kShowExistingInstanceMessageName[] =
    L"NasCabOS_ShowExistingInstance";

UINT GetShowExistingInstanceMessageId() {
  static const UINT message_id =
      RegisterWindowMessageW(kShowExistingInstanceMessageName);
  return message_id;
}

struct FindMainWindowData {
  HWND found_hwnd = nullptr;
};

BOOL CALLBACK FindMainWindowProc(HWND hwnd, LPARAM lparam) {
  auto* data = reinterpret_cast<FindMainWindowData*>(lparam);

  wchar_t class_name[256] = {};
  if (GetClassNameW(hwnd, class_name, 256) == 0) {
    return TRUE;
  }
  if (wcscmp(class_name, kWindowClassName) != 0) {
    return TRUE;
  }

  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid == 0 || pid == GetCurrentProcessId()) {
    return TRUE;
  }

  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) {
    return TRUE;
  }

  wchar_t exe_path[MAX_PATH] = {};
  DWORD size = MAX_PATH;
  bool is_nascab = false;
  if (QueryFullProcessImageNameW(process, 0, exe_path, &size)) {
    const wchar_t* exe_name = wcsrchr(exe_path, L'\\');
    exe_name = exe_name ? exe_name + 1 : exe_path;
    is_nascab = (_wcsicmp(exe_name, kExecutableName) == 0);
  }
  CloseHandle(process);

  if (is_nascab) {
    data->found_hwnd = hwnd;
    return FALSE;
  }
  return TRUE;
}

HWND FindExistingNasCabOSWindow() {
  FindMainWindowData data;
  EnumWindows(FindMainWindowProc, reinterpret_cast<LPARAM>(&data));
  return data.found_hwnd;
}

void BringWindowToForeground(HWND hwnd) {
  if (!hwnd) {
    return;
  }

  if (!IsWindowVisible(hwnd)) {
    ShowWindow(hwnd, SW_SHOW);
  }
  if (IsIconic(hwnd)) {
    ShowWindow(hwnd, SW_RESTORE);
  } else {
    ShowWindow(hwnd, SW_SHOWNORMAL);
  }

  HWND foreground_window = GetForegroundWindow();
  DWORD foreground_thread =
      GetWindowThreadProcessId(foreground_window, nullptr);
  DWORD target_thread = GetWindowThreadProcessId(hwnd, nullptr);
  DWORD current_thread = GetCurrentThreadId();

  AttachThreadInput(current_thread, foreground_thread, TRUE);
  AttachThreadInput(current_thread, target_thread, TRUE);
  SetForegroundWindow(hwnd);
  AttachThreadInput(current_thread, target_thread, FALSE);
  AttachThreadInput(current_thread, foreground_thread, FALSE);
}

void NotifyExistingInstance(HWND hwnd) {
  if (!hwnd) {
    return;
  }

  const UINT message_id = GetShowExistingInstanceMessageId();
  if (message_id != 0) {
    DWORD_PTR result = 0;
    SendMessageTimeoutW(hwnd, message_id, 0, 0, SMTO_ABORTIFHUNG, 3000,
                        &result);
    return;
  }

  BringWindowToForeground(hwnd);
}

}  // namespace

void CreateAndAttachConsole() {
  if (::AllocConsole()) {
    FILE *unused;
    if (freopen_s(&unused, "CONOUT$", "w", stdout)) {
      _dup2(_fileno(stdout), 1);
    }
    if (freopen_s(&unused, "CONOUT$", "w", stderr)) {
      _dup2(_fileno(stdout), 2);
    }
    std::ios::sync_with_stdio();
    FlutterDesktopResyncOutputStreams();
  }
}

std::vector<std::string> GetCommandLineArguments() {
  // Convert the UTF-16 command line arguments to UTF-8 for the Engine to use.
  int argc;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return std::vector<std::string>();
  }

  std::vector<std::string> command_line_arguments;

  // Skip the first argument as it's the binary name.
  for (int i = 1; i < argc; i++) {
    command_line_arguments.push_back(Utf8FromUtf16(argv[i]));
  }

  ::LocalFree(argv);

  return command_line_arguments;
}

bool TryActivateExistingInstance(void** out_mutex) {
  *out_mutex = nullptr;

  HANDLE mutex = CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    if (mutex) {
      CloseHandle(mutex);
    }
    NotifyExistingInstance(FindExistingNasCabOSWindow());
    return true;
  }

  *out_mutex = mutex;
  return false;
}

void HandleShowExistingInstanceMessage(HWND hwnd) {
  BringWindowToForeground(hwnd);
}

bool IsShowExistingInstanceMessage(UINT message) {
  const UINT message_id = GetShowExistingInstanceMessageId();
  return message_id != 0 && message == message_id;
}

std::string Utf8FromUtf16(const wchar_t* utf16_string) {
  if (utf16_string == nullptr) {
    return std::string();
  }
  unsigned int target_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      -1, nullptr, 0, nullptr, nullptr)
    -1; // remove the trailing null character
  int input_length = (int)wcslen(utf16_string);
  std::string utf8_string;
  if (target_length == 0 || target_length > utf8_string.max_size()) {
    return utf8_string;
  }
  utf8_string.resize(target_length);
  int converted_length = ::WideCharToMultiByte(
      CP_UTF8, WC_ERR_INVALID_CHARS, utf16_string,
      input_length, utf8_string.data(), target_length, nullptr, nullptr);
  if (converted_length == 0) {
    return std::string();
  }
  return utf8_string;
}
