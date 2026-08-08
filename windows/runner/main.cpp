#include <app_links/app_links_plugin_c_api.h>
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <regex>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Window class and title of the running instance. Both are defined by the
// Flutter runner (win32_window.cpp) and by the Create() call below; they are
// repeated here because FindWindow needs them before any window exists.
constexpr wchar_t kWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"neximmo_app";

// Custom URI scheme for the desktop auth callback. Must stay in sync with
// desktopAuthCallbackUri in
// lib/features/identity_access/application/desktop_auth_callback.dart.
constexpr wchar_t kAuthScheme[] = L"neximmo";

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
  const LONG result = ::RegSetValueEx(key, name, 0, REG_SZ, bytes, byte_count);
  ::RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

// Registers neximmo: for the current user, pointing at this executable.
//
// Per-user (HKCU) on purpose: it needs no elevation, and it keeps a development
// build from hijacking the scheme for every account on the machine. It also
// means the last build that ran owns the scheme, which is what a developer
// switching between builds wants. A shipped installer must do this under
// HKLM instead, at install time -- see docs/architecture/cloud/06_desktop_auth
// _deep_link.md; running this at startup does not cover packaging.
void RegisterAuthProtocol() {
  wchar_t executable_path[MAX_PATH];
  const DWORD path_length =
      ::GetModuleFileName(nullptr, executable_path, MAX_PATH);
  if (path_length == 0 || path_length == MAX_PATH) {
    return;
  }

  const std::wstring protocol_path =
      std::wstring(L"Software\\Classes\\") + kAuthScheme;
  const std::wstring command_path = protocol_path + L"\\shell\\open\\command";
  const std::wstring command =
      L"\"" + std::wstring(executable_path, path_length) + L"\" \"%1\"";

  SetRegistryString(HKEY_CURRENT_USER, protocol_path.c_str(), nullptr,
                    L"URL:NexImmo Authentication");
  SetRegistryString(HKEY_CURRENT_USER, protocol_path.c_str(), L"URL Protocol",
                    L"");
  SetRegistryString(HKEY_CURRENT_USER, command_path.c_str(), nullptr, command);
}

// True when this process was started by the protocol handler rather than by a
// user opening the app.
//
// The check mirrors AppLinksPlugin::GetLink(), which is what will read the
// argument on the receiving side: exactly one argument, and it must start with
// a URI scheme. Matching it matters -- forwarding a launch the plugin would
// then ignore would close this window without opening anything.
bool LaunchedWithAppLink() {
  int argc = 0;
  wchar_t** argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
  if (argv == nullptr) {
    return false;
  }
  const bool has_single_argument = argc == 2;
  std::wstring argument = has_single_argument ? argv[1] : L"";
  ::LocalFree(argv);
  if (!has_single_argument) {
    return false;
  }

  static const std::wregex scheme_pattern(L"^([a-z][a-z0-9+.-]+):",
                                          std::regex_constants::icase);
  return std::regex_search(argument, scheme_pattern);
}

// Hands the callback to the already-running instance, if there is one.
//
// Without this, clicking the sign-in link while the app is open starts a second
// copy: the new process owns the URI, the process the user is looking at never
// hears about it, and the session lands in the wrong window. SendAppLink is
// exported by the app_links plugin and posts the current command line to the
// target window via WM_COPYDATA, where the plugin turns it into a stream event.
//
// Only protocol launches take this path. Opening the app twice by hand behaves
// as it always did.
bool ForwardAppLinkToRunningInstance() {
  if (!LaunchedWithAppLink()) {
    return false;
  }
  const HWND existing = ::FindWindow(kWindowClass, kWindowTitle);
  if (existing == nullptr) {
    return false;
  }

  SendAppLink(existing);

  // The user clicked a link and expects to end up in the app, not behind it.
  if (::IsIconic(existing)) {
    ::ShowWindow(existing, SW_RESTORE);
  }
  ::SetForegroundWindow(existing);
  return true;
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

  // Warm start: the callback belongs to the instance the user already has open.
  // Done before anything is created so this process leaves no trace.
  if (ForwardAppLinkToRunningInstance()) {
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  // Cold start: the browser must be able to reach this build. app_links reads
  // the URI from the command line and emits it once Dart subscribes.
  RegisterAuthProtocol();

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(kWindowTitle, origin, size)) {
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
