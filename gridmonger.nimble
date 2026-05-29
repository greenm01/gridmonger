# Package

version = "1.2.0"
author = "John Novak <john@johnnovak.net>"
description = "Old-school cRPG mapping companion"
license = "GPL-3.0-or-later"

# Dependencies

requires "nim >= 2.2.4", "osdialog", "riff", "semver", "with"

when hostOS == "windows":
  requires "winim"

# Tasks

import std/os
import std/strformat
import std/strutils

const
  ExeName = "gridmonger".toExe
  ExeNameMacArm64 = "gridmonger-macos-arm64".toExe
  ExeNameMacX64 = "gridmonger-macos-x64".toExe

  DataDir = "Data"
  ExampleMapsDir = "Example Maps"
  ManualDir = "Manual"
  ThemesDir = "Themes"

  DistDir = "dist"
  DistMacDir = DistDir / "macos"
  DistWinDir = DistDir / "windows"

  DistManualName = "gridmonger-manual.zip"
  DistMapsName = "gridmonger-example-maps.zip"

  WebsiteDir = "docs"
  WebsiteFilesDir = WebsiteDir / "files"
  WebsiteReleasesDir = WebsiteFilesDir / "releases"
  WebsiteReleasesMacDir = WebsiteReleasesDir / "macos"
  WebsiteReleasesWinDir = WebsiteReleasesDir / "windows"
  WebsiteExtrasDir = WebsiteFilesDir / "extras"

  PreviewWebsiteDir = "docs/preview"
  SphinxDocsDir = "sphinx-docs"

type BuildMode = enum
  bmDebug
  bmReleaseNoStacktrace
  bmRelease

proc sh(cmd: string) =
  exec cmd

proc removeFileIfExists(path: string) =
  if fileExists(path):
    rmFile(path)

proc removeDirIfExists(path: string) =
  if dirExists(path):
    rmDir(path)

proc projectVersion(): string =
  readFile("CURRENT_VERSION").strip()

proc gitHash(): string =
  gorge("git rev-parse --short=5 HEAD").strip()

proc packageSrcPath(pkg: string): string =
  let envPath = getEnv(pkg.toUpperAscii & "_PATH")
  if envPath.len > 0:
    return
      if envPath.lastPathPart == "src":
        envPath
      else:
        envPath / "src"

  when hostOS == "windows":
    result = gorge("nimble path " & pkg).strip() / "src"
  else:
    result =
      gorge(
        "find \"$HOME/.nimble/pkgs2\" -maxdepth 1 -type d -name '" & pkg &
          "-*' | sort | tail -n 1"
      )
      .strip() / "src"

proc koiSrcPath(): string =
  let envPath = getEnv("KOI_PATH")
  if envPath.len > 0:
    return envPath
  result = parentDir(getCurrentDir()) / "koi-webgpu"

proc detectedLinuxBackend(): string =
  let requested = getEnv("GRIDMONGER_BACKEND").toLowerAscii()
  case requested
  of "", "auto":
    discard
  of "wayland", "x11":
    return requested
  else:
    quit "GRIDMONGER_BACKEND must be 'wayland', 'x11', or unset"

  if getEnv("WAYLAND_DISPLAY").len > 0:
    return "wayland"
  if getEnv("DISPLAY").len > 0:
    return "x11"
  "wayland"

proc hostBackend(): string =
  when hostOS == "linux":
    detectedLinuxBackend()
  elif hostOS == "macosx":
    "mac"
  elif hostOS == "windows":
    "windows"
  else:
    quit "Unsupported host OS: " & hostOS

proc validateBackend(backend: string) =
  when hostOS == "linux":
    if backend notin ["wayland", "x11"]:
      quit "Linux builds require backend 'wayland' or 'x11'"
  elif hostOS == "macosx":
    if backend != "mac":
      quit "macOS builds require backend 'mac'"
  elif hostOS == "windows":
    if backend != "windows":
      quit "Windows builds require backend 'windows'"
  else:
    quit "Unsupported host OS: " & hostOS

proc backendFlags(backend: string): string =
  case backend
  of "wayland":
    "-d:wayland -d:gridmongerBackendWayland"
  of "x11":
    "-d:gridmongerBackendX11"
  of "mac":
    "-d:gridmongerBackendMac"
  of "windows":
    "-d:gridmongerBackendWindows"
  else:
    quit "Unsupported backend: " & backend

proc commonFlags(backend: string): string =
  validateBackend(backend)
  result =
    "--mm:orc --threads:on --deepcopy:on -d:ssl " &
    "-d:nimPreviewFloatRoundtrip -d:wgpu -d:wgvkWGSL -d:NoGLFW " &
    "-d:koiWebGpu --passC:-Wno-incompatible-pointer-types --passC:-D_GNU_SOURCE " &
    "--path:" & quoteShell(koiSrcPath()) & " " & "--path:" &
    quoteShell(packageSrcPath("webgpu")) & " " &
    "--nimcache:/tmp/gridmonger_nimcache --hint:Name:off " & backendFlags(backend)

  when hostOS == "linux":
    result.add " -d:osdialogGtk3"

  when hostOS == "windows":
    result.add " --dynlibOverride:ssl --dynlibOverride:crypto"

proc modeFlags(mode: BuildMode): string =
  case mode
  of bmDebug: "-d:debug"
  of bmReleaseNoStacktrace: "-d:release --app:gui"
  of bmRelease: "-d:release --app:gui --stacktrace:on --linetrace:on"

proc compileGridmonger(
    mode: BuildMode, backend = hostBackend(), outPath = ExeName, extraFlags = ""
) =
  let flags = commonFlags(backend) & " " & modeFlags(mode) & " " & extraFlags
  echo "Building " & outPath & " (" & backend & ")"
  sh "nim c " & flags & " --out:" & quoteShell(outPath) & " " & quoteShell("src/main")

proc createZip(zipName, srcPath: string, extraArgs = "") =
  sh "zip -q -9 -r " & quoteShell(zipName) & " " & quoteShell(srcPath) & " " & extraArgs

proc packageVersionTag(): string =
  projectVersion() & "-" & gitHash()

task version, "get version number":
  echo projectVersion()

task gitHash, "get Git hash":
  echo gitHash()

task versionAndGitHash, "get version and Git hash":
  echo packageVersionTag()

task debug, "debug build for the current platform":
  compileGridmonger(bmDebug)

task debugWayland, "debug build (Linux Wayland)":
  compileGridmonger(bmDebug, backend = "wayland")

task debugX11, "debug build (Linux X11)":
  compileGridmonger(bmDebug, backend = "x11")

task releaseNoStacktrace, "release build for the current platform (no stacktrace)":
  compileGridmonger(bmReleaseNoStacktrace)

task release, "release build for the current platform":
  compileGridmonger(bmRelease)

task releaseWayland, "release build (Linux Wayland)":
  compileGridmonger(bmRelease, backend = "wayland")

task releaseX11, "release build (Linux X11)":
  compileGridmonger(bmRelease, backend = "x11")

task releaseMac, "release build (macOS host)":
  compileGridmonger(bmRelease, backend = "mac")

task releaseWin, "release build (Windows host)":
  compileGridmonger(bmRelease, backend = "windows")

task releaseMacArm64, "release build (macOS arm64)":
  compileGridmonger(
    bmRelease,
    backend = "mac",
    outPath = ExeNameMacArm64,
    extraFlags =
      "--passL:\"-target arm64-apple-macos11\" --passC:\"-target arm64-apple-macos11\"",
  )

task releaseMacX64, "release build (macOS x86-64)":
  compileGridmonger(
    bmRelease,
    backend = "mac",
    outPath = ExeNameMacX64,
    extraFlags =
      "--passL:\"-target x86_64-apple-macos10.12\" --passC:\"-target x86_64-apple-macos10.12\"",
  )

task mergeMacUniversal, "create macOS universal binary":
  sh "strip -S " & quoteShell(ExeNameMacX64)
  sh "strip -S " & quoteShell(ExeNameMacArm64)
  sh "lipo " & quoteShell(ExeNameMacX64) & " " & quoteShell(ExeNameMacArm64) &
    " -create -output " & quoteShell(ExeName)

task winInstallerPackageName, "get Windows installer package name":
  echo fmt"gridmonger-v{packageVersionTag()}-windows-setup.exe"

task winPortablePackageName, "get Windows portable package name":
  echo fmt"gridmonger-v{packageVersionTag()}-windows-portable.zip"

task packageWinInstaller, "create Windows installer package":
  mkDir DistWinDir
  sh "strip -S " & quoteShell(ExeName)
  sh "makensis gridmonger.nsi"

task packageWinPortable, "create Windows portable package":
  mkDir DistWinDir
  sh "strip -S " & quoteShell(ExeName)

  let packageDir = DistWinDir / "portable" / "Gridmonger"
  removeDirIfExists(packageDir)
  mkDir(packageDir / "Config")
  writeFile(packageDir / "Config" / "portable", "dummy")

  cpFile(ExeName, packageDir / ExeName)

  for srcPath in listFiles("extras" / "windows-deps"):
    let (_, srcFile) = splitPath(srcPath)
    cpFile(srcPath, packageDir / srcFile)

  cpDir(DataDir, packageDir / DataDir)
  cpDir(ExampleMapsDir, packageDir / ExampleMapsDir)
  cpDir(ManualDir, packageDir / ManualDir)
  cpDir(ThemesDir, packageDir / ThemesDir)

task macPackageName, "get macOS package name":
  echo fmt"gridmonger-v{packageVersionTag()}-macos.zip"

task packageMac, "create macOS app bundle package":
  let
    appBundleName = "Gridmonger.app"
    appBundleDir = DistMacDir / appBundleName
    contentsDir = appBundleDir / "Contents"
    macOsDir = contentsDir / "MacOS"
    resourcesDir = contentsDir / "Resources"
    distExePath = macOsDir / ExeName.capitalizeAscii()

  removeDirIfExists(appBundleDir)
  mkDir contentsDir

  let plistPath = quoteShell(contentsDir / "Info.plist")
  sh fmt"sed 's/##VERSION##/{projectVersion()}/g;s/##YEAR##/{CompileDate[0..3]}/g' Info.plist >{plistPath}"

  mkDir macOsDir
  cpFile(ExeName, distExePath)

  mkDir resourcesDir
  cpDir(DataDir, resourcesDir / DataDir)
  cpDir(ExampleMapsDir, resourcesDir / ExampleMapsDir)
  cpDir(ManualDir, resourcesDir / ManualDir)
  cpDir(ThemesDir, resourcesDir / ThemesDir)
  cpFile("extras/appicons/mac/gridmonger.icns", resourcesDir / "gridmonger.icns")

  sh "chmod +x " & quoteShell(distExePath)
  sh "xattr -cr " & quoteShell(distExePath)
  sh "codesign --verbose --sign '-' --options runtime --deep " & quoteShell(
    appBundleDir
  )
  sh "codesign --verify --deep --strict --verbose=2 " & quoteShell(appBundleDir)

  mkDir DistMacDir
  withDir DistMacDir:
    createZip(
      zipName = fmt"gridmonger-v{packageVersionTag()}-macos.zip",
      srcPath = appBundleName,
    )
    rmDir appBundleName

task packageManual, "create zipped manual package":
  let outputDir = "Gridmonger Manual"
  removeDirIfExists(outputDir)
  cpDir(ManualDir, outputDir)
  mkDir DistDir
  removeFileIfExists(DistDir / DistManualName)
  createZip(zipName = DistDir / DistManualName, srcPath = outputDir)
  rmDir outputDir

task packageExampleMaps, "create zipped example maps package":
  mkDir DistDir
  removeFileIfExists(DistDir / DistMapsName)
  createZip(
    zipName = DistDir / DistMapsName, srcPath = ExampleMapsDir, extraArgs = "-i *.gmm"
  )

task publishPackageWin, "publish Windows packages to website dir":
  let
    installerName = fmt"gridmonger-v{packageVersionTag()}-windows-setup.exe"
    portableName = fmt"gridmonger-v{packageVersionTag()}-windows-portable.zip"
  cpFile(DistWinDir / installerName, WebsiteReleasesWinDir / installerName)
  cpFile(DistWinDir / portableName, WebsiteReleasesWinDir / portableName)

task publishPackageMac, "publish macOS package to website dir":
  let packageName = fmt"gridmonger-v{packageVersionTag()}-macos.zip"
  cpFile(DistMacDir / packageName, WebsiteReleasesMacDir / packageName)

task publishExtras, "publish extra packages (manual, example maps) to website dir":
  cpFile(DistDir / DistManualName, WebsiteExtrasDir / DistManualName)
  cpFile(DistDir / DistMapsName, WebsiteExtrasDir / DistMapsName)

task manual, "build manual":
  withDir SphinxDocsDir:
    sh "make build_manual"

task website, "build website":
  withDir SphinxDocsDir:
    sh "make build_website"

  withDir WebsiteDir:
    sh "../scripts/indexer.py -r files"

task previewWebsite, "build preview website":
  withDir SphinxDocsDir:
    sh "make build_website WEBSITE_DIR=../docs/preview"

  withDir PreviewWebsiteDir:
    sh "../../scripts/indexer.py -r files"

task clean, "clean everything":
  removeFileIfExists ExeName
  removeFileIfExists ExeNameMacArm64
  removeFileIfExists ExeNameMacX64
  removeFileIfExists "gridmonger-wayland".toExe
  removeFileIfExists "gridmonger-x11".toExe

  removeDirIfExists DistDir
  removeDirIfExists ManualDir

  if dirExists(SphinxDocsDir):
    withDir SphinxDocsDir:
      sh "make clean"

task tidy, "format Nim sources and remove generated binaries":
  for path in walkDirRec("."):
    if path.startsWith("./.git") or path.startsWith("./docs") or
        path.startsWith("./sphinx-docs"):
      continue
    if path.endsWith(".nim") or path.endsWith(".nims") or path.endsWith(".nimble"):
      sh "nph " & quoteShell(path)

  removeFileIfExists ExeName
  removeFileIfExists ExeNameMacArm64
  removeFileIfExists ExeNameMacX64
  removeFileIfExists "gridmonger-wayland".toExe
  removeFileIfExists "gridmonger-x11".toExe
