function(set_cpp_version)
    if (MSVC)
        if ((MSVC_VERSION GREATER_EQUAL "1910"))  # VS 2017 15.0+
            # 使用 CMake 的标准属性，不要手动添加 /std:c++latest
            set(CMAKE_CXX_STANDARD 20 PARENT_SCOPE)
            set(CMAKE_CXX_STANDARD_REQUIRED ON PARENT_SCOPE)
            set(CMAKE_CXX_EXTENSIONS OFF PARENT_SCOPE)
            
            # /permissive- 需要通过其他方式添加
            add_compile_options("/permissive-")
        else()
            message(STATUS "The Visual Studio C++ compiler ${CMAKE_CXX_COMPILER} is not supported. Please use Visual Studio 2017 or newer.")
        endif()
    else()
        # 检测可用的最高 C++ 标准
        include(CheckCXXCompilerFlag)
        
        if(NOT CMAKE_CXX_STANDARD)
            # 从高到低检测
            if(CMAKE_CXX_COMPILER_ID MATCHES "GNU" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 10)
                set(SUGGESTED_STD 20)
            elseif(CMAKE_CXX_COMPILER_ID MATCHES "Clang" AND CMAKE_CXX_COMPILER_VERSION VERSION_GREATER_EQUAL 10)
                set(SUGGESTED_STD 20)
            else()
                set(SUGGESTED_STD 17)
            endif()
            
            CHECK_CXX_COMPILER_FLAG("-std=c++${SUGGESTED_STD}" COMPILER_SUPPORTS_CXX${SUGGESTED_STD})
            
            if(COMPILER_SUPPORTS_CXX${SUGGESTED_STD})
                set(CMAKE_CXX_STANDARD ${SUGGESTED_STD} PARENT_SCOPE)
            else()
                # 尝试 C++17
                CHECK_CXX_COMPILER_FLAG("-std=c++17" COMPILER_SUPPORTS_CXX17)
                if(COMPILER_SUPPORTS_CXX17)
                    set(CMAKE_CXX_STANDARD 17 PARENT_SCOPE)
                else()
                    # 尝试 C++14
                    CHECK_CXX_COMPILER_FLAG("-std=c++14" COMPILER_SUPPORTS_CXX14)
                    if(COMPILER_SUPPORTS_CXX14)
                        set(CMAKE_CXX_STANDARD 14 PARENT_SCOPE)
                    else()
                        message(STATUS "The compiler ${CMAKE_CXX_COMPILER} has no support for C++14/17/20. Please use a more recent C++ compiler version.")
                        set(CMAKE_CXX_STANDARD 11 PARENT_SCOPE)
                    endif()
                endif()
            endif()
            
            set(CMAKE_CXX_STANDARD_REQUIRED ON PARENT_SCOPE)
            set(CMAKE_CXX_EXTENSIONS OFF PARENT_SCOPE)
        endif()
    endif()
endfunction()