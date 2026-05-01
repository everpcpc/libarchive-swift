#!/usr/bin/env bash

set -euo pipefail

LIBARCHIVE_VERSION="${LIBARCHIVE_VERSION:-v3.8.7}"
LIBARCHIVE_RELEASE_VERSION="${LIBARCHIVE_VERSION#v}"
LIBARCHIVE_SHA256="${LIBARCHIVE_SHA256:-d3a8ba457ae25c27c84fd2830a2efdcc5b1d40bf585d4eb0d35f47e99e5d4774}"
LIBARCHIVE_ARCHIVE_URL="${LIBARCHIVE_ARCHIVE_URL:-https://github.com/libarchive/libarchive/releases/download/${LIBARCHIVE_VERSION}/libarchive-${LIBARCHIVE_RELEASE_VERSION}.tar.xz}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/.build/libarchive"
SOURCE_DIR="${BUILD_DIR}/source"
SOURCE_ARCHIVE="${BUILD_DIR}/libarchive-${LIBARCHIVE_RELEASE_VERSION}.tar.xz"
ARTIFACT_DIR="${ROOT_DIR}/Artifacts"
XCFRAMEWORK_PATH="${ARTIFACT_DIR}/CArchive.xcframework"

IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"
TVOS_DEPLOYMENT_TARGET="${TVOS_DEPLOYMENT_TARGET:-13.0}"
MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-11.0}"
XROS_DEPLOYMENT_TARGET="${XROS_DEPLOYMENT_TARGET:-1.0}"

COMMON_CMAKE_OPTIONS=(
  -DBUILD_SHARED_LIBS=OFF
  -DENABLE_INSTALL=OFF
  -DENABLE_TEST=OFF
  -DENABLE_TAR=OFF
  -DENABLE_CPIO=OFF
  -DENABLE_CAT=OFF
  -DENABLE_UNZIP=OFF
  -DENABLE_OPENSSL=OFF
  -DENABLE_MBEDTLS=OFF
  -DENABLE_NETTLE=OFF
  -DENABLE_LIBB2=OFF
  -DENABLE_LZ4=OFF
  -DENABLE_LZO=OFF
  -DENABLE_LZMA=OFF
  -DENABLE_ZSTD=OFF
  -DENABLE_BZip2=OFF
  -DENABLE_LIBXML2=OFF
  -DENABLE_EXPAT=OFF
  -DENABLE_PCREPOSIX=OFF
  -DENABLE_PCRE2POSIX=OFF
  -DENABLE_ZLIB=ON
  -DENABLE_ICONV=OFF
  -DENABLE_ACL=OFF
  -DENABLE_XATTR=OFF
  -DHAVE_FORK=0
  -DHAVE_VFORK=0
  -DHAVE_POSIX_SPAWN=0
  -DHAVE_POSIX_SPAWNP=0
  -DCMAKE_BUILD_TYPE=Release
)

prepare_source() {
  mkdir -p "${BUILD_DIR}" "${ARTIFACT_DIR}"

  if [[ ! -f "${SOURCE_ARCHIVE}" ]]; then
    curl -fsSL -o "${SOURCE_ARCHIVE}" "${LIBARCHIVE_ARCHIVE_URL}"
  fi

  local actual_sha256
  actual_sha256="$(shasum -a 256 "${SOURCE_ARCHIVE}" | awk '{print $1}')"

  if [[ "${actual_sha256}" != "${LIBARCHIVE_SHA256}" ]]; then
    echo "SHA256 mismatch for ${SOURCE_ARCHIVE}" >&2
    echo "expected: ${LIBARCHIVE_SHA256}" >&2
    echo "actual:   ${actual_sha256}" >&2
    exit 1
  fi

  rm -rf "${SOURCE_DIR}"
  mkdir -p "${SOURCE_DIR}"
  tar -xJf "${SOURCE_ARCHIVE}" --strip-components 1 -C "${SOURCE_DIR}"
}

write_module_map() {
  local headers_path="$1"

  cat >"${headers_path}/module.modulemap" <<'EOF'
module CArchive {
  header "archive.h"
  header "archive_entry.h"
  export *
}
EOF
}

configure_and_build() {
  local name="$1"
  local sdk="$2"
  local architectures="$3"
  local deployment_target="$4"
  local system_name="$5"
  local build_path="${BUILD_DIR}/${name}"
  local install_path="${BUILD_DIR}/install/${name}"
  local sdk_path

  sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"

  rm -rf "${build_path}" "${install_path}"

  local log_path="${BUILD_DIR}/${name}.log"

  cmake -S "${SOURCE_DIR}" -B "${build_path}" \
    -G Ninja \
    -DCMAKE_SYSTEM_NAME="${system_name}" \
    -DCMAKE_OSX_SYSROOT="${sdk_path}" \
    -DCMAKE_OSX_ARCHITECTURES="${architectures}" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}" \
    -DCMAKE_INSTALL_PREFIX="${install_path}" \
    "${COMMON_CMAKE_OPTIONS[@]}" >"${log_path}" 2>&1

  cmake --build "${build_path}" --target archive_static >>"${log_path}" 2>&1

  local headers_path="${install_path}/include"
  mkdir -p "${headers_path}"
  cp "${SOURCE_DIR}/libarchive/archive.h" "${headers_path}/archive.h"
  cp "${SOURCE_DIR}/libarchive/archive_entry.h" "${headers_path}/archive_entry.h"
  write_module_map "${headers_path}"

  echo "${build_path}/libarchive/libarchive.a|${headers_path}"
}

main() {
  prepare_source

  rm -rf "${XCFRAMEWORK_PATH}"

  local -a framework_args=()
  local build_result

  build_result="$(configure_and_build macosx macosx "arm64;x86_64" "${MACOSX_DEPLOYMENT_TARGET}" Darwin)"
  framework_args+=(-library "${build_result%%|*}" -headers "${build_result##*|}")

  build_result="$(configure_and_build iphoneos iphoneos "arm64" "${IPHONEOS_DEPLOYMENT_TARGET}" iOS)"
  framework_args+=(-library "${build_result%%|*}" -headers "${build_result##*|}")

  build_result="$(configure_and_build iphonesimulator iphonesimulator "arm64;x86_64" "${IPHONEOS_DEPLOYMENT_TARGET}" iOS)"
  framework_args+=(-library "${build_result%%|*}" -headers "${build_result##*|}")

  build_result="$(configure_and_build appletvos appletvos "arm64" "${TVOS_DEPLOYMENT_TARGET}" tvOS)"
  framework_args+=(-library "${build_result%%|*}" -headers "${build_result##*|}")

  build_result="$(configure_and_build appletvsimulator appletvsimulator "arm64;x86_64" "${TVOS_DEPLOYMENT_TARGET}" tvOS)"
  framework_args+=(-library "${build_result%%|*}" -headers "${build_result##*|}")

  if xcrun --sdk xros --show-sdk-path >/dev/null 2>&1; then
    build_result="$(configure_and_build xros xros "arm64" "${XROS_DEPLOYMENT_TARGET}" visionOS)"
    framework_args+=(-library "${build_result%%|*}" -headers "${build_result##*|}")

    build_result="$(configure_and_build xrsimulator xrsimulator "arm64;x86_64" "${XROS_DEPLOYMENT_TARGET}" visionOS)"
    framework_args+=(-library "${build_result%%|*}" -headers "${build_result##*|}")
  fi

  xcodebuild -create-xcframework "${framework_args[@]}" -output "${XCFRAMEWORK_PATH}"
}

main "$@"
