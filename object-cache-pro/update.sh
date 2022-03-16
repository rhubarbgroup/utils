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
  echo -e "${LOGERR} No version specified, defaulting to latest stable."
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

echo "Detecting WordPress..."

wpver=$($wpcli eval 'global $wp_version; echo $wp_version;' --skip-plugins --skip-themes --path=$wp)
echo "Found WordPress: ${wpver}"

mudir=$($wpcli eval 'echo WPMU_PLUGIN_DIR;' --skip-plugins --skip-themes --path=$wp)
echo "Found mu-plugin path: ${mudir}"

if [ ! -w "$mudir" ]; then
  echo -e "${LOGERR} Must-use plugin directory is not a writable as $USER." >&2
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

# Atomic release
# `mv -f $tmpdir/object-cache-pro $src/object-cache-pro`
# TODO: symlink $dest and $src (nuke if directory)
# `rm $mudir/redis-cache-pro.php` (migration) 
# `cp $src/object-cache-pro/stubs/mu-plugin.php $mudir/object-cache-pro.php`
# (if active) `$wpcli redis enable --skip-flush --skip-flush-notice`

echo "Resetting opcode cache..."
$wpcli eval 'opcache_reset();' --skip-plugins --skip-themes --path=$wp

# `rm -rf $dest/redis-cache-pro` (migration)

echo "Done."