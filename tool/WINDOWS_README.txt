SEJBOSEJBO - building the Windows app
=====================================

WHAT THIS IS
  The complete source for the Sejbosejbo app. Windows binaries cannot be
  cross-compiled from a Mac, so this has to be built on the Windows PC itself.

BEFORE YOU START
  You need about 12 GB free. Almost all of that is Visual Studio, which the
  script installs if it is missing. The rest takes minutes.

HOW TO BUILD
  1. Extract this zip somewhere simple, e.g.  C:\dev\sejbosejbo
     Avoid OneDrive or a network drive - deep CMake paths break there.

  2. Open PowerShell AS ADMINISTRATOR, cd into the folder, and run:

       Set-ExecutionPolicy -Scope Process Bypass -Force
       .\tool\build_windows.ps1

  3. Wait. First build is slow (Flutter downloads its engine, and Visual
     Studio is ~10 GB if it is not already there). Later builds take under
     a minute.

  4. When it finishes it prints the path to sejbosejbo.exe.

WHAT YOU GET
  build\windows\x64\runner\Release\
      sejbosejbo.exe        <- the app
      *.dll                 <- required, do not delete
      data\                 <- required, do not delete

  The whole Release folder IS the app. Copy the folder, not just the exe -
  on its own the exe will not start.

  (On a Windows-on-ARM machine the folder is arm64\ instead of x64\.)

NOTES
  - The app talks to the live site at https://sejbosejbo.fyi. Anything you
    post from it is public immediately, same as the phone app.
  - Windows will likely show a SmartScreen warning the first time, because
    the exe is not code-signed. "More info" -> "Run anyway". Signing needs a
    paid certificate; it is not needed to run it yourself.
  - No keystore, password or other secret is in this zip.

TROUBLE
  "winget is not recognized"
      Install "App Installer" from the Microsoft Store, reopen PowerShell.

  "cannot be loaded because running scripts is disabled"
      You skipped the Set-ExecutionPolicy line in step 2.

  flutter doctor complains about Android
      Ignore it. Android is irrelevant here; only the Visual Studio line
      matters for a Windows build.
