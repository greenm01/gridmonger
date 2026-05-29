{.hints: off.}

import os
import strformat
import strutils


var exeName = "gridmonger".toExe
var exeNameWayland = exeName
var exeNameX11 = exeName
var exeNameMac = exeName
var exeNameWin = exeName
var exeNameMacArm64 = "gridmonger-macos-arm64".toExe
var exeNameMacX64 = "gridmonger-macos-x64".toExe

const rootDir = getCurrentDir()
const version = staticRead("CURRENT_VERSION").strip
const gitHash = strutils.strip(staticExec("git rev-parse --short=5 HEAD"))
const currYear = CompileDate[0..3]

proc packageSrcPath(pkg: string): string =
  let envPath = getEnv(pkg.toUpperAscii & "_PATH")
  if envPath.len > 0:
    return if envPath.lastPathPart == "src": envPath else: envPath / "src"

  when hostOS == "windows":
    result = staticExec("nimble path " & pkg).strip / "src"
  else:
    result = staticExec(
      "find \"$HOME/.nimble/pkgs2\" -maxdepth 1 -type d -name '" &
      pkg & "-*' | sort | tail -n 1"
    ).strip / "src"

const macPackageName = fmt"gridmonger-v{version}-{gitHash}-macos.zip"

const winInstallerPackageName = fmt"gridmonger-v{version}-{gitHash}-windows-setup.exe"
const winPortablePackageName  = fmt"gridmonger-v{version}-{gitHash}-windows-portable.zip"

const dataDir = "Data"
const exampleMapsDir = "Example Maps"
const manualDir = "Manual"
const themesDir = "Themes"

const distDir    = "dist"
const distMacDir = distDir / "macos"
const distWinDir = distDir / "windows"

const distManualName = "gridmonger-manual.zip"
const distMapsName = "gridmonger-example-maps.zip"

const websiteDir = "docs"
const websiteFilesDir = websiteDir / "files"
const websiteReleasesDir = websiteFilesDir / "releases"
const websiteReleasesMacDir = websiteReleasesDir / "macos"
const websiteReleasesWinDir = websiteReleasesDir / "windows"
const websiteExtrasDir = websiteFilesDir / "extras"

const previewWebsiteDir = "docs/preview"

const sphinxDocsDir = "sphinx-docs"


proc setCommonCompileParams(useWayland = false) =
  --mm:orc
  --threads:on
  --deepcopy:on
  --d:ssl
  --d:nimPreviewFloatRoundtrip
  --d:wgpu
  --d:wgvkWGSL
  --d:NoGLFW
  --d:koiWebGpu
  switch "passC", "-Wno-incompatible-pointer-types"
  switch "path", "../koi-webgpu"
  switch "path", packageSrcPath("webgpu")
  switch "nimcache", "/tmp/gridmonger_nimcache"
  --hint:"Name:off"

  if hostOS == "linux" and useWayland:
    --d:wayland
    --d:gridmongerBackendWayland
  elif hostOS == "linux":
    --d:gridmongerBackendX11
  elif hostOS == "macosx":
    --d:gridmongerBackendMac
  elif hostOS == "windows":
    --d:gridmongerBackendWindows

  if hostOS == "windows":
    --dynlibOverride:ssl
    --dynlibOverride:crypto

  switch "out", exeName
  setCommand "c", "src/main"

proc detectLinuxWayland(): bool =
  let requested = getEnv("GRIDMONGER_BACKEND").toLowerAscii
  if requested == "wayland":
    return true
  if requested == "x11":
    return false

  if getEnv("WAYLAND_DISPLAY").len > 0:
    return true
  if getEnv("DISPLAY").len > 0:
    return false

  true

proc createZip(zipName, srcPath: string, extraArgs = "") =
  exec fmt"zip -q -9 -r ""{zipName}"" ""{srcPath}"" {extraArgs}"

# All tasks must be executed from the project root directory!

task version, "get version number":
  echo version

task gitHash, "get Git hash":
  echo gitHash

task versionAndGitHash, "get version and Git hash":
  echo fmt"{version}-{gitHash}"

task debug, "debug build":
  --d:debug
  when hostOS == "linux":
    setCommonCompileParams(useWayland = detectLinuxWayland())
  else:
    setCommonCompileParams()


task debugWayland, "debug build (Linux Wayland)":
  --d:debug
  setCommonCompileParams(useWayland = true)


task debugX11, "debug build (Linux X11)":
  --d:debug
  setCommonCompileParams()


task releaseNoStacktrace, "release build (no stacktrace)":
  --d:release
  --app:gui
  when hostOS == "linux":
    setCommonCompileParams(useWayland = detectLinuxWayland())
  else:
    setCommonCompileParams()


task releaseWayland, "release build (Linux Wayland)":
  --d:release
  --app:gui
  setCommonCompileParams(useWayland = true)


task releaseX11, "release build (Linux X11)":
  --d:release
  --app:gui
  setCommonCompileParams()


task release, "release build":
  --stacktrace:on
  --linetrace:on
  releaseNoStacktraceTask()


task releaseMac, "release build (macOS host)":
  releaseTask()


task releaseWin, "release build (Windows host)":
  releaseTask()


task releaseMacArm64, "release build (macOS arm64)":
  --l:"-target arm64-apple-macos11"
  --t:"-target arm64-apple-macos11"
  exeName = exeNameMacArm64
  releaseTask()


task releaseMacX64, "release build (macOS x86-64)":
  --l:"-target x86_64-apple-macos10.12"
  --t:"-target x86_64-apple-macos10.12"
  exeName = exeNameMacX64
  releaseTask()


task mergeMacUniversal, "create macOS universal binary":
  exec fmt"strip -S {exeNameMacX64}"
  exec fmt"strip -S {exeNameMacArm64}"
  exec fmt"lipo {exeNameMacX64} {exeNameMacArm64} -create -output {exeName}"


task winInstallerPackageName, "get Windows installer package name":
  echo winInstallerPackageName

task winPortablePackageName, "get Windows portable package name":
  echo winPortablePackageName

task packageWinInstaller, "create Windows installer package":
  mkdir distWinDir
  exec fmt"strip -S {exeName}"
  exec fmt"makensis gridmonger.nsi"


task packageWinPortable, "create Windows portable package":
  mkdir distWinDir
  exec fmt"strip -S {exeName}"
  let packageDir = distWinDir / "portable" / "Gridmonger"
  rmDir packageDir
  mkDir packageDir

  # Create config dir
  mkDir packageDir / "Config"

  # We need to put a dummy file into the Config dir, otherwise the GitHub
  # uploader action will exclude it from the ZIP file
  writeFile(packageDir / "Config" / "portable", "dummy")

  # Copy main executable
  cpFile exeName, packageDir / exeName

  # Copy extra Windows dependencies
  for srcPath in listFiles("extras" / "windows-deps"):
    let (_, srcFile) = splitPath(srcPath)
    let outPath = packageDir / srcFile
    cpFile srcPath, outpath

  # Copy resources
  cpDir dataDir, packageDir / dataDir
  cpDir exampleMapsDir, packageDir / exampleMapsDir
  cpDir manualDir, packageDir / manualDir
  cpDir themesDir, packageDir / themesDir

#  let zipName = getWinPortablePackageName(arch)
#  withDir distWinDir:
#    createZip(zipName, srcPath=packageName)
#
#  rmDir packageDir
#

task macPackageName, "get macOS package name":
  echo macPackageName

task packageMac, "create macOS app bundle package":
  let appBundleName = "Gridmonger.app"
  let appBundleDir = distMacDir / appBundleName
  let contentsDir = appBundleDir / "Contents"
  let macOsDir = contentsDir / "MacOS"
  let resourcesDir = contentsDir / "Resources"

  let distExePath = macOsDir / exeName.capitalizeAscii

  rmDir appBundleDir
  mkDir contentsDir

  # Copy plist file & set version
  exec fmt"sed 's/##VERSION##/{version}/g;s/##YEAR##/{currYear}/g' Info.plist >{contentsDir}/Info.plist"

  # Copy main executable
  mkDir macOsDir
  cpFile exeName, distExePath

  # Copy resources
  mkDir resourcesDir
  cpDir dataDir, resourcesDir / dataDir
  cpDir exampleMapsDir, resourcesDir / exampleMapsDir
  cpDir manualDir, resourcesDir / manualDir
  cpDir themesDir, resourcesDir / themesDir
  cpFile "extras/appicons/mac/gridmonger.icns", resourcesDir / "gridmonger.icns"

  # Set executable flags
  exec "chmod +x " & distExePath
  exec "xattr -cr " & distExePath

  exec fmt"codesign --verbose --sign '-' --options runtime --deep {appBundleDir}"
  exec fmt"codesign --verify --deep --strict --verbose=2 {appBundleDir}"

  # Make distribution ZIP file
  withDir distMacDir:
    createZip(zipName=macPackageName, srcPath=appBundleName)
    rmDir appBundleName


task packageManual, "create zipped manual package":
  let outputDir = "Gridmonger Manual"
  cpDir manualDir, outputDir
  mkdir distDir
  rmFile distDir / distManualName
  createZip(zipName=distDir / distManualName, srcPath=outputDir)
  rmDir outputDir


task packageExampleMaps, "create zipped example maps package":
  rmFile distDir / distMapsName
  createZip(zipName=distDir / distMapsName, srcPath=exampleMapsDir, extraArgs="-i *.gmm")


task publishPackageWin, "publish Windows packages to website dir":
  let installerName = winInstallerPackageName
  cpFile distWinDir / installerName, websiteReleasesWinDir / installerName

  let portableName = winPortablePackageName
  cpFile distWinDir / portableName, websiteReleasesWinDir / portableName


task publishPackageMac, "publish macOS package to website dir":
  cpFile distMacDir / macPackageName, websiteReleasesMacDir / macPackageName


task publishExtras, "publish extra packages (manual, example maps) to website dir":
  cpFile distDir / distManualName, websiteExtrasDir / distManualName
  cpFile distDir / distMapsName, websiteExtrasDir / distMapsName


task manual, "build manual":
  withDir sphinxDocsDir:
    exec "make build_manual"


task website, "build website":
  withDir sphinxDocsDir:
    exec "make build_website"

  withDir websiteDir:
    exec "../scripts/indexer.py -r files"


task previewWebsite, "build website":
  withDir sphinxDocsDir:
    exec "make build_website WEBSITE_DIR=../docs/preview"

  withDir previewWebsiteDir:
    exec "../../scripts/indexer.py -r files"


task clean, "clean everything":
  rmFile exeName
  rmFile exeNameMacArm64
  rmFile exeNameMacX64

  rmDir distDir
  rmDir manualDir

  if fileExists(sphinxDocsDir):
    withDir sphinxDocsDir:
      exec "make clean"
