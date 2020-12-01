#!/bin/sh

if [ "$(id -u)" = "0" ]; then
   echo "Running as root will mess up file permissions. Aborting ..." 1>&2
   exit 1
fi

die()
{
  echo ERROR: $*
  exit 1
}

# Check for whitespace in absolute path; this will cause problems in the
# SpiderMonkey build (https://bugzilla.mozilla.org/show_bug.cgi?id=459089)
# and maybe elsewhere, so we just forbid it
# Use perl as an alternative to readlink -f, which isn't available on BSD or OS X
SCRIPTPATH=`perl -MCwd -e 'print Cwd::abs_path shift' "$0"`
case "$SCRIPTPATH" in
  *\ * )
    die "Absolute path contains whitespace, which will break the build - move the game to a path without spaces" ;;
esac

JOBS=${JOBS:="-j2"}

# Some of our makefiles depend on GNU make, so we set some sane defaults if MAKE
# is not set.
case "`uname -s`" in
  "FreeBSD" | "OpenBSD" )
    MAKE=${MAKE:="gmake"}
    ;;
  * )
    MAKE=${MAKE:="make"}
    ;;
esac

# Parse command-line options:

premake_args=""

with_system_premake5=false
without_nvtt=false
with_system_nvtt=false
with_system_mozjs=false
enable_atlas=true

for i in "$@"
do
  case $i in
    --with-system-premake5 ) with_system_premake5=true ;;
    --without-nvtt ) without_nvtt=true; premake_args="${premake_args} --without-nvtt" ;;
    --with-system-nvtt ) with_system_nvtt=true; premake_args="${premake_args} --with-system-nvtt" ;;
    --with-system-mozjs ) with_system_mozjs=true; premake_args="${premake_args} --with-system-mozjs" ;;
    --enable-atlas ) enable_atlas=true ;;
    --disable-atlas ) enable_atlas=false ;;
    -j* ) JOBS=$i ;;
    # Assume any other --options are for Premake
    --* ) premake_args="${premake_args} $i" ;;
  esac
done

if [ "$enable_atlas" = "true" ]; then
  premake_args="${premake_args} --atlas"
fi

cd "$(dirname $0)"
# Now in build/workspaces/ (where we assume this script resides)

if [ "`uname -s`" = "Darwin" ]; then
  # Set minimal SDK version
  export MIN_OSX_VERSION=${MIN_OSX_VERSION:="10.12"}

  # Set *_CONFIG variables on OS X, to override the path to e.g. sdl2-config
  export GLOOX_CONFIG=${GLOOX_CONFIG:="$(pwd)/../../libraries/osx/gloox/bin/gloox-config"}
  export ICU_CONFIG=${ICU_CONFIG:="$(pwd)/../../libraries/osx/icu/bin/icu-config"}
  export SDL2_CONFIG=${SDL2_CONFIG:="$(pwd)/../../libraries/osx/sdl2/bin/sdl2-config"}
  export WX_CONFIG=${WX_CONFIG:="$(pwd)/../../libraries/osx/wxwidgets/bin/wx-config"}
  export XML2_CONFIG=${XML2_CONFIG:="$(pwd)/../../libraries/osx/libxml2/bin/xml2-config"}
fi

# Don't want to build bundled libs on OS X
# (build-osx-libs.sh is used instead)
if [ "`uname -s`" != "Darwin" ]; then
  echo "Updating bundled third-party dependencies..."
  echo

  # Build/update bundled external libraries
  (cd ../../libraries/source/fcollada && MAKE=${MAKE} JOBS=${JOBS} ./build.sh) || die "FCollada build failed"
  echo
  if [ "$with_system_mozjs" = "false" ]; then
    (cd ../../libraries/source/spidermonkey && MAKE=${MAKE} JOBS=${JOBS} ./build.sh) || die "SpiderMonkey build failed"
  fi
  echo
  if [ "$with_system_nvtt" = "false" ] && [ "$without_nvtt" = "false" ]; then
    (cd ../../libraries/source/nvtt && MAKE=${MAKE} JOBS=${JOBS} ./build.sh) || die "NVTT build failed"
  fi
  echo
fi

# Now run premake to create the makefiles

premake_command="premake5"
if [ "$with_system_premake5" = "false" ]; then
  # Build bundled premake
  cd ../premake/premake5
  PREMAKE_BUILD_DIR=build/gmake.unix
  # BSD and OS X need different Makefiles
  case "`uname -s`" in
    "GNU/kFreeBSD" )
      # use default gmake.unix (needs -ldl as we have a GNU userland and libc)
      ;;
    *"BSD" )
      PREMAKE_BUILD_DIR=build/gmake.bsd
      ;;
    "Darwin" )
      PREMAKE_BUILD_DIR=build/gmake.macosx
      ;;
  esac
  ${MAKE} -C $PREMAKE_BUILD_DIR ${JOBS} || die "Premake build failed"

  premake_command="premake5/bin/release/premake5"
fi

echo

cd ..

# If we're in bash then make HOSTTYPE available to Premake, for primitive arch-detection
export HOSTTYPE="$HOSTTYPE"

echo "Premake args: ${premake_args}"
if [ "`uname -s`" != "Darwin" ]; then
  ${premake_command} --file="premake5.lua" --outpath="../workspaces/gcc/" ${premake_args} gmake || die "Premake failed"
else
  ${premake_command} --file="premake5.lua" --outpath="../workspaces/gcc/" --macosx-version-min="${MIN_OSX_VERSION}" ${premake_args} gmake || die "Premake failed"
  # Also generate xcode workspaces if on OS X
  ${premake_command} --file="premake5.lua" --outpath="../workspaces/xcode4" --macosx-version-min="${MIN_OSX_VERSION}" ${premake_args} xcode4 || die "Premake failed"
fi

# test_root.cpp gets generated by cxxtestgen and passing different arguments to premake could require a regeneration of this file.
# It doesn't depend on anything in the makefiles, so make won't notice that the prebuild command for creating test_root.cpp needs to be triggered.
# We force this by deleting the file.
rm -f ../../source/test_root.cpp
