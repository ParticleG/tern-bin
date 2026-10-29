#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: build.sh Tern-<version>-linux-x86_64.tar.gz

Build an unsigned local pacman package in the project's packages/ directory.
Use an authenticated, manually downloaded glibc tarball. No download or install
is performed. PKGREL may be set to a positive integer (default: 1).
EOF
}

if [[ $# == 1 && ( $1 == --help || $1 == -h ) ]]; then
  usage
  exit 0
fi
if [[ $# != 1 ]]; then
  usage >&2
  exit 2
fi

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

(( EUID != 0 )) || fail 'Run this script as a regular user, not with sudo.'
command -v makepkg > /dev/null || fail 'makepkg is required; install base-devel.'

archive_name=${1##*/}
if [[ ! $archive_name =~ ^Tern-([0-9][0-9A-Za-z._+]*)-linux-x86_64\.tar\.gz$ ]]; then
  fail 'Expected Tern-<version>-linux-x86_64.tar.gz; musl and other architectures are not supported.'
fi
version=${BASH_REMATCH[1]}
release=${PKGREL:-1}
[[ $release =~ ^[1-9][0-9]*$ ]] || fail 'PKGREL must be a positive integer.'
archive=$(realpath -e -- "$1")
[[ -f $archive && -r $archive ]] || fail 'The tarball must be a readable regular file.'
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
output_dir="$project_dir/packages"

umask 077
mkdir -p -- "$output_dir"
workspace=$(mktemp -d "$output_dir/.build.XXXXXXXX")
trap 'rm -rf -- "$workspace"' EXIT

archive_sha256=$(sha256sum < "$archive")
archive_sha256=${archive_sha256%% *}
# Project files packaged alongside the tarball, each with its checksum
# placeholder in PKGBUILD.in.
project_files=(
  so.stencil.tern.desktop:DESKTOP_SHA256
  so.stencil.tern.open.desktop:OPEN_DESKTOP_SHA256
  tern-bin-open.desktop:OPEN_TAB_DESKTOP_SHA256
  tern-open-focus:OPEN_FOCUS_SHA256
)
pkgbuild=$(< "$project_dir/PKGBUILD.in")
pkgbuild=${pkgbuild//@VERSION@/$version}
pkgbuild=${pkgbuild//@PKGREL@/$release}
pkgbuild=${pkgbuild//@ARCHIVE_SHA256@/$archive_sha256}
for entry in "${project_files[@]}"; do
  file=${entry%%:*}
  placeholder=${entry#*:}
  checksum=$(sha256sum < "$project_dir/$file")
  pkgbuild=${pkgbuild//@$placeholder@/${checksum%% *}}
  cp -- "$project_dir/$file" "$workspace/"
done
printf '%s\n' "$pkgbuild" > "$workspace/PKGBUILD"
ln -s -- "$archive" "$workspace/$archive_name"

# Command-line assignments override makepkg.conf and isolate beta artifacts
# from any shared source, build, log, or package cache configured by the user.
makepkg_paths=(
  "PKGDEST=$workspace"
  "SRCDEST=$workspace"
  "SRCPKGDEST=$workspace"
  "BUILDDIR=$workspace"
  "LOGDEST=$workspace"
)
cd -- "$workspace"
package_path=$(makepkg --packagelist "${makepkg_paths[@]}")
destination="$output_dir/${package_path##*/}"
[[ ! -e $destination && ! -L $destination ]] || \
  fail "Package already exists: $destination. Choose a new PKGREL to rebuild."

printf 'Source: %s\nSHA256: %s\n' "$archive" "$archive_sha256" >&2
makepkg --cleanbuild --clean --nosign "${makepkg_paths[@]}" >&2
chmod 600 -- "$package_path"
# Both paths are on the same filesystem. Linking publishes the completed
# package without copying it or overwriting an existing build.
ln -- "$package_path" "$destination"
printf 'Package: %s\nInstall: sudo pacman -U -- %q\n' "$destination" "$destination"
