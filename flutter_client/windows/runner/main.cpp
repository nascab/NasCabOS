#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  void* single_instance_mutex = nullptr;
  if (TryActivateExistingInstance(&single_instance_mutex)) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"NasCabOS", origin, size)) {
    return EXIT_FAILURE;
  }
  // Consistent with window_manager hide/tray: do not PostQuitMessage on WM_DESTROY,
  // otherwise hiding the window might still exit the message loop.
  // Real exit is triggered by calling destroy from Dart side tray "quit".
  window.SetQuitOnClose(false);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex) {
    ReleaseMutex(static_cast<HANDLE>(single_instance_mutex));
    CloseHandle(static_cast<HANDLE>(single_instance_mutex));
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
