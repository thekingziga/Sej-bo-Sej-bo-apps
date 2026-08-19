SEJBOSEJBO - BUILDING THE WINDOWS APP
=====================================

First, the thing that trips everyone up:

  Flutter builds Windows apps for x64 or ARM64. There is NO 32-bit x86
  target, and there has not been one for years. When people say "x86" they
  almost always mean an ordinary Intel/AMD PC, which is x64 - that is what
  this produces.

  The build always matches the machine it runs on. Building on Windows-on-ARM
  (a Parallels VM on an Apple Silicon Mac, a Surface Pro X) gives you an ARM64
  binary that will not start on a normal PC. The script checks for this and
  warns before wasting your time, and checks again afterwards by reading the
  compiled exe's PE header.


WHAT YOU NEED
-------------

  * A Windows 10 or 11 PC, Intel or AMD (not ARM)
  * About 15 GB free - almost all of it Visual Studio
  * An hour, mostly unattended


HOW TO BUILD
------------

  1. Copy this folder onto the Windows PC and extract it.

  2. Open PowerShell in the extracted folder. (Shift + right-click in the
     folder, "Open PowerShell window here".)

  3. Run:

       Set-ExecutionPolicy -Scope Process Bypass -Force
       .\tool\build_windows.ps1

  That is all. The script installs Git and Flutter if missing, offers to
  install Visual Studio with the C++ workload if it is not there, and builds.

  Say yes to the Visual Studio prompt if asked. It is a ~10 GB download and
  by far the longest step; everything else takes minutes.


WHAT YOU GET
------------

  build\windows\x64\runner\Release\

  The whole folder is the app. Copy it anywhere and run sejbosejbo.exe.
  Everything beside the exe - the DLLs and the data folder - is required;
  the exe alone will not start.

  The script prints the exact path and the architecture it produced when it
  finishes. If it says anything other than x64, do not distribute it.


IF SOMETHING GOES WRONG
-----------------------

  "winget is missing"
      Install "App Installer" from the Microsoft Store, then re-run.

  "Cannot build for Windows without the C++ workload"
      Visual Studio needs the "Desktop development with C++" workload
      specifically. Build Tools alone is not enough - flutter doctor will
      keep reporting the Windows toolchain as missing.

  The build stops somewhere in firebase_core
      Its Windows support downloads the Firebase C++ SDK during the first
      build, which is large and occasionally times out. Re-running usually
      works; it is cached afterwards.

  The app starts but shows sample posts
      It was built without API_BASE_URL and is in demo mode. The script
      always passes it, so this means the build was run by hand. Use:

        flutter build windows --release --dart-define=API_BASE_URL=https://sejbosejbo.fyi


NO WINDOWS PC?
--------------

  .github\workflows\build.yml builds x64 on GitHub's runners. Push the repo,
  open the Actions tab, and download the artefact. It is free, it takes about
  ten minutes, and it cannot accidentally produce an ARM64 binary.


WHAT WORKS ON WINDOWS
---------------------

  Everything except the two things Windows has no implementation for:

    * Notifications      - Android/iOS only. Silently absent, nothing breaks.
    * Store billing      - the tip screen uses Stripe in your browser
                           instead, which is also the cheaper path.

  Browsing, voting, comments, uploads, deep links and the theme music all
  work.
