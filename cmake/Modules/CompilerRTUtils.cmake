include(CMakePushCheckState)
include(CheckSymbolExists)

# Because compiler-rt spends a lot of time setting up custom compile flags,
# define a handy helper function for it. The compile flags setting in CMake
# has serious issues that make its syntax challenging at best.
function(set_target_compile_flags target)
  set(argstring "")
  foreach(arg ${ARGN})
    set(argstring "${argstring} ${arg}")
  endforeach()
  set_property(TARGET ${target} PROPERTY COMPILE_FLAGS "${argstring}")
endfunction()

function(set_target_link_flags target)
  set(argstring "")
  foreach(arg ${ARGN})
    set(argstring "${argstring} ${arg}")
  endforeach()
  set_property(TARGET ${target} PROPERTY LINK_FLAGS "${argstring}")
endfunction()

# Set the variable var_PYBOOL to True if var holds a true-ish string,
# otherwise set it to False.
macro(pythonize_bool var)
  if (${var})
    set(${var}_PYBOOL True)
  else()
    set(${var}_PYBOOL False)
  endif()
endmacro()

# Appends value to all lists in ARGN, if the condition is true.
macro(append_list_if condition value)
  if(${condition})
    foreach(list ${ARGN})
      list(APPEND ${list} ${value})
    endforeach()
  endif()
endmacro()

# Appends value to all strings in ARGN, if the condition is true.
macro(append_string_if condition value)
  if(${condition})
    foreach(str ${ARGN})
      set(${str} "${${str}} ${value}")
    endforeach()
  endif()
endmacro()

macro(append_rtti_flag polarity list)
  if(polarity)
    append_list_if(COMPILER_RT_HAS_FRTTI_FLAG -frtti ${list})
    append_list_if(COMPILER_RT_HAS_GR_FLAG /GR ${list})
  else()
    append_list_if(COMPILER_RT_HAS_FNO_RTTI_FLAG -fno-rtti ${list})
    append_list_if(COMPILER_RT_HAS_GR_FLAG /GR- ${list})
  endif()
endmacro()

macro(append_have_file_definition filename varname list)
  check_include_file("${filename}" "${varname}")
  if (NOT ${varname})
    set("${varname}" 0)
  endif()
  list(APPEND ${list} "${varname}=${${varname}}")
endmacro()

macro(list_intersect output input1 input2)
  set(${output})
  foreach(it ${${input1}})
    list(FIND ${input2} ${it} index)
    if( NOT (index EQUAL -1))
      list(APPEND ${output} ${it})
    endif()
  endforeach()
endmacro()

# Takes ${ARGN} and puts only supported architectures in @out_var list.
function(filter_available_targets out_var)
  set(archs ${${out_var}})
  foreach(arch ${ARGN})
    list(FIND COMPILER_RT_SUPPORTED_ARCH ${arch} ARCH_INDEX)
    if(NOT (ARCH_INDEX EQUAL -1) AND CAN_TARGET_${arch})
      list(APPEND archs ${arch})
    endif()
  endforeach()
  set(${out_var} ${archs} PARENT_SCOPE)
endfunction()

function(check_compile_definition def argstring out_var)
  if("${def}" STREQUAL "")
    set(${out_var} TRUE PARENT_SCOPE)
    return()
  endif()
  cmake_push_check_state()
  set(CMAKE_REQUIRED_FLAGS "${CMAKE_REQUIRED_FLAGS} ${argstring}")
  check_symbol_exists(${def} "" ${out_var})
  cmake_pop_check_state()
endfunction()

# test_target_arch(<arch> <def> <target flags...>)
# Checks if architecture is supported: runs host compiler with provided
# flags to verify that:
#   1) <def> is defined (if non-empty)
#   2) simple file can be successfully built.
# If successful, saves target flags for this architecture.
macro(test_target_arch arch def)
  set(TARGET_${arch}_CFLAGS ${ARGN})
  set(TARGET_${arch}_LINKFLAGS ${ARGN})
  set(argstring "")
  foreach(arg ${ARGN})
    set(argstring "${argstring} ${arg}")
  endforeach()
  check_compile_definition("${def}" "${argstring}" HAS_${arch}_DEF)
  if(NOT DEFINED CAN_TARGET_${arch})
    if(NOT HAS_${arch}_DEF)
      set(CAN_TARGET_${arch} FALSE)
    elseif(TEST_COMPILE_ONLY)
      try_compile_only(CAN_TARGET_${arch} ${TARGET_${arch}_CFLAGS})
    else()
      set(argstring "${CMAKE_EXE_LINKER_FLAGS} ${argstring}")
      try_compile(CAN_TARGET_${arch} ${CMAKE_BINARY_DIR} ${SIMPLE_SOURCE}
                  COMPILE_DEFINITIONS "${TARGET_${arch}_CFLAGS}"
                  OUTPUT_VARIABLE TARGET_${arch}_OUTPUT
                  CMAKE_FLAGS "-DCMAKE_EXE_LINKER_FLAGS:STRING=${argstring}")
    endif()
  endif()
  if(${CAN_TARGET_${arch}})
    list(APPEND COMPILER_RT_SUPPORTED_ARCH ${arch})
  elseif("${COMPILER_RT_DEFAULT_TARGET_ARCH}" STREQUAL "${arch}" AND
         COMPILER_RT_HAS_EXPLICIT_DEFAULT_TARGET_TRIPLE)
    # Bail out if we cannot target the architecture we plan to test.
    message(FATAL_ERROR "Cannot compile for ${arch}:\n${TARGET_${arch}_OUTPUT}")
  endif()
endmacro()

macro(detect_target_arch)
  check_symbol_exists(__arm__ "" __ARM)
  check_symbol_exists(__aarch64__ "" __AARCH64)
  check_symbol_exists(__x86_64__ "" __X86_64)
  check_symbol_exists(__i686__ "" __I686)
  check_symbol_exists(__i386__ "" __I386)
  check_symbol_exists(__mips__ "" __MIPS)
  check_symbol_exists(__mips64__ "" __MIPS64)
  check_symbol_exists(__s390x__ "" __S390X)
  check_symbol_exists(__wasm32__ "" __WEBASSEMBLY32)
  check_symbol_exists(__wasm64__ "" __WEBASSEMBLY64)
  if(__ARM)
    add_default_target_arch(arm)
  elseif(__AARCH64)
    add_default_target_arch(aarch64)
  elseif(__X86_64)
    add_default_target_arch(x86_64)
  elseif(__I686)
    add_default_target_arch(i686)
  elseif(__I386)
    add_default_target_arch(i386)
  elseif(__MIPS64) # must be checked before __MIPS
    add_default_target_arch(mips64)
  elseif(__MIPS)
    add_default_target_arch(mips)
  elseif(__S390X)
    add_default_target_arch(s390x)
  elseif(__WEBASSEMBLY32)
    add_default_target_arch(wasm32)
  elseif(__WEBASSEMBLY64)
    add_default_target_arch(wasm64)
  endif()
endmacro()
