#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

bool SetRegistryString(HKEY root, const wchar_t* path, const wchar_t* name,
                       const std::wstring& value) {
  HKEY key = nullptr;
  if (::RegCreateKeyEx(root, path, 0, nullptr, REG_OPTION_NON_VOLATILE,
                       KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }

  const auto* bytes = reinterpret_cast<const BYTE*>(value.c_str());
  const DWORD byte_count =
      static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  const LONG result =
      ::RegSetValueEx(key, name, 0, REG_SZ, bytes, byte_count);
  ::RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

void RegisterAuthProtocol() {
  wchar_t executable_path[MAX_PATH];
  const DWORD path_length =
      ::GetModuleFileName(nullptr, executable_path, MAX_PATH);
  if (path_length == 0 || path_length == MAX_PATH) {
    return;
  }

  constexpr wchar_t protocol_path[] = L"Software\\Classes\\neximmo";
  constexpr wchar_t command_path[] =
      L"Software\\Classes\\neximmo\\shell\\open\\command";
  const std::wstring command =
      L"\"" + std::wstring(executable_path, path_length) + L"\" \"%1\"";

  SetRegistryString(HKEY_CURRENT_USER, protocol_path, nullptr,
                    L"URL:NexImmo Authentication");
  SetRegistryString(HKEY_CURRENT_USER, protocol_path, L"URL Protocol", L"");
  SetRegistryString(HKEY_CURRENT_USER, command_path, nullptr, command);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Register the passwordless callback per user so a mail-client click can
  // cold-start this exact build and hand the URI to app_links.
  RegisterAuthProtocol();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"neximmo_app", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
