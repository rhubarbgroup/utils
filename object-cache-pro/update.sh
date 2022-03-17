#!/bin/bash

set -e

wpcli=wp

for i in "$@"; do
  case $i in
    -s=*|--source=*)
      src="${i#*=}"
      shift
      ;;
    -w=*|--wp=*)
      wp="${i#*=}"
      shift
      ;;
    -v=*|--version=*)
      version="${i#*=}"
      shift
      ;;
    -t=*|--token=*)
      token="${i#*=}"
      shift
      ;;
    -c=*|--cli=*)
      wpcli="${i#*=}"
      shift
      ;;
    -*|--*)
      echo "Unknown option ${i}"
      exit 1
      ;;
    *)
      ;;
  esac
done

LOGINF="\033[1;36mINFO:\033[0m"
LOGERR="\033[1;31mERROR:\033[0m"

if [ -z "$src" ]; then
  echo -e "${LOGERR} Please specify source." >&2
  exit 1
fi

if [ -z "$wp" ]; then
  echo -e "${LOGERR} Please specify destination." >&2
  exit 1
fi

if [ -z "$token" ]; then
  echo -e "${LOGERR} Please specify license token." >&2
  exit 1
fi

if [ -z "$version" ]; then
  version="stable"
  echo -e "${LOGINF} No version specified, defaulting to latest stable."
fi

echo "Updating Object Cache Pro must-use installation..."
echo "> Source: ${src}"
echo "> WordPress: ${wp}"
echo "> Token: ${token}"
echo "> Version: ${version}"

if [ ! -d "$src" ]; then
  echo "Creating source directory..."
  mkdir -p $src
fi

if [ ! -w "$src" ]; then
  echo -e "${LOGERR} Source is not a writable as $USER." >&2
  exit 1
fi

if [ ! -d "$wp" ]; then
  echo -e "${LOGERR} WordPress path is not a directory." >&2
  exit 1
fi

echo "Preparing for update..."

mudir=$($wpcli eval 'echo WPMU_PLUGIN_DIR;' --skip-plugins --skip-themes --path=$wp)
echo "Detected must-use plugin directory: ${mudir}"

if [ ! -w "$mudir" ]; then
  echo -e "${LOGERR} Must-use plugin directory is not a writable as $USER." >&2
  exit 1
fi

diagnostics=$(cat <<\END
  if (isset($GLOBALS['ObjectCachePro'])) {
    $diagnostics = $GLOBALS['ObjectCachePro']->diagnostics();
    echo (int) ($diagnostics->dropinExists() && $diagnostics->dropinIsValid());
  } else {
    echo 0;
  }
END
)

dropin=$($wpcli eval "${diagnostics}" --skip-plugins --skip-themes --path=$wp)

if [ "$dropin" != "1" ]; then
  echo "Detected valid object cache drop-in"
elif [ "$dropin" != "0" ]; then
  echo "Detected foreign object cache drop-in"
else
  echo -e "${LOGERR} Failed to detect drop-in status." >&2
  exit 1
fi

if [ "$version" != "stable" ]; then
  version="-${version}"
fi

echo "Downloading plugin..."

tmpdir=$(mktemp -d)

curl "https://objectcache.pro/plugin/object-cache-pro${version}.zip?token=${token}" \
  --silent \
  --show-error \
  --location \
  --output $tmpdir/object-cache-pro.zip

echo "Unpacking archive..."

unzip -q $tmpdir/object-cache-pro.zip -d $tmpdir
rm $tmpdir/object-cache-pro.zip

exit 0

echo "Starting update..."

echo "Moving plugin directory..."
mv -f $tmpdir/object-cache-pro $src/object-cache-pro

if [ -d "$mudir/object-cache-pro" ]; then
  echo "Deleting old must-use plugin directory..."
  mv $mudir/object-cache-pro $tmpdir/$RANDOM
fi

echo "Linking must-use plugin directory..."
ln -sfn $src/object-cache-pro $mudir/object-cache-pro

if [ -f "$mudir/redis-cache-pro.php" ]; then
  echo "Deleting old must-use plugin stub..."
  rm $mudir/redis-cache-pro.php
fi

echo "Updating must-use plugin stub..."
cp -f $src/object-cache-pro/stubs/mu-plugin.php $mudir/object-cache-pro.php

if [ "$dropin" != "1" ]; then
  echo "Updating object cache drop-in..."
  $wpcli redis enable --force --skip-flush --skip-flush-notice --skip-plugins --skip-themes --path=$wp
else
  echo "Skipping object cache drop-in."
fi

echo "Resetting opcode cache..."
$wpcli eval 'opcache_reset();' --skip-plugins --skip-themes --path=$wp

echo "Completed update."

if [ -d "$mudir/redis-cache-pro" ]; then
  echo "Deleting old must-use plugin files..."
  rm -rf $mudir/redis-cache-pro
fi

echo "Deleting temporay files..."
rm -rf $tmpdir

echo "Done."
