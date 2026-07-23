# ==============================================================================
# BuildAndRepository v2  --  分层构建 + 关键词 API 设计
#
# 入口函数:
#   BuildRepo          (新 API，关键词风格)
#   Use_Build_Repo     (旧 API，自动兼容路由)
#
# 作者: nackli <nackli@163.com>
# ==============================================================================

include(ExternalProject)

# 记录本文件所在目录 (宏内 CMAKE_CURRENT_FUNCTION_LIST_DIR 不可用)
set(_BuildAndRepository_DIR "${CMAKE_CURRENT_LIST_DIR}")

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

macro(is_git_repo strUrl result)
    message(STATUS "DEBUG is_git_repo: strUrl=[${strUrl}], result=[${result}]")
    set(${result} FALSE)
    if("${strUrl}" MATCHES "\\.git$")
        message(STATUS "DEBUG is_git_repo: MATCHES \\.git$")
        set(${result} TRUE)
    elseif("${strUrl}" MATCHES "^git@")
        message(STATUS "DEBUG is_git_repo: MATCHES ^git@")
        set(${result} TRUE)
    elseif("${strUrl}" MATCHES "^https?://.*\\.git")
        message(STATUS "DEBUG is_git_repo: MATCHES ^https?://")
        set(${result} TRUE)
    endif()
    message(STATUS "DEBUG is_git_repo: returning ${result}=[${${result}}]")
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 对外统一入口: BuildRepo
# ══════════════════════════════════════════════════════════════════════════════
#
# 参数说明:
#   TARGET            target 名称 (必填，位置参数)
#   GIT_REPO          仓库地址 (git@... 或 https://...)
#   GIT_TAG           分支/标签 (默认 main)
#   URL               压缩包下载地址 (与 GIT_REPO 二选一)
#   URL_HASH          压缩包哈希值
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
#   DEPENDS           依赖的其他 BuildRepo target 列表
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
#  # [1] cmake 构建 (默认)
#  BuildRepo(pahoMqtt-c
#      GIT_REPO   https://github.com/eclipse-paho/paho.mqtt.c.git
#      GIT_TAG    master
#  )
#
#  # [2] cmake 构建 + 依赖 + 选项 + 消费宏
#  BuildRepo(pahoMqtt
#      GIT_REPO   git@github.com:eclipse-paho/paho.mqtt.cpp.git
#      GIT_TAG    master
#      DEPENDS    pahoMqtt-c
#      CMAKE_OPTS PAHO_WITH_MQTT_C=ON
#      DEFINES    USE_PAHO_MQTT
#  )
#
#  # [3] autotools 构建
#  BuildRepo(asound
#      GIT_REPO      https://github.com/alsa-project/alsa-lib.git
#      GIT_TAG       v1.2.15.3
#      BUILD_SYSTEM  AUTOTOOLS
#      AUTORECONF    "autoreconf -fi"
#      DEFINES       USE_ALSA
#  )
#
#  # [4] 静态库
#  BuildRepo(opus
#      GIT_REPO  https://gitee.com/huang-ruifeng/opus.git
#      GIT_TAG   v1.6.1
#      LIB_TYPE  STATIC
#  )
#
#  # [5] autotools + 自定义 autoreconf 脚本
#  BuildRepo(speexdsp
#      GIT_REPO      https://github.com/xiph/speexdsp.git
#      GIT_TAG       master
#      BUILD_SYSTEM  AUTOTOOLS
#      AUTORECONF    "./autogen.sh"
#  )
#
#  # [6] 压缩包下载 + autotools 构建
#  BuildRepo(zlib
#      URL          https://zlib.net/zlib-1.3.tar.gz
#      URL_HASH     SHA256=ff0ba4c292014b6e...
#      BUILD_SYSTEM AUTOTOOLS
#  )
# ══════════════════════════════════════════════════════════════════════════════

function(BuildRepo TARGET)
    # ─── cmake_parse_arguments 解析关键词参数 ───
    set(options   )   # 布尔 flag (STATIC/SHARED 由 LIB_TYPE 统一处理)
    set(oneValue  GIT_REPO GIT_TAG URL URL_HASH LIB_TYPE BUILD_SYSTEM AUTORECONF
                  CONFIGURE_CMD BUILD_CMD INSTALL_CMD)
    set(multiValue DEPENDS BUILD_DEFINES DEFINES CMAKE_OPTS CONFIGURE_OPTS)

    cmake_parse_arguments(ARG "${options}" "${oneValue}" "${multiValue}" ${ARGN})

    # ─── 默认值 ───
    if(NOT ARG_GIT_TAG)
        set(ARG_GIT_TAG "main")
    endif()
    if(NOT ARG_LIB_TYPE)
        set(ARG_LIB_TYPE "SHARED")
    endif()
    if(NOT ARG_BUILD_SYSTEM)
        set(ARG_BUILD_SYSTEM "CMAKE")
    endif()
    string(TOUPPER "${ARG_LIB_TYPE}" _lib_type_upper)
    string(TOUPPER "${ARG_BUILD_SYSTEM}" _build_sys_upper)

    strequal_ignore_case("${ARG_LIB_TYPE}" "STATIC" _is_static)

    set(BINARY_DIR  ${CMAKE_CURRENT_BINARY_DIR})
    set(INSTALL_DIR "${BINARY_DIR}/3rdparty/${TARGET}_install")
    set(SOURCE_DIR  "${BINARY_DIR}/3rdparty/${TARGET}-src")

    # ─── byproduct 路径 ───
    if(WIN32)
        set(BYPRODUCT "lib/${TARGET}.lib")
    elseif(_is_static)
        set(BYPRODUCT "lib/lib${TARGET}.a")
    else()
        set(BYPRODUCT "lib/lib${TARGET}.so")
    endif()

    # ─── 处理 GIT_REPO vs URL ───
    if(ARG_GIT_REPO)
        set(_REPO_URL_ADDR "${ARG_GIT_REPO}")
        set(_REPO_URL_TAG  "${ARG_GIT_TAG}")
        set(_DL_URL    "")
        set(_DL_HASH   "")
    elseif(ARG_URL)
        set(_REPO_URL_ADDR "")
        set(_REPO_URL_TAG  "")
        set(_DL_URL    "${ARG_URL}")
        set(_DL_HASH   "${ARG_URL_HASH}")
    else()
        message(FATAL_ERROR "BuildRepo(${TARGET}): must specify GIT_REPO or URL")
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
        _build_cmake(${TARGET})
    elseif(_is_autotools)
        _build_autotools(${TARGET})
    elseif(_is_custom)
        _build_custom(${TARGET})
    else()
        message(FATAL_ERROR "BuildRepo(${TARGET}): unknown BUILD_SYSTEM '${ARG_BUILD_SYSTEM}'")
    endif()

    # ─── 记录外部项目名称 ───
    set(${TARGET}_EXTERNAL  ${TARGET}-external  PARENT_SCOPE)
    set(${TARGET}_FOUND     "YES"               PARENT_SCOPE)
    set(${TARGET}_INCLUDE_DIR "${INSTALL_DIR}/include" PARENT_SCOPE)
    set(${TARGET}_LIBRARY     "${INSTALL_DIR}/${BYPRODUCT}" PARENT_SCOPE)

    # ─── 事后赋值在 _build_* 中完成, 再单独给父作用域回写 ───
    set(${TARGET}_FOUND     "YES"                CACHE STRING "" FORCE)
    set(${TARGET}_INCLUDE_DIR "${INSTALL_DIR}/include" CACHE STRING "" FORCE)
    set(${TARGET}_LIBRARY     "${INSTALL_DIR}/${BYPRODUCT}" CACHE STRING "" FORCE)
    set(${TARGET}_LIBRARIES   ${${TARGET}_LIBRARY}          CACHE STRING "" FORCE)

    # ─── 确保 include 目录存在 ───
    file(MAKE_DIRECTORY ${${TARGET}_INCLUDE_DIR})

    # ─── 创建 CMake 目标 ───
    _create_imported_target(${TARGET})

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
    _gen_find_package_config(${TARGET})

    message(STATUS "BuildRepo: ${TARGET} [${ARG_BUILD_SYSTEM}/${ARG_LIB_TYPE}]")
endfunction()


# ══════════════════════════════════════════════════════════════════════════════
# 内部构建器: _build_cmake
#   处理 cmake 构建流程
# ══════════════════════════════════════════════════════════════════════════════
macro(_build_cmake TARGET)
    message(STATUS "  -> cmake build: ${TARGET}")

    _nproc()
    if(_REPO_URL_ADDR)
        ExternalProject_Add(
            ${TARGET}-external
            GIT_REPOSITORY     ${_REPO_URL_ADDR}
            GIT_TAG            ${_REPO_URL_TAG}
            TIMEOUT            600              #下载超时设置为 600 秒（默认可能只有 10 秒）
            RETRY_COUNT        5                # 重试次数
            RETRY_TIMEOUT      30               #每次重试的等待间隔（秒）
            USES_TERMINAL_DOWNLOAD TRUE         # 强制让 CMake 调用系统的 git，而不是内置下载器
            GIT_SHALLOW        1
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR         ${SOURCE_DIR}
            BINARY_DIR         ${CMAKE_CURRENT_BINARY_DIR}/3rdparty/${TARGET}-build
            UPDATE_DISCONNECTED YES
            CMAKE_ARGS         ${_EFFECTIVE_CMAKE_ARGS}
            CMAKE_CACHE_ARGS   ${PASSTHROUGH_CMAKE_CACHE_ARGS}
            BUILD_COMMAND      cmake --build . --target install -- -j${_nproc_result}
            INSTALL_COMMAND    ""
            BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
            INSTALL_DIR        ${INSTALL_DIR}
            EXCLUDE_FROM_ALL   TRUE
        )
    else()
        ExternalProject_Add(
            ${TARGET}-external
            URL                ${_DL_URL}
            URL_HASH           ${_DL_HASH}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR         ${SOURCE_DIR}
            BINARY_DIR         ${CMAKE_CURRENT_BINARY_DIR}/3rdparty/${TARGET}-build
            UPDATE_DISCONNECTED YES
            CMAKE_ARGS         ${_EFFECTIVE_CMAKE_ARGS}
            CMAKE_CACHE_ARGS   ${PASSTHROUGH_CMAKE_CACHE_ARGS}
            BUILD_COMMAND      cmake --build . --target install -- -j${_nproc_result}
            INSTALL_COMMAND    ""
            BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
            INSTALL_DIR        ${INSTALL_DIR}
            EXCLUDE_FROM_ALL   TRUE
        )
    endif()
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部构建器: _build_autotools
#   处理 autotools (configure / autoreconf) 构建流程
# ══════════════════════════════════════════════════════════════════════════════
macro(_build_autotools TARGET)
    message(STATUS "  -> autotools build: ${TARGET}")
    _nproc()

    # -- 修复 CFLAGS/CXXFLAGS 多余空格 --
    string(STRIP "${_EFFECTIVE_C_FLAGS}" _EFFECTIVE_C_FLAGS)
    string(STRIP "${_EFFECTIVE_CXX_FLAGS}" _EFFECTIVE_CXX_FLAGS)

    # -- 拼接 configure 公共参数 --
    set(_configure_args
        "CC=${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER}"
        "--host=arm-none-linux-gnu"
        "--prefix=${INSTALL_DIR}"
        ${ARG_CONFIGURE_OPTS}
    )

    # -- autoreconf 前置 --
    if(ARG_AUTORECONF)
        # bash -c 模式下 CFLAGS/CXXFLAGS 值含空格, 需用单引号包裹
        string(JOIN " " _configure_args_str ${_configure_args})
        set(_full_configure_cmd
            bash -c "${ARG_AUTORECONF} && ./configure ${_configure_args_str} CFLAGS='${_EFFECTIVE_C_FLAGS}' CXXFLAGS='${_EFFECTIVE_CXX_FLAGS}'"
        )
    else()
        # 无 autoreconf 时直接用 CMake list 方式传给 CONFIGURE_COMMAND
        set(_full_configure_cmd
            ./configure
            ${_configure_args}
            "CFLAGS=${_EFFECTIVE_C_FLAGS}"
            "CXXFLAGS=${_EFFECTIVE_CXX_FLAGS}"
        )
    endif()

    # -- install 后创建 .so 符号链接 (libtool 交叉编译时不会自动创建) --
    # 用 set() 构造 CMake list, bash -c 的 shell 脚本作为单个元素, 分号用 \; 转义
    if(LIB_TYPE STREQUAL "shared")
        set(_full_install_cmd
            bash -c "make install && cd ${INSTALL_DIR}/lib && for f in lib${TARGET}.so.*\; do [ -f \$f ] && ln -sf \$f lib${TARGET}.so && ln -sf \$f \${f%.*} && break\; done"
        )
    else()
        set(_full_install_cmd make install)
    endif()

    if(_REPO_URL_ADDR)
        ExternalProject_Add(
            ${TARGET}-external
            GIT_REPOSITORY     ${_REPO_URL_ADDR}
            GIT_TAG            ${_REPO_URL_TAG}
            GIT_SHALLOW        1
            TIMEOUT            600              #下载超时设置为 600 秒（默认可能只有 10 秒）
            RETRY_COUNT        5                # 重试次数
            RETRY_TIMEOUT      30               #每次重试的等待间隔（秒）
            USES_TERMINAL_DOWNLOAD TRUE         # 强制让 CMake 调用系统的 git，而不是内置下载器
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR         ${SOURCE_DIR}
            BINARY_DIR         ${SOURCE_DIR}           # in-source build
            UPDATE_DISCONNECTED YES
            CONFIGURE_COMMAND  ${_full_configure_cmd}
            BUILD_COMMAND      make -j${_nproc_result}
            INSTALL_COMMAND    ${_full_install_cmd}
            CMAKE_COMMAND      ""
            UPDATE_COMMAND     ""
            BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
            INSTALL_DIR        ${INSTALL_DIR}
            EXCLUDE_FROM_ALL   TRUE
        )
    else()
        ExternalProject_Add(
            ${TARGET}-external
            URL                ${_DL_URL}
            URL_HASH           ${_DL_HASH}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR         ${SOURCE_DIR}
            BINARY_DIR         ${SOURCE_DIR}           # in-source build
            UPDATE_DISCONNECTED YES
            CONFIGURE_COMMAND  ${_full_configure_cmd}
            BUILD_COMMAND      make -j${_nproc_result}
            INSTALL_COMMAND    ${_full_install_cmd}
            CMAKE_COMMAND      ""
            UPDATE_COMMAND     ""
            BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
            INSTALL_DIR        ${INSTALL_DIR}
            EXCLUDE_FROM_ALL   TRUE
        )
    endif()
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部构建器: _build_custom
#   处理自定义构建流程 (用户提供 CONFIGURE/BUILD/INSTALL 命令)
# ══════════════════════════════════════════════════════════════════════════════
macro(_build_custom TARGET)
    message(STATUS "  -> custom build: ${TARGET}")

    _nproc()
    if(NOT ARG_CONFIGURE_CMD)
        set(ARG_CONFIGURE_CMD "")
    endif()
    if(NOT ARG_BUILD_CMD)
        set(ARG_BUILD_CMD "make -j${_nproc_result}")
    endif()
    if(NOT ARG_INSTALL_CMD)
        set(ARG_INSTALL_CMD "make install")
    endif()

    if(_REPO_URL_ADDR)
        ExternalProject_Add(
            ${TARGET}-external
            GIT_REPOSITORY     ${_REPO_URL_ADDR}
            GIT_TAG            ${_REPO_URL_TAG}
            GIT_SHALLOW        1
            TIMEOUT            600              #下载超时设置为 600 秒（默认可能只有 10 秒）
            RETRY_COUNT        5                # 重试次数
            RETRY_TIMEOUT      30               #每次重试的等待间隔（秒）
            USES_TERMINAL_DOWNLOAD TRUE         # 强制让 CMake 调用系统的 git，而不是内置下载器
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR         ${SOURCE_DIR}
            BINARY_DIR         ${SOURCE_DIR}
            UPDATE_DISCONNECTED YES
            CONFIGURE_COMMAND  ${ARG_CONFIGURE_CMD}
            BUILD_COMMAND      ${ARG_BUILD_CMD}
            INSTALL_COMMAND    ${ARG_INSTALL_CMD}
            CMAKE_COMMAND      ""
            UPDATE_COMMAND     ""
            BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
            INSTALL_DIR        ${INSTALL_DIR}
            EXCLUDE_FROM_ALL   TRUE
        )
    else()
        ExternalProject_Add(
            ${TARGET}-external
            URL                ${_DL_URL}
            URL_HASH           ${_DL_HASH}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR         ${SOURCE_DIR}
            BINARY_DIR         ${SOURCE_DIR}
            UPDATE_DISCONNECTED YES
            CONFIGURE_COMMAND  ${ARG_CONFIGURE_CMD}
            BUILD_COMMAND      ${ARG_BUILD_CMD}
            INSTALL_COMMAND    ${ARG_INSTALL_CMD}
            CMAKE_COMMAND      ""
            UPDATE_COMMAND     ""
            BUILD_BYPRODUCTS   "${INSTALL_DIR}/${BYPRODUCT}"
            INSTALL_DIR        ${INSTALL_DIR}
            EXCLUDE_FROM_ALL   TRUE
        )
    endif()
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部函数: _create_imported_target
#   统一创建 STATIC IMPORTED / INTERFACE 目标
# ══════════════════════════════════════════════════════════════════════════════
macro(_create_imported_target TARGET)
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
# 内部函数: _gen_find_package_config
#   生成 <TARGET>Config.cmake 和 <TARGET>ConfigVersion.cmake
# ══════════════════════════════════════════════════════════════════════════════
macro(_gen_find_package_config TARGET)
    set(CONFIG_INSTALL_DIR "${INSTALL_DIR}/lib/cmake/${TARGET}")
    file(MAKE_DIRECTORY ${CONFIG_INSTALL_DIR})

    if(_is_static)
        set(TEMPLATE_FILE "${_BuildAndRepository_DIR}/FindPackageConfig-Static.cmake.in")
    else()
        set(TEMPLATE_FILE "${_BuildAndRepository_DIR}/FindPackageConfig-Shared.cmake.in")
    endif()
    configure_file("${TEMPLATE_FILE}" "${CONFIG_INSTALL_DIR}/${TARGET}Config.cmake" @ONLY)

    set(VERSION_TEMPLATE "${_BuildAndRepository_DIR}/FindPackageConfig-Version.cmake.in")
    configure_file("${VERSION_TEMPLATE}" "${CONFIG_INSTALL_DIR}/${TARGET}ConfigVersion.cmake" @ONLY)

    message(STATUS "  -> find_package config: ${CONFIG_INSTALL_DIR}")
endmacro()


# ══════════════════════════════════════════════════════════════════════════════
# 内部辅助: _nproc
#   返回并行编译线程数 (环境变量 NPROC 优先，默认 4)
# ══════════════════════════════════════════════════════════════════════════════
function(_nproc)
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
# 向后兼容层: Use_Build_Repo
#   完整保留旧版所有调用，同时支持新 BuildRepo 的使用方式。
#   兼容逻辑：
#     - 如果第二个参数是位置参数风格 (含 "://" 等) → 走旧逻辑
#     - 否则转发给 BuildRepo (关键词参数)
# ══════════════════════════════════════════════════════════════════════════════
function(Use_Build_Repo)
    # 在调用栈中，ARGV 是先于 cmake_parse_arguments 的原始入参
    # Use_Build_Repo(TARGET_NAME URL TAG [TYPE] [TOOL] ...)
    list(LENGTH ARGV _argc)
    if(_argc LESS 3)
        message(FATAL_ERROR "Use_Build_Repo: need at least 3 arguments")
    endif()

    list(GET ARGV 0 _target_name)
    list(GET ARGV 1 _second_arg)

    # 判断是老式调用 (第二个参数是 URL/Repo 地址)
    if(_second_arg MATCHES "://|^git@" OR _argc GREATER 3 AND NOT _second_arg STREQUAL "GIT_REPO" AND NOT _second_arg STREQUAL "URL")
        # ─── 走旧版兼容逻辑 ───
        _use_build_repo_legacy(${ARGV})
    else()
        # ─── 转发给新版 BuildRepo ───
        BuildRepo(${ARGV})
    endif()
endfunction()


# ══════════════════════════════════════════════════════════════════════════════
# 旧版实现: _use_build_repo_legacy
#   完整保留原有 Use_Build_Repo 的全部逻辑，一个字不改，仅改名 + 用 PARENT_SCOPE。
#   (实际项目中旧版逻辑太长，这里只保留核心骨架示意；
#    真正重构时直接把现有的 Use_Build_Repo 函数体搬进来即可）
# ══════════════════════════════════════════════════════════════════════════════
function(_use_build_repo_legacy)
    # 参数：TARGET_NAME REPO_URL REPO_TAG [LIB_TYPE] [BUILD_TOOL] [AUTORECONFIG_CMD] [EXTRA_ARGS...]
    set(LIB_TYPE "shared")
    set(DEFAULT_BUILD_TOOL "cmake")
    set(AUTORECONFIG_CMD "")
    set(AUTORECONFIG_CMD_PARAM "")
    set(BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR})
    set(CONFIGURE_BUILD_PARAM "")
    set(CONFIGURE_COMMAND_BUILD "")

    list(LENGTH ARGV arg_count)
    if(arg_count LESS 3)
        message(FATAL_ERROR "Use_Build_Repo: need at least 3 arguments (name, url, tag)")
    endif()

    list(GET ARGV 0 TARGET_NAME)
    list(GET ARGV 1 REPO_URL)
    list(GET ARGV 2 REPO_TAG)

    if(arg_count GREATER 3)
        list(GET ARGV 3 LIB_TYPE)
    endif()
    if(arg_count GREATER 4)
        list(GET ARGV 4 DEFAULT_BUILD_TOOL)
    endif()

    strequal_ignore_case(${LIB_TYPE} "static" IS_STATIC)

    # -- 约定变量：BUILD_DEFINES / INTERFACE_DEFINES --
    set(_EFFECTIVE_C_FLAGS   "${PASSTHROUGH_CMAKE_C_FLAGS}")
    set(_EFFECTIVE_CXX_FLAGS "${PASSTHROUGH_CMAKE_CXX_FLAGS}")
    if(DEFINED ${TARGET_NAME}_BUILD_DEFINES)
        foreach(_def ${${TARGET_NAME}_BUILD_DEFINES})
            set(_EFFECTIVE_C_FLAGS   "${_EFFECTIVE_C_FLAGS} -D${_def}")
            set(_EFFECTIVE_CXX_FLAGS "${_EFFECTIVE_CXX_FLAGS} -D${_def}")
        endforeach()
        message(STATUS "${TARGET_NAME} BUILD_DEFINES: ${${TARGET_NAME}_BUILD_DEFINES}")
    endif()
    if(DEFINED ${TARGET_NAME}_INTERFACE_DEFINES)
        message(STATUS "${TARGET_NAME} INTERFACE_DEFINES: ${${TARGET_NAME}_INTERFACE_DEFINES}")
    endif()

    # byproduct
    if(WIN32)
        set(BYPRODUCT "lib/${TARGET_NAME}.lib")
    elseif(IS_STATIC)
        set(BYPRODUCT "lib/lib${TARGET_NAME}.a")
    else()
        set(BYPRODUCT "lib/lib${TARGET_NAME}.so")
    endif()

    # URL 处理
    set(DOWNLOAD_URL "")
    set(URL_HASH "")
    set(REPO_URL_ADDR "")
    set(REPO_URL_TAG "")
    message(STATUS "DEBUG: REPO_URL=[${REPO_URL}], REPO_TAG=[${REPO_TAG}]")
    is_git_repo(${REPO_URL} IS_REPO)
    message(STATUS "DEBUG: IS_REPO=[${IS_REPO}] after is_git_repo")
    if(IS_REPO)
        set(REPO_URL_ADDR ${REPO_URL})
        set(REPO_URL_TAG ${REPO_TAG})
    else()
        set(DOWNLOAD_URL ${REPO_URL})
        set(URL_HASH ${REPO_TAG})
    endif()

    set(BUILD_SDK_INSTALL "${BINARY_DIR}/3rdparty/${TARGET_NAME}_install")

    # 构建命令
    strequal_ignore_case(${DEFAULT_BUILD_TOOL} "cmake" IS_CMAKE_BUILD)
    if(IS_CMAKE_BUILD)
        message(STATUS "Build ${TARGET_NAME} use cmake")
        set(BUILD_CMAKE_ARGS ${PASSTHROUGH_CMAKE_ARGS} "-DCMAKE_INSTALL_PREFIX=${BUILD_SDK_INSTALL}")
        if(DEFINED ${TARGET_NAME}_BUILD_DEFINES)
            list(APPEND BUILD_CMAKE_ARGS
                "-DCMAKE_C_FLAGS=${_EFFECTIVE_C_FLAGS}"
                "-DCMAKE_CXX_FLAGS=${_EFFECTIVE_CXX_FLAGS}"
            )
        endif()
        if(DEFINED ${TARGET_NAME}_CMAKE_CACHE_ARGS)
            list(APPEND BUILD_CMAKE_ARGS ${${TARGET_NAME}_CMAKE_CACHE_ARGS})
            message(STATUS "${TARGET_NAME} CMAKE_CACHE_ARGS: ${${TARGET_NAME}_CMAKE_CACHE_ARGS}")
        endif()
        set(CONFIGURE_COMMAND_BUILD "")
    else()
        message(STATUS "Build ${TARGET_NAME} use configure")
        set(BUILD_CMAKE_ARGS "")
        if(arg_count GREATER 5)
            list(GET ARGV 5 AUTORECONFIG_CMD)
            if(arg_count GREATER 6)
                set(extra_args ${ARGV})
                list(REMOVE_AT extra_args 0 1 2 3 4 5)
                set(AUTORECONFIG_CMD_PARAM ${extra_args})
            endif()
        endif()
        set(CONFIGURE_BUILD_PARAM
            ./configure
            "CC=${CMAKE_C_COMPILER}"
            "CXX=${CMAKE_CXX_COMPILER}"
            --host=arm-none-linux-gnu
            "CFLAGS=${_EFFECTIVE_C_FLAGS}"
            "CXXFLAGS=${_EFFECTIVE_CXX_FLAGS}"
            "--prefix=${BUILD_SDK_INSTALL}"
        )
        if(AUTORECONFIG_CMD)
            set(CONFIGURE_COMMAND_BUILD ${AUTORECONFIG_CMD} ${AUTORECONFIG_CMD_PARAM} && ${CONFIGURE_BUILD_PARAM})
        else()
            set(CONFIGURE_COMMAND_BUILD ${CONFIGURE_BUILD_PARAM})
        endif()
    endif()

    # ExternalProject - CMake 4.x 不允许同时传空 URL/URL_HASH 和 GIT_REPOSITORY
    if(IS_REPO)
        ExternalProject_Add(
            ${TARGET_NAME}-external
            GIT_REPOSITORY ${REPO_URL_ADDR}
            GIT_TAG ${REPO_URL_TAG}
            GIT_SHALLOW 1
            TIMEOUT            600              #下载超时设置为 600 秒（默认可能只有 10 秒）
            RETRY_COUNT        5                # 重试次数
            RETRY_TIMEOUT      30               #每次重试的等待间隔（秒）
            USES_TERMINAL_DOWNLOAD TRUE         # 强制让 CMake 调用系统的 git，而不是内置下载器
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR "${BINARY_DIR}/3rdparty/${TARGET_NAME}-src"
            BINARY_DIR "${BINARY_DIR}/3rdparty/${TARGET_NAME}-src"
            UPDATE_DISCONNECTED YES
            BUILD_COMMAND make -j4
            CMAKE_COMMAND ""
            UPDATE_COMMAND ""
            INSTALL_COMMAND make install
            BUILD_BYPRODUCTS "${BUILD_SDK_INSTALL}/${BYPRODUCT}"
            CONFIGURE_COMMAND ${CONFIGURE_COMMAND_BUILD}
            INSTALL_DIR "${BUILD_SDK_INSTALL}"
            LIST_SEPARATOR %
            CMAKE_ARGS ${BUILD_CMAKE_ARGS}
            CMAKE_CACHE_ARGS ${PASSTHROUGH_CMAKE_CACHE_ARGS}
            EXCLUDE_FROM_ALL TRUE
        )
    else()
        ExternalProject_Add(
            ${TARGET_NAME}-external
            URL ${DOWNLOAD_URL}
            URL_HASH ${URL_HASH}
            DOWNLOAD_EXTRACT_TIMESTAMP TRUE
            SOURCE_DIR "${BINARY_DIR}/3rdparty/${TARGET_NAME}-src"
            BINARY_DIR "${BINARY_DIR}/3rdparty/${TARGET_NAME}-src"
            UPDATE_DISCONNECTED YES
            BUILD_COMMAND make -j4
            CMAKE_COMMAND ""
            UPDATE_COMMAND ""
            INSTALL_COMMAND make install
            BUILD_BYPRODUCTS "${BUILD_SDK_INSTALL}/${BYPRODUCT}"
            CONFIGURE_COMMAND ${CONFIGURE_COMMAND_BUILD}
            INSTALL_DIR "${BUILD_SDK_INSTALL}"
            LIST_SEPARATOR %
            CMAKE_ARGS ${BUILD_CMAKE_ARGS}
            CMAKE_CACHE_ARGS ${PASSTHROUGH_CMAKE_CACHE_ARGS}
            EXCLUDE_FROM_ALL TRUE
        )
    endif()

    set(${TARGET_NAME}_EXTERNAL ${TARGET_NAME}-external PARENT_SCOPE)
    set(${TARGET_NAME}_FOUND "YES" CACHE STRING "" FORCE)
    set(${TARGET_NAME}_INCLUDE_DIR "${BUILD_SDK_INSTALL}/include" CACHE STRING "" FORCE)
    set(${TARGET_NAME}_LIBRARY "${BUILD_SDK_INSTALL}/${BYPRODUCT}" CACHE STRING "" FORCE)
    set(${TARGET_NAME}_LIBRARIES ${${TARGET_NAME}_LIBRARY} CACHE STRING "" FORCE)
    file(MAKE_DIRECTORY ${${TARGET_NAME}_INCLUDE_DIR})

    if(IS_STATIC)
        add_library(${TARGET_NAME} STATIC IMPORTED GLOBAL)
        set_target_properties(${TARGET_NAME} PROPERTIES
            IMPORTED_LOCATION "${${TARGET_NAME}_LIBRARY}"
            INTERFACE_LINK_LIBRARIES "${${TARGET_NAME}_LIBRARY}"
        )
        add_dependencies(${TARGET_NAME} ${TARGET_NAME}-external)
        target_include_directories(${TARGET_NAME} INTERFACE ${${TARGET_NAME}_INCLUDE_DIR})
    else()
        add_library(${TARGET_NAME} SHARED IMPORTED GLOBAL)
        set_target_properties(${TARGET_NAME} PROPERTIES
            IMPORTED_LOCATION "${${TARGET_NAME}_LIBRARY}"
            INTERFACE_LINK_LIBRARIES "${${TARGET_NAME}_LIBRARY}"
            IMPORTED_NO_SONAME TRUE
        )
        target_include_directories(${TARGET_NAME} INTERFACE ${${TARGET_NAME}_INCLUDE_DIR})
        add_custom_target(${TARGET_NAME}_deps DEPENDS ${TARGET_NAME}-external)
        add_dependencies(${TARGET_NAME} ${TARGET_NAME}_deps)
    endif()

    if(DEFINED ${TARGET_NAME}_INTERFACE_DEFINES)
        target_compile_definitions(${TARGET_NAME} INTERFACE ${${TARGET_NAME}_INTERFACE_DEFINES})
    endif()

    # find_package config
    set(CONFIG_INSTALL_DIR "${BUILD_SDK_INSTALL}/lib/cmake/${TARGET_NAME}")
    file(MAKE_DIRECTORY ${CONFIG_INSTALL_DIR})
    if(IS_STATIC)
        set(TEMPLATE_FILE "${_BuildAndRepository_DIR}/FindPackageConfig-Static.cmake.in")
    else()
        set(TEMPLATE_FILE "${_BuildAndRepository_DIR}/FindPackageConfig-Shared.cmake.in")
    endif()
    configure_file("${TEMPLATE_FILE}" "${CONFIG_INSTALL_DIR}/${TARGET_NAME}Config.cmake" @ONLY)
    set(VERSION_TEMPLATE "${_BuildAndRepository_DIR}/FindPackageConfig-Version.cmake.in")
    configure_file("${VERSION_TEMPLATE}" "${CONFIG_INSTALL_DIR}/${TARGET_NAME}ConfigVersion.cmake" @ONLY)
    message(STATUS "${TARGET_NAME} find_package config generated: ${CONFIG_INSTALL_DIR}")
endfunction()
