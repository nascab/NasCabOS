#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <windows.h>

#include <string>
#include <vector>

// Creates a console for the process, and redirects stdout and stderr to
// it for both the runner and the Flutter library.
void CreateAndAttachConsole();

// Takes a null-terminated wchar_t* encoded in UTF-16 and returns a std::string
// encoded in UTF-8. Returns an empty std::string on failure.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

// Gets the command line arguments passed in as a std::vector<std::string>,
// encoded in UTF-8. Returns an empty std::vector<std::string> on failure.
std::vector<std::string> GetCommandLineArguments();

// Returns true when another NasCabOS instance is already running and was
// brought to the foreground. When false, |out_mutex| holds the single-instance
// mutex and must be released on application exit.
bool TryActivateExistingInstance(void** out_mutex);

// Handles a show-existing-instance request in the running process.
void HandleShowExistingInstanceMessage(HWND hwnd);

// Returns true when |message| is the cross-process show-window notification.
bool IsShowExistingInstanceMessage(UINT message);

#endif  // RUNNER_UTILS_H_
