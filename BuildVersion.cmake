# 获取git信息函数
function(get_git_info)
    find_package(Git QUIET)
    
    if(NOT GIT_FOUND)
        set(GIT_TAG "unknown" PARENT_SCOPE)
        set(GIT_COMMIT "unknown" PARENT_SCOPE)
        set(GIT_DIRTY "" PARENT_SCOPE)
        return()
    endif()
    
    # 获取tag
    execute_process(
        COMMAND ${GIT_EXECUTABLE} describe --tags --abbrev=0
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE TAG_OUTPUT
        ERROR_VARIABLE TAG_ERROR
        RESULT_VARIABLE TAG_RESULT
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    
    if(TAG_RESULT EQUAL 0 AND NOT TAG_OUTPUT STREQUAL "")
        set(GIT_VERSION "${TAG_OUTPUT}")
    else()
        # 获取commit id作为fallback
        execute_process(
            COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
            WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
            OUTPUT_VARIABLE COMMIT_OUTPUT
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(GIT_VERSION "commit-${COMMIT_OUTPUT}")
    endif()
    
    # 检查是否有未提交的修改
    execute_process(
        COMMAND ${GIT_EXECUTABLE} status --porcelain
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE STATUS_OUTPUT
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    
    if(NOT STATUS_OUTPUT STREQUAL "")
        set(GIT_DIRTY "-dirty")
    else()
        set(GIT_DIRTY "")
    endif()
    
    # 获取完整信息
    execute_process(
        COMMAND ${GIT_EXECUTABLE} describe --tags --always --long
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE FULL_DESCRIBE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    
    if(FULL_DESCRIBE STREQUAL "")
        execute_process(
            COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
            WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
            OUTPUT_VARIABLE FULL_COMMIT
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(FULL_DESCRIBE "${FULL_COMMIT}")
    endif()
    
    set(GIT_TAG "${GIT_VERSION}${GIT_DIRTY}" PARENT_SCOPE)
    set(GIT_COMMIT "${FULL_DESCRIBE}" PARENT_SCOPE)
    set(GIT_DIRTY "${GIT_DIRTY}" PARENT_SCOPE)
endfunction()

# 调用函数获取git信息
get_git_info()

# 生成时间戳
string(TIMESTAMP BUILD_TIMESTAMP "%Y-%m-%d %H:%M:%S")

# 生成version.h
configure_file(
    ${CMAKE_CURRENT_SOURCE_DIR}/version.h.in
    ${CMAKE_CURRENT_BINARY_DIR}/version.h
)

# 包含生成的头文件目录
include_directories(${CMAKE_CURRENT_BINARY_DIR})