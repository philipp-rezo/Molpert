#[========================================================================[.rst:
RDKitWheel
----------

Sets up the RDKit and Boost dependencies using the ``rdkit`` wheel from PyPI,
as installed in the environment of ``Python3_EXECUTABLE``.

The wheel ships the RDKit and Boost shared libraries but not their headers.
This module downloads the headers matching the RDKit and Boost versions the
wheel was built with, and recreates the headers the RDKit generates at build
time. The Python module is then linked against the wheel's libraries, so that
at runtime it shares them with the ``rdkit`` Python package.

Cache Variables
^^^^^^^^^^^^^^^

`MOLPERT_RDKIT_SOURCE_DIR`
  Existing RDKit source tree to use instead of downloading one.
  Must match the version of the installed ``rdkit`` wheel.
`MOLPERT_BOOST_INCLUDE_DIR`
  Existing Boost include directory to use instead of downloading one.
  Must match the Boost version of the installed ``rdkit`` wheel.
`MOLPERT_DEPS_DIR`
  Directory where downloaded headers are kept between builds.

Every download is checked against a SHA256 pinned in RDKitWheelHashes.cmake.

Result Variables
^^^^^^^^^^^^^^^^

This will define the following variables:

`RDKit_VERSION`
  The version of the RDKit wheel.
`RDKit_INCLUDE_DIRS`
  Include directories needed to use RDKit.
`Boost_INCLUDE_DIRS`
  Include directories needed to use Boost.
`BoostPython_INCLUDE_DIRS`
  Include directories needed to use Boost Python.
`BoostPython_LIBRARY`
  Path to Boost Python library.
`RDKit_WHEEL_RPATH`
  RPATH pointing from site-packages to the wheel's library directory.

It also defines an imported target ``RDKit<Name>`` for every RDKit library
Molpert links against.

#]========================================================================]

set(MOLPERT_RDKIT_SOURCE_DIR "" CACHE PATH
  "RDKit source tree matching the rdkit wheel (downloaded if empty)")
set(MOLPERT_BOOST_INCLUDE_DIR "" CACHE PATH
  "Boost include directory matching the rdkit wheel (downloaded if empty)")

if(WIN32)
  message(FATAL_ERROR
    "Building against the rdkit wheel is not supported on Windows. "
    "Build with -DMOLPERT_RDKIT_WHEEL=OFF against a conda RDKit instead.")
endif()

# Ask the rdkit wheel where it lives and how it was built.
execute_process(
  COMMAND ${Python3_EXECUTABLE} -c
    "import os, sys\nfrom rdkit import rdBase as b\nprint(os.path.dirname(b.__file__), b.rdkitVersion, b.boostVersion, '%d%d' % sys.version_info[:2], sep='|', end='')"
  OUTPUT_VARIABLE RDKIT_WHEEL_INFO
  RESULT_VARIABLE RDKIT_WHEEL_RESULT)
if(NOT RDKIT_WHEEL_RESULT EQUAL 0)
  message(FATAL_ERROR
    "Could not import rdkit with ${Python3_EXECUTABLE}. "
    "Install it with: pip install rdkit")
endif()
string(REPLACE "|" ";" RDKIT_WHEEL_INFO "${RDKIT_WHEEL_INFO}")
list(GET RDKIT_WHEEL_INFO 0 RDKIT_WHEEL_DIR)
list(GET RDKIT_WHEEL_INFO 1 RDKit_VERSION)
list(GET RDKIT_WHEEL_INFO 2 RDKIT_BOOST_VERSION)
list(GET RDKIT_WHEEL_INFO 3 RDKIT_PYTHON_VERSION)

# 2026.03.6 -> Release_2026_03_6 and 1_85 -> 1.85.0
string(REPLACE "." "_" RDKIT_TAG "Release_${RDKit_VERSION}")
string(REPLACE "_" "." RDKIT_BOOST_VERSION "${RDKIT_BOOST_VERSION}.0")

# Location of the shared libraries bundled by delocate (macOS)
# or auditwheel (GNU+Linux), and the matching RPATH relative to the
# Python module installed next to the rdkit package.
if(APPLE)
  set(RDKIT_WHEEL_LIBRARY_DIR ${RDKIT_WHEEL_DIR}/.dylibs)
  set(RDKit_WHEEL_RPATH "@loader_path/rdkit/.dylibs")
else()
  get_filename_component(RDKIT_WHEEL_LIBRARY_DIR
    ${RDKIT_WHEEL_DIR}/../rdkit.libs ABSOLUTE)
  set(RDKit_WHEEL_RPATH "$ORIGIN/rdkit.libs")
endif()

message(STATUS "Found rdkit wheel: ${RDKIT_WHEEL_DIR} "
  "(RDKit ${RDKit_VERSION}, Boost ${RDKIT_BOOST_VERSION}, "
  "Python ${RDKIT_PYTHON_VERSION})")

# Downloads are kept outside the per-wheel build directory,
# so that builds for different Python versions share them.
set(MOLPERT_DEPS_DIR ${PROJECT_SOURCE_DIR}/build/deps CACHE PATH
  "Directory where downloaded RDKit and Boost headers are kept")
include(RDKitWheelHashes)

# Download a file whose SHA256 is pinned in RDKitWheelHashes.cmake.
function(rdkit_wheel_download NAME URL OUTPUT)
  set(SHA256 ${MOLPERT_SHA256_${NAME}})
  if(NOT SHA256)
    message(FATAL_ERROR
      "No pinned SHA256 for ${NAME} (rdkit ${RDKit_VERSION}). "
      "Verify ${URL} and add its hash to cmake/RDKitWheelHashes.cmake.")
  endif()
  message(STATUS "Downloading ${URL}")
  file(DOWNLOAD ${URL} ${OUTPUT}
    EXPECTED_HASH SHA256=${SHA256}
    STATUS DOWNLOAD_STATUS)
  list(GET DOWNLOAD_STATUS 0 DOWNLOAD_CODE)
  if(NOT DOWNLOAD_CODE EQUAL 0)
    list(GET DOWNLOAD_STATUS 1 DOWNLOAD_MESSAGE)
    file(REMOVE ${OUTPUT})
    message(FATAL_ERROR "Failed to download ${URL}: ${DOWNLOAD_MESSAGE}")
  endif()
endfunction()

# Download and extract an archive unless it was extracted before.
function(rdkit_wheel_fetch NAME URL)
  set(EXTRACTED_DIR ${MOLPERT_DEPS_DIR}/${NAME})
  if(EXISTS ${EXTRACTED_DIR})
    return()
  endif()
  set(ARCHIVE ${MOLPERT_DEPS_DIR}/${NAME}.archive)
  rdkit_wheel_download(${NAME} ${URL} ${ARCHIVE})
  # Extract into a temporary directory first,
  # so that an interrupted extraction isn't mistaken for a complete one.
  file(REMOVE_RECURSE ${EXTRACTED_DIR}.tmp)
  file(ARCHIVE_EXTRACT INPUT ${ARCHIVE} DESTINATION ${EXTRACTED_DIR}.tmp
    PATTERNS ${ARGN})
  file(RENAME ${EXTRACTED_DIR}.tmp/${NAME} ${EXTRACTED_DIR})
  file(REMOVE_RECURSE ${EXTRACTED_DIR}.tmp)
  file(REMOVE ${ARCHIVE})
endfunction()

# RDKit headers. The CMakeLists.txt are needed to generate export.h.
if(MOLPERT_RDKIT_SOURCE_DIR)
  set(RDKIT_SOURCE_DIR ${MOLPERT_RDKIT_SOURCE_DIR})
else()
  set(RDKIT_SOURCE_DIR ${MOLPERT_DEPS_DIR}/rdkit-${RDKIT_TAG})
  rdkit_wheel_fetch(rdkit-${RDKIT_TAG}
    https://github.com/rdkit/rdkit/archive/refs/tags/${RDKIT_TAG}.tar.gz
    "*.h" "*.hpp" "*CMakeLists.txt" "*.cmake")
endif()

# Boost headers.
if(MOLPERT_BOOST_INCLUDE_DIR)
  set(Boost_INCLUDE_DIRS ${MOLPERT_BOOST_INCLUDE_DIR})
else()
  set(Boost_INCLUDE_DIRS ${MOLPERT_DEPS_DIR}/boost-${RDKIT_BOOST_VERSION})
  rdkit_wheel_fetch(boost-${RDKIT_BOOST_VERSION}
    https://github.com/boostorg/boost/releases/download/boost-${RDKIT_BOOST_VERSION}/boost-${RDKIT_BOOST_VERSION}-b2-nodocs.tar.xz
    "boost-${RDKIT_BOOST_VERSION}/boost/*")
endif()
set(BoostPython_INCLUDE_DIRS ${Boost_INCLUDE_DIRS})

# RingInfo.h includes RingDecomposerLib.h, which the RDKit downloads at
# build time. Fetch the same release the RDKit uses.
file(READ ${RDKIT_SOURCE_DIR}/External/RingFamilies/CMakeLists.txt
  URF_CMAKELISTS)
string(REGEX MATCH "set\\(RELEASE_NO \"([^\"]+)\"\\)" _ "${URF_CMAKELISTS}")
set(URF_NAME RingDecomposerLib-${CMAKE_MATCH_1})
set(URF_HEADER ${MOLPERT_DEPS_DIR}/${URF_NAME}/RingDecomposerLib.h)
if(NOT EXISTS ${URF_HEADER})
  rdkit_wheel_download(${URF_NAME}
    https://raw.githubusercontent.com/rareylab/RingDecomposerLib/v${CMAKE_MATCH_1}/src/RingDecomposerLib/RingDecomposerLib.h
    ${URF_HEADER})
endif()

# Headers the RDKit generates at build time.
set(RDKIT_GENERATED_DIR ${CMAKE_BINARY_DIR}/rdkit_generated)

# Recreate RDGeneral/export.h like RDKit's createExportTestHeaders().
file(GLOB_RECURSE RDKIT_CMAKELISTS ${RDKIT_SOURCE_DIR}/CMakeLists.txt)
set(RDKIT_EXPORT_LIBS "")
foreach(RDKIT_CMAKELIST ${RDKIT_CMAKELISTS})
  file(STRINGS ${RDKIT_CMAKELIST} RDKIT_LIBRARY_ITEMS
    REGEX "rdkit_library[ ]*\\([ ]*[^ ]+.*$")
  foreach(RDKIT_LIBRARY_ITEM ${RDKIT_LIBRARY_ITEMS})
    string(REGEX REPLACE "^[ ]*rdkit_library[ ]*\\([ ]*([^ ]+).*$" "\\1"
      RDKIT_EXPORT_LIB "${RDKIT_LIBRARY_ITEM}")
    list(APPEND RDKIT_EXPORT_LIBS "${RDKIT_EXPORT_LIB}")
  endforeach()
endforeach()
list(REMOVE_DUPLICATES RDKIT_EXPORT_LIBS)
list(SORT RDKIT_EXPORT_LIBS)
set(RDKIT_EXPORT_H "#pragma once\n#include <RDGeneral/RDExportMacros.h>\n")
foreach(RDKIT_EXPORT_LIB ${RDKIT_EXPORT_LIBS})
  string(TOUPPER "${RDKIT_EXPORT_LIB}" L)
  string(APPEND RDKIT_EXPORT_H "
#ifdef RDKIT_${L}_LOCAL_BUILD
#define RDKIT_${L}_EXPORT
#elif defined(RDKIT_${L}_BUILD)
#define RDKIT_${L}_EXPORT RDKIT_EXPORT_API
#else
#define RDKIT_${L}_EXPORT RDKIT_IMPORT_API
#endif
")
endforeach()
string(APPEND RDKIT_EXPORT_H "
#if defined(RDKIT_DYN_LINK) && defined(WIN32) && defined(BOOST_HAS_DECLSPEC)
#define RDKIT_QUERY_EXPORT
#else
#define RDKIT_QUERY_EXPORT RDKIT_GRAPHMOL_EXPORT
#endif
")
file(CONFIGURE OUTPUT ${RDKIT_GENERATED_DIR}/RDGeneral/export.h
  CONTENT "${RDKIT_EXPORT_H}" @ONLY)

# Recreate RDGeneral/versions.h.
string(REPLACE "." ";" RDKIT_VERSION_PARTS ${RDKit_VERSION})
list(GET RDKIT_VERSION_PARTS 0 RDKIT_YEAR)
list(GET RDKIT_VERSION_PARTS 1 RDKIT_MONTH)
list(GET RDKIT_VERSION_PARTS 2 RDKIT_REVISION)
math(EXPR RDKIT_MONTH "${RDKIT_MONTH}")
file(CONFIGURE OUTPUT ${RDKIT_GENERATED_DIR}/RDGeneral/versions.h
  CONTENT [=[
#include <RDGeneral/export.h>
#define RDKIT_VERSION_CHECK(year, month, rev) \
  ((year * 1000) + (month * 10) + (rev))
#define RDKIT_VERSION RDKIT_VERSION_CHECK(@RDKIT_YEAR@, @RDKIT_MONTH@, @RDKIT_REVISION@)
namespace RDKit {
RDKIT_RDGENERAL_EXPORT extern const char* rdkitVersion;
RDKIT_RDGENERAL_EXPORT extern const char* boostVersion;
RDKIT_RDGENERAL_EXPORT extern const char* rdkitBuild;
}  // namespace RDKit
]=] @ONLY)

# Recreate RDGeneral/RDConfig.h with the options used to build the wheel
# (see https://github.com/kuelumbus/rdkit-pypi/blob/main/setup.py).
# Some of these change the memory layout of RDKit classes.
set(RDK_USE_BOOST_SERIALIZATION ON)
set(RDK_USE_BOOST_IOSTREAMS ON)
set(RDK_BUILD_THREADSAFE_SSS ON)
set(RDK_TEST_MULTITHREADED ON)
set(RDK_USE_STRICT_ROTOR_DEFINITION ON)
set(RDK_BUILD_DESCRIPTORS3D ON)
set(RDK_BUILD_COORDGEN_SUPPORT ON)
set(RDK_BUILD_MAEPARSER_SUPPORT ON)
set(RDK_BUILD_AVALON_SUPPORT ON)
set(RDK_BUILD_INCHI_SUPPORT ON)
set(RDK_BUILD_SLN_SUPPORT ON)
set(RDK_BUILD_CAIRO_SUPPORT ON)
set(RDK_BUILD_FREETYPE_SUPPORT ON)
set(RDK_USE_URF ON)
set(RDK_BUILD_YAEHMOP_SUPPORT ON)
set(RDK_BUILD_XYZ2MOL_SUPPORT ON)
set(RDK_BUILD_CHEMDRAW_SUPPORT ON)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
  set(RDK_OPTIMIZE_POPCNT ON)
endif()
if(NOT APPLE)
  set(RDK_USE_BOOST_STACKTRACE ON)
endif()
configure_file(${RDKIT_SOURCE_DIR}/Code/RDGeneral/RDConfig.h.cmake
  ${RDKIT_GENERATED_DIR}/RDGeneral/RDConfig.h)

set(RDKit_INCLUDE_DIRS
  ${RDKIT_GENERATED_DIR}
  ${MOLPERT_DEPS_DIR}/${URF_NAME}
  ${RDKIT_SOURCE_DIR}/Code)
set(RDKit_LIBRARY_DIRS "")
set(Boost_LIBRARY_DIRS "")

# On macOS the wheel's libraries carry install names from the machine that
# built them. Link against copies whose install names resolve via RPATH.
set(RDKIT_WHEEL_LINK_DIR ${CMAKE_BINARY_DIR}/rdkit_wheel_link)
file(MAKE_DIRECTORY ${RDKIT_WHEEL_LINK_DIR})

# Find a library bundled with the wheel and return a path to link against.
function(rdkit_wheel_library OUTPUT_PATH NAME)
  if(APPLE)
    file(GLOB CANDIDATES ${RDKIT_WHEEL_LIBRARY_DIR}/lib${NAME}.dylib
      ${RDKIT_WHEEL_LIBRARY_DIR}/lib${NAME}.[0-9]*.dylib)
  else()
    # auditwheel appends a hash to the library names.
    file(GLOB CANDIDATES ${RDKIT_WHEEL_LIBRARY_DIR}/lib${NAME}-*.so*)
  endif()
  list(LENGTH CANDIDATES NUM_CANDIDATES)
  if(NOT NUM_CANDIDATES EQUAL 1)
    message(FATAL_ERROR "Expected one lib${NAME} in ${RDKIT_WHEEL_LIBRARY_DIR}, "
      "found: ${CANDIDATES}")
  endif()
  if(APPLE)
    get_filename_component(FILE_NAME ${CANDIDATES} NAME)
    set(LINK_PATH ${RDKIT_WHEEL_LINK_DIR}/${FILE_NAME})
    file(COPY_FILE ${CANDIDATES} ${LINK_PATH} ONLY_IF_DIFFERENT)
    execute_process(
      COMMAND install_name_tool -id @rpath/${FILE_NAME} ${LINK_PATH}
      ERROR_QUIET
      COMMAND_ERROR_IS_FATAL ANY)
    set(${OUTPUT_PATH} ${LINK_PATH} PARENT_SCOPE)
  else()
    set(${OUTPUT_PATH} ${CANDIDATES} PARENT_SCOPE)
  endif()
endfunction()

rdkit_wheel_library(BoostPython_LIBRARY boost_python${RDKIT_PYTHON_VERSION})

set(RDKIT_WHEEL_COMPONENTS
  RDGeneral
  RDGeometryLib
  DataStructs
  RingDecomposerLib
  GraphMol
  SubstructMatch
  Fingerprints
  SmilesParse)
foreach(COMPONENT ${RDKIT_WHEEL_COMPONENTS})
  rdkit_wheel_library(COMPONENT_LIBRARY RDKit${COMPONENT})
  add_library(RDKit${COMPONENT} SHARED IMPORTED)
  set_target_properties(RDKit${COMPONENT} PROPERTIES
    IMPORTED_LOCATION ${COMPONENT_LIBRARY}
    INTERFACE_COMPILE_DEFINITIONS RDKIT_DYN_LINK)
endforeach()

# Headers of the libraries Molpert uses directly reference symbols
# from these libraries.
set_target_properties(RDKitGraphMol PROPERTIES
  INTERFACE_LINK_LIBRARIES
    "RDKitRDGeneral;RDKitRDGeometryLib;RDKitDataStructs;RDKitRingDecomposerLib;RDKitSubstructMatch")

if(NOT APPLE)
  # Let the linker resolve the dependencies between the wheel's libraries.
  add_link_options(-Wl,-rpath-link,${RDKIT_WHEEL_LIBRARY_DIR})

  # Some rdkit wheels (e.g. 2024.9.6) are built with the old libstdc++ string
  # ABI, others (e.g. 2026.3.6) with the new one. Use the ABI of the wheel:
  # with the new ABI, RDKit functions taking or returning strings mention
  # std::__cxx11 in their mangled names.
  get_target_property(GRAPHMOL_LIBRARY RDKitGraphMol IMPORTED_LOCATION)
  execute_process(
    COMMAND ${CMAKE_NM} -D --defined-only ${GRAPHMOL_LIBRARY}
    OUTPUT_VARIABLE GRAPHMOL_SYMBOLS
    COMMAND_ERROR_IS_FATAL ANY)
  if(GRAPHMOL_SYMBOLS MATCHES "_ZN5RDKit[A-Za-z0-9_]*cxx11")
    set(RDKIT_CXX11_ABI 1)
  else()
    set(RDKIT_CXX11_ABI 0)
  endif()
  message(STATUS "rdkit wheel uses _GLIBCXX_USE_CXX11_ABI=${RDKIT_CXX11_ABI}")
  set_property(TARGET RDKitRDGeneral APPEND PROPERTY
    INTERFACE_COMPILE_DEFINITIONS _GLIBCXX_USE_CXX11_ABI=${RDKIT_CXX11_ABI})
endif()
