# @author nackli <nackli@163.com>
# @version 1.0
# @copyright 2025 nackli. All rights reserved.
# @License: MIT (https://opensource.org/licenses/MIT)
# @Created: 2025-03-20
#
function(use_pack_fun PACKAGE_NAME PAGE_TYPE)
    include(InstallRequiredSystemLibraries)
    if (CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR)
        install(TARGETS ${PROJECT_NAME} DESTINATION lib)
        # install(
        #     DIRECTORY 
        #         FileQueue/
        #     DESTINATION include
        #     FILES_MATCHING 
        #         PATTERN "FileQueue.h"
		# 		PATTERN "PimplMacro.h"
        #         PATTERN "test" EXCLUDE
        # )
      # CPack 配置
       # set(CPACK_RESOURCE_FILE_LICENSE "${CMAKE_CURRENT_SOURCE_DIR}/License.txt")
        set(CPACK_GENERATOR "${PAGE_TYPE}")
        set(CPACK_PACKAGE_VERSION_MAJOR "${${PACKAGE_NAME}_VERSION_MAJOR}")
        set(CPACK_PACKAGE_VERSION_MINOR "${${PACKAGE_NAME}_VERSION_MINOR}")
        set(CPACK_PACKAGE_VERSION_PATCH "${${PACKAGE_NAME}_VERSION_PATCH}")
        set(CPACK_PACKAGE_NAME "${PACKAGE_NAME}")
        set(CPACK_PACKAGE_FILE_NAME "${PACKAGE_NAME}")
        set(CPACK_INCLUDE_TOPLEVEL_DIRECTORY 0)
        include(CPack)
    endif()
endfunction(use_pack_fun)