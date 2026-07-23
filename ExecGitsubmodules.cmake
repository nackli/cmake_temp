# 定义函数：init_git_submodules()
# 作用：在调用该函数的 CMakeLists.txt 所在目录执行 git submodule update --init --recursive
# 参数（可选）：
#   TARGET_DIR - 指定执行目录，默认为 ${CMAKE_CURRENT_SOURCE_DIR}
function(InitGitSubmodules)
    # 解析可选参数
    set(options "")
    set(oneValueArgs TARGET_DIR)
    set(multiValueArgs "")
    cmake_parse_arguments(GIT_SUB "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    # 设定工作目录：若指定则用指定，否则用当前 CMake 文件所在目录
    if(GIT_SUB_TARGET_DIR)
        set(WORK_DIR "${GIT_SUB_TARGET_DIR}")
    else()
        set(WORK_DIR "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()

    # 查找 Git
    find_package(Git QUIET)
    if(NOT GIT_FOUND)
        message(WARNING "Git not found, cannot update submodules.")
        return()
    endif()

    # 检查工作目录是否是一个 Git 仓库（是否有 .git 子目录或 .git 文件）
    if(NOT EXISTS "${WORK_DIR}/.git")
        message(STATUS "Not a Git repository (${WORK_DIR}), skipping submodule update.")
        return()
    endif()

    message(STATUS "Initializing/updating Git submodules in ${WORK_DIR} ...")

    # 执行命令
    execute_process(
        COMMAND ${GIT_EXECUTABLE} submodule update --init --recursive
        WORKING_DIRECTORY ${WORK_DIR}
        RESULT_VARIABLE GIT_RESULT
        OUTPUT_VARIABLE GIT_OUTPUT
        ERROR_VARIABLE GIT_ERROR
    )

    # 打印输出信息（便于调试）
    if(GIT_OUTPUT)
        message(STATUS "Git output: ${GIT_OUTPUT}")
    endif()
    if(GIT_ERROR)
        message(STATUS "Git error: ${GIT_ERROR}")
    endif()

    # 检查结果
    if(NOT GIT_RESULT EQUAL 0)
        message(FATAL_ERROR 
            "git submodule update failed (code ${GIT_RESULT})\n"
            "Working dir: ${WORK_DIR}\n"
            "Error output:\n${GIT_ERROR}\n"
            "Standard output:\n${GIT_OUTPUT}"
        )
    else()
        message(STATUS "Git submodules updated successfully.")
    endif()
endfunction()