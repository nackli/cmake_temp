# ==============================================================================
# BuildSubmodule v1  --  基于本地 git submodule 源码的分层构建模块
#
# 与 BuildAndRepository 的区别:
#   BuildAndRepository  -> 从远程 git/URL 下载源码后编译
#   BuildSubmodule      -> 使用本地 3rdparty/<name>/ 下的 submodule 源码编译
#
# 入口函数:
#   BuildSubmodule    (关键词风格 API，兼容 BuildRepo 的参数设计)
#
# 使用前提:
#   先通过 git submodule add/update 将源码拉取到 3rdparty/<name>/
#
# 作者: nackli <nackli@163.com>
# ==============================================================================

include(ExternalProject)

# 记录本文件所在目录 (模板文件在同目录下)
set(_BuildSubmodule_DIR "${CMAKE_CURRENT_LIST_DIR}")

# ─── 工具宏 ───────────────────────────────────────────────────────────────────

macro(strequal_ignore_case str1 str2 result)
    string(TOLOWER "${str1}" _tmp1)
    string(TOLOWER "${str2}" _tmp2)
    if(_tmp1 STREQUAL _tmp2)
        set(${result} TRUE)
    else()
        set(${result} FALSE)
    endif()
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 对外统一入口: BuildSubmodule
# ══════════════════════════════════════════════════════════════════════════════
#
# 参数说明:
#   TARGET            target 名称 (必填，位置参数)
#   SOURCE_SUBDIR     源码子目录 (当 CMakeLists.txt 不在根目录时指定，如 "source")
#   LIB_TYPE          库类型: SHARED (默认) | STATIC
#   BUILD_SYSTEM      构建系统: CMAKE (默认) | AUTOTOOLS | CUSTOM
#
#   ── 构建宏 ──
#   BUILD_DEFINES     传给构建过程的 -D 宏 (e.g. PAHO_WITH_MQTT_C=1)
#   CMAKE_OPTS        cmake -D 变量列表 (e.g. BUILD_SHARED=ON ENABLE_SSL=OFF)
#
#   ── 消费宏 ──
#   DEFINES           传递给链接方的 INTERFACE compile_definitions
#                      (e.g. USE_PAHO_MQTT)
#
#   ── 依赖 ──
#   DEPENDS           依赖的其他 BuildSubmodule target 列表
#                     自动: add_dependencies + CMAKE_PREFIX_PATH
#
#   ── AUTOTOOLS 专用 ──
#   AUTORECONF        执行 autoreconf 命令 (e.g. "autoreconf -fi")
#   CONFIGURE_OPTS    额外的 ./configure 参数
#
#   ── CUSTOM 专用 ──
#   CONFIGURE_CMD     自定义 configure 命令
#   BUILD_CMD         自定义 build 命令 (默认 make -j${NPROC})
#   INSTALL_CMD       自定义 install 命令 (默认 make install)
#
# ── 使用示例 ──────────────────────────────────────────────────────────────────
#
#  # 先确保 submodule 已拉取:
#  #   git submodule add -b master git@github.com:example/foo.git 3rdparty/foo
#  #   git submodule update --init --recursive
#
#  # [1] cmake 构建 (默认)
#  BuildSubmodule(numactl
#      LIB_TYPE  STATIC
#  )
#
#  # [2] autotools 构建
#  BuildSubmodule(alsa-lib
#      BUILD_SYSTEM  AUTOTOOLS
#      AUTORECONF    "autoreconf -fi"
#      CONFIGURE_OPTS --disable-python
#  )
#
#  # [3] cmake 构建 + 依赖
#  BuildSubmodule(paho-mqttpp3
#      CMAKE_OPTS PAHO_WITH_MQTT_C=ON PAHO_BUILD_SHARED=ON
#      DEFINES    USE_PAHO_MQTT
#  )
#
#  # [4] 指定源码子目录 (当 CMakeLists.txt 在子目录内)
#  BuildSubmodule(x265
#      SOURCE_SUBDIR source
#      LIB_TYPE      STATIC
#  )
#
#  # [5] 自定义构建命令
#  BuildSubmodule(x264
#      BUILD_SYSTEM CUSTOM
#      CONFIGURE_CMD ./configure --enable-static --enable-pic
#      BUILD_CMD     make -j4
#      INSTALL_CMD   make install
#  )
# ══════════════════════════════════════════════════════════════════════════════

function(BuildSubmodule TARGET)
    # ─── cmake_parse_arguments 解析关键词参数 ───
    set(options     )
    set(oneValue    SOURCE_SUBDIR LIB_TYPE BUILD_SYSTEM AUTORECONF
                    CONFIGURE_CMD BUILD_CMD INSTALL_CMD)
    set(multiValue  DEPENDS BUILD_DEFINES DEFINES CMAKE_OPTS CONFIGURE_OPTS)

    cmake_parse_arguments(ARG "${options}" "${oneValue}" "${multiValue}" ${ARGN})

    # ─── 默认值 ───
    if(NOT ARG_LIB_TYPE)
        set(ARG_LIB_TYPE "SHARED")
    endif()
    if(NOT ARG_BUILD_SYSTEM)
        set(ARG_BUILD_SYSTEM "CMAKE")
    endif()

    string(TOUPPER "${ARG_LIB_TYPE}" _lib_type_upper)
    string(TOUPPER "${ARG_BUILD_SYSTEM}" _build_sys_upper)

    strequal_ignore_case("${ARG_LIB_TYPE}" "STATIC" _is_static)

    # ─── 目录配置 ───
    set(SUBMODULE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty")
    set(BINARY_DIR  ${CMAKE_CURRENT_BINARY_DIR})
    set(INSTALL_DIR "${BINARY_DIR}/3rdparty/${TARGET}_install")
    set(BUILD_DIR   "${BINARY_DIR}/3rdparty/${TARGET}-build")

    # ─── 源码目录: 3rdparty/<TARGET>/[SOURCE_SUBDIR] ───
    if(ARG_SOURCE_SUBDIR)
        set(SOURCE_DIR "${SUBMODULE_ROOT}/${TARGET}/${ARG_SOURCE_SUBDIR}")
    else()
        set(SOURCE_DIR "${SUBMODULE_ROOT}/${TARGET}")
    endif()

    # 校验源码目录是否存在
    if(NOT EXISTS "${SOURCE_DIR}")
        message(FATAL_ERROR
            "BuildSubmodule(${TARGET}): source dir '${SOURCE_DIR}' not found.\n"
            "  Hint: run 'git submodule update --init --recursive' first.\n"
            "  Hint: or 'git submodule add <repo> 3rdparty/${TARGET}' to add the submodule."
        )
    endif()

    # ─── byproduct 路径 ───
    if(WIN32)
        set(BYPRODUCT "lib/${TARGET}.lib")
    elseif(_is_static)
        set(BYPRODUCT "lib/lib${TARGET}.a")
    else()
        set(BYPRODUCT "lib/lib${TARGET}.so")
    endif()

    # ─── 处理 DEPENDS (自动: 依赖排序 + CMAKE_PREFIX_PATH) ───
    set(_EXTRA_CMAKE_ARGS "")
    set(_DEPEND_TARGETS "")
    foreach(_dep ${ARG_DEPENDS})
        list(APPEND _DEPEND_TARGETS ${_dep}-external)
        list(APPEND _EXTRA_CMAKE_ARGS
            "-DCMAKE_PREFIX_PATH=${BINARY_DIR}/3rdparty/${_dep}_install")
        message(STATUS "  ${TARGET} depends on ${_dep}")
    endforeach()

    # ─── 处理 BUILD_DEFINES (构建时 -D 宏) ───
    set(_EFFECTIVE_C_FLAGS   "${PASSTHROUGH_CMAKE_C_FLAGS}")
    set(_EFFECTIVE_CXX_FLAGS "${PASSTHROUGH_CMAKE_CXX_FLAGS}")
    if(ARG_BUILD_DEFINES)
        foreach(_def ${ARG_BUILD_DEFINES})
            set(_EFFECTIVE_C_FLAGS   "${_EFFECTIVE_C_FLAGS} -D${_def}")
            set(_EFFECTIVE_CXX_FLAGS "${_EFFECTIVE_CXX_FLAGS} -D${_def}")
        endforeach()
        message(STATUS "${TARGET} BUILD_DEFINES: ${ARG_BUILD_DEFINES}")
    endif()

    # ─── 处理 CMAKE_OPTS (cmake -D 变量) ───
    set(_EFFECTIVE_CMAKE_ARGS ${PASSTHROUGH_CMAKE_ARGS}
        "-DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}"
        ${_EXTRA_CMAKE_ARGS}
    )
    if(ARG_BUILD_DEFINES)
        list(APPEND _EFFECTIVE_CMAKE_ARGS
            "-DCMAKE_C_FLAGS=${_EFFECTIVE_C_FLAGS}"
            "-DCMAKE_CXX_FLAGS=${_EFFECTIVE_CXX_FLAGS}"
        )
    endif()
    if(ARG_CMAKE_OPTS)
        foreach(_opt ${ARG_CMAKE_OPTS})
            list(APPEND _EFFECTIVE_CMAKE_ARGS "-D${_opt}")
        endforeach()
        message(STATUS "${TARGET} CMAKE_OPTS: ${ARG_CMAKE_OPTS}")
    endif()

    # ─── 根据 BUILD_SYSTEM 路由到具体构建器 ───
    strequal_ignore_case("${ARG_BUILD_SYSTEM}" "CMAKE" _is_cmake)
    strequal_ignore_case("${ARG_BUILD_SYSTEM}" "AUTOTOOLS" _is_autotools)
    strequal_ignore_case("${ARG_BUILD_SYSTEM}" "CUSTOM" _is_custom)

    if(_is_cmake)
        _build_submodule_cmake(${TARGET})
    elseif(_is_autotools)
        _build_submodule_autotools(${TARGET})
    elseif(_is_custom)
        _build_submodule_custom(${TARGET})
    else()
        message(FATAL_ERROR "BuildSubmodule(${TARGET}): unknown BUILD_SYSTEM '${ARG_BUILD_SYSTEM}'")
    endif()

    # ─── 记录外部项目名称 ───
    set(${TARGET}_EXTERNAL  ${TARGET}-external  PARENT_SCOPE)
    set(${TARGET}_FOUND     "YES"               PARENT_SCOPE)
    set(${TARGET}_INCLUDE_DIR "${INSTALL_DIR}/include" PARENT_SCOPE)
    set(${TARGET}_LIBRARY     "${INSTALL_DIR}/${BYPRODUCT}" PARENT_SCOPE)

    # ─── 事后赋值回写 ───
    set(${TARGET}_FOUND     "YES"                CACHE STRING "" FORCE)
    set(${TARGET}_INCLUDE_DIR "${INSTALL_DIR}/include" CACHE STRING "" FORCE)
    set(${TARGET}_LIBRARY     "${INSTALL_DIR}/${BYPRODUCT}" CACHE STRING "" FORCE)
    set(${TARGET}_LIBRARIES   ${${TARGET}_LIBRARY}          CACHE STRING "" FORCE)

    # ─── 确保 include 目录存在 ───
    file(MAKE_DIRECTORY ${${TARGET}_INCLUDE_DIR})

    # ─── 创建 CMake 目标 ───
    _create_submodule_imported_target(${TARGET})

    # ─── 处理 DEPENDS 排序 ───
    if(_DEPEND_TARGETS)
        add_dependencies(${TARGET}-external ${_DEPEND_TARGETS})
    endif()

    # ─── 应用 DEFINES (INTERFACE compile_definitions) ───
    if(ARG_DEFINES)
        target_compile_definitions(${TARGET} INTERFACE ${ARG_DEFINES})
        message(STATUS "${TARGET} DEFINES: ${ARG_DEFINES}")
    endif()

    # ─── 生成 find_package Config 文件 ───
    _gen_submodule_find_package_config(${TARGET})

    message(STATUS "BuildSubmodule: ${TARGET} [${ARG_BUILD_SYSTEM}/${ARG_LIB_TYPE}] from ${SOURCE_DIR}")
endfunction()


# ══════════════════════════════════════════════════════════════════════════════
# 内部构建器: _build_submodule_cmake
#   处理 cmake 构建流程 (本地 submodule 源码)
# ══════════════════════════════════════════════════════════════════════════════
macro(_build_submodule_cmake TARGET)
    message(STATUS "  -> cmake build (from submodule): ${TARGET}")
    _submodule_nproc()

    ExternalProject_Add(
        ${TARGET}-external
        SOURCE_DIR         ${SOURCE_DIR}
        BINARY_DIR         ${BUILD_DIR}
        DOWNLOAD_COMMAND   ""           # 不从远程下载
        UPDATE_COMMAND     ""           # 不执行 git pull
        CMAKE_ARGS         ${_EFFECTIVE_CMAKE_ARGS}
        CMAKE_CACHE_ARGS   ${PASSTHROUGH_CMAKE_CACHE_ARGS}
        BUILD_COMMAND      cmake --build . --target install -- -j${_nproc_result}
        INSTALL_COMMAND    ""
        BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
        INSTALL_DIR        ${INSTALL_DIR}
        EXCLUDE_FROM_ALL   TRUE
    )
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部构建器: _build_submodule_autotools
#   处理 autotools (configure / autoreconf) 构建流程 (本地 submodule 源码)
# ══════════════════════════════════════════════════════════════════════════════
macro(_build_submodule_autotools TARGET)
    message(STATUS "  -> autotools build (from submodule): ${TARGET}")
    _submodule_nproc()

    # -- 修复 CFLAGS/CXXFLAGS 多余空格 --
    string(STRIP "${_EFFECTIVE_C_FLAGS}" _EFFECTIVE_C_FLAGS)
    string(STRIP "${_EFFECTIVE_CXX_FLAGS}" _EFFECTIVE_CXX_FLAGS)

    # -- 拼接 configure 公共参数 --
    set(_configure_args
        "CC=${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER}"
        "--prefix=${INSTALL_DIR}"
        ${ARG_CONFIGURE_OPTS}
    )

   # -- 交叉编译时自动添加 --host --
    if(CMAKE_CROSSCOMPILING OR DEFINED CMAKE_TOOLCHAIN_FILE)
        # 从编译器名称中提取 host triple (e.g. arm-linux-gnueabihf-gcc -> arm-linux-gnueabihf)
        get_filename_component(_compiler_name "${CMAKE_C_COMPILER}" NAME)
        if(_compiler_name MATCHES "^(.*)-gcc$")
            set(_host_triple "${CMAKE_MATCH_1}")
        elseif(_compiler_name MATCHES "^(.*)-clang$")
            set(_host_triple "${CMAKE_MATCH_1}")
        elseif(_compiler_name MATCHES "^(.*)-cc$")
            set(_host_triple "${CMAKE_MATCH_1}")
        endif()
        if(_host_triple)
            list(APPEND _configure_args "--host=${_host_triple}")
            message(STATUS "  -> cross-compiling: adding --host=${_host_triple}")
        else()
            message(WARNING "  -> cross-compiling detected but cannot extract host triple from compiler '${_compiler_name}'")
        endif()
    endif()


    # -- autoreconf 前置 --
    if(ARG_AUTORECONF)
        string(JOIN " " _configure_args_str ${_configure_args})
        set(_full_configure_cmd
            bash -c "${ARG_AUTORECONF} && ./configure ${_configure_args_str} CFLAGS='${_EFFECTIVE_C_FLAGS}' CXXFLAGS='${_EFFECTIVE_CXX_FLAGS}'"
        )
    else()
        set(_full_configure_cmd
            ./configure
            ${_configure_args}
            "CFLAGS=${_EFFECTIVE_C_FLAGS}"
            "CXXFLAGS=${_EFFECTIVE_CXX_FLAGS}"
        )
    endif()

    ExternalProject_Add(
        ${TARGET}-external
        SOURCE_DIR         ${SOURCE_DIR}
        BINARY_DIR         ${SOURCE_DIR}           # in-source build
        DOWNLOAD_COMMAND   ""                      # 不从远程下载
        UPDATE_COMMAND     ""                      # 不执行 git pull
        CONFIGURE_COMMAND  ${_full_configure_cmd}
        BUILD_COMMAND      make -j${_nproc_result}
        INSTALL_COMMAND    make install
        CMAKE_COMMAND      ""
        BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
        INSTALL_DIR        ${INSTALL_DIR}
        EXCLUDE_FROM_ALL   TRUE
    )
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部构建器: _build_submodule_custom
#   处理自定义构建流程 (用户提供 CONFIGURE/BUILD/INSTALL 命令)
# ══════════════════════════════════════════════════════════════════════════════
macro(_build_submodule_custom TARGET)
    message(STATUS "  -> custom build (from submodule): ${TARGET}")

    _submodule_nproc()
    if(NOT ARG_CONFIGURE_CMD)
        set(ARG_CONFIGURE_CMD "")
    endif()
    if(NOT ARG_BUILD_CMD)
        set(ARG_BUILD_CMD "make -j${_nproc_result}")
    endif()
    if(NOT ARG_INSTALL_CMD)
        set(ARG_INSTALL_CMD "make install")
    endif()

    ExternalProject_Add(
        ${TARGET}-external
        SOURCE_DIR         ${SOURCE_DIR}
        BINARY_DIR         ${SOURCE_DIR}           # in-source build
        DOWNLOAD_COMMAND   ""                      # 不从远程下载
        UPDATE_COMMAND     ""                      # 不执行 git pull
        CONFIGURE_COMMAND  ${ARG_CONFIGURE_CMD}
        BUILD_COMMAND      ${ARG_BUILD_CMD}
        INSTALL_COMMAND    ${ARG_INSTALL_CMD}
        CMAKE_COMMAND      ""
        BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
        INSTALL_DIR        ${INSTALL_DIR}
        EXCLUDE_FROM_ALL   TRUE
    )
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部辅助: _submodule_nproc
#   返回并行编译线程数 (环境变量 NPROC 优先，默认 4)
# ══════════════════════════════════════════════════════════════════════════════
function(_submodule_nproc)
    if(DEFINED ENV{NPROC})
        set(_n "$ENV{NPROC}")
    elseif(DEFINED ENV{NUMBER_OF_PROCESSORS})
        set(_n "$ENV{NUMBER_OF_PROCESSORS}")
    else()
        include(ProcessorCount)
        ProcessorCount(_n)
        if(NOT _n)
            set(_n 4)
        endif()
    endif()
    set(_nproc_result "${_n}" PARENT_SCOPE)
endfunction()


# ══════════════════════════════════════════════════════════════════════════════
# 内部宏: _create_submodule_imported_target
#   统一创建 STATIC/SHARED IMPORTED 目标
# ══════════════════════════════════════════════════════════════════════════════
macro(_create_submodule_imported_target TARGET)
    if(_is_static)
        add_library(${TARGET} STATIC IMPORTED GLOBAL)
        set_target_properties(${TARGET} PROPERTIES
            IMPORTED_LOCATION "${INSTALL_DIR}/${BYPRODUCT}"
            INTERFACE_LINK_LIBRARIES "${INSTALL_DIR}/${BYPRODUCT}"
        )
        add_dependencies(${TARGET} ${TARGET}-external)
        target_include_directories(${TARGET} INTERFACE "${INSTALL_DIR}/include")
    else()
        add_library(${TARGET} SHARED IMPORTED GLOBAL)
        set_target_properties(${TARGET} PROPERTIES
            IMPORTED_LOCATION "${INSTALL_DIR}/${BYPRODUCT}"
            INTERFACE_LINK_LIBRARIES "${INSTALL_DIR}/${BYPRODUCT}"
            IMPORTED_NO_SONAME TRUE
        )
        target_include_directories(${TARGET} INTERFACE "${INSTALL_DIR}/include")
        add_custom_target(${TARGET}_deps DEPENDS ${TARGET}-external)
        add_dependencies(${TARGET} ${TARGET}_deps)
    endif()
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部宏: _gen_submodule_find_package_config
#   生成 <TARGET>Config.cmake 和 <TARGET>ConfigVersion.cmake
# ══════════════════════════════════════════════════════════════════════════════
macro(_gen_submodule_find_package_config TARGET)
    set(TARGET_NAME "${TARGET}")
    set(CONFIG_INSTALL_DIR "${INSTALL_DIR}/lib/cmake/${TARGET}")
    file(MAKE_DIRECTORY ${CONFIG_INSTALL_DIR})

    if(_is_static)
        set(TEMPLATE_FILE "${_BuildSubmodule_DIR}/FindPackageConfig-Static.cmake.in")
    else()
        set(TEMPLATE_FILE "${_BuildSubmodule_DIR}/FindPackageConfig-Shared.cmake.in")
    endif()
    configure_file("${TEMPLATE_FILE}" "${CONFIG_INSTALL_DIR}/${TARGET}Config.cmake" @ONLY)

    set(VERSION_TEMPLATE "${_BuildSubmodule_DIR}/FindPackageConfig-Version.cmake.in")
    configure_file("${VERSION_TEMPLATE}" "${CONFIG_INSTALL_DIR}/${TARGET}ConfigVersion.cmake" @ONLY)

    message(STATUS "  -> find_package config: ${CONFIG_INSTALL_DIR}")
endmacro()
