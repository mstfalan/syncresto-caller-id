#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Tek kopya: Caller ID cihazini ayni anda yalniz bir surec dinleyebilir; ikinci kopya
  // cid.dll'i kilitli bulup baglanamiyordu. Zaten aciksa mevcut pencereyi one getir ve cik.
  HANDLE tek_kopya = ::CreateMutexW(nullptr, TRUE, L"Local\\SyncRestoCallerIdTekKopya");
  if (tek_kopya != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Ilk kopyanin penceresi acilis/kapanis aninda olmayabilir: 3 sn bekleyerek ara.
    HWND mevcut = nullptr;
    for (int i = 0; i < 15 && mevcut == nullptr; ++i) {
      mevcut = ::FindWindowW(L"FLUTTER_RUNNER_WIN32_WINDOW", L"SyncResto Caller ID");
      if (mevcut == nullptr) ::Sleep(200);
    }
    if (mevcut != nullptr) {
      if (::IsIconic(mevcut)) ::ShowWindow(mevcut, SW_RESTORE);
      else ::ShowWindow(mevcut, SW_SHOW);
      ::SetForegroundWindow(mevcut);
      ::CloseHandle(tek_kopya);
      return EXIT_SUCCESS;
    }
    // Pencere yok: ilk kopya kapanirken asili kalmis. Uygulamanin hic acilmamasindansa devam et.
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
  if (!window.Create(L"SyncResto Caller ID", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  if (tek_kopya != nullptr) ::CloseHandle(tek_kopya);
  return EXIT_SUCCESS;
}
