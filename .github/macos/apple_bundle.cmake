# Define the path to the entitlements file
set(ENTITLEMENTS_FILE ${CMAKE_SOURCE_DIR}/.github/macos/entitlements.plist)

# Locate the real SDL3 dylib so it can be bundled alongside the SDL2 shim (see the SDL3 copy step in
# the POST_BUILD block below). Modern Homebrew's `sdl2` formula is actually sdl2-compat — a thin shim
# that dlopens the real SDL3 at runtime (`@loader_path/libSDL3.dylib`). fixup_bundle only follows load
# commands, never a dlopen, so it bundles the shim but never SDL3, and the app aborts on launch with
# "Failed loading SDL3 library." Resolve SDL3 here at configure time so the copy doesn't depend on
# `brew` being on PATH during the build.
find_program(BREW_EXECUTABLE brew)
if (BREW_EXECUTABLE)
    execute_process(COMMAND ${BREW_EXECUTABLE} --prefix sdl3
                    OUTPUT_VARIABLE SDL3_PREFIX OUTPUT_STRIP_TRAILING_WHITESPACE
                    ERROR_QUIET RESULT_VARIABLE SDL3_PREFIX_RESULT)
    if (SDL3_PREFIX_RESULT EQUAL 0 AND EXISTS "${SDL3_PREFIX}/lib/libSDL3.dylib")
        set(SDL3_DYLIB "${SDL3_PREFIX}/lib/libSDL3.dylib")
    endif()
endif()
if (NOT SDL3_DYLIB)
    message(WARNING "SDL3 dylib not found via Homebrew. If the Homebrew sdl2 in use is the sdl2-compat "
                    "shim, the bundled .app will abort on launch with \"Failed loading SDL3 library.\" "
                    "Install it with `brew install sdl3`.")
endif()

# Bundle identity — single source of truth. Used both for the target's MACOSX_BUNDLE_* properties and
# for configuring Info.plist below. We can't rely on CMake's built-in MACOSX_BUNDLE_INFO_PLIST
# substitution (it silently breaks when the build path contains spaces — see the explicit Info.plist
# copy in the POST_BUILD block), so Info.plist.in uses @VAR@ placeholders that configure_file fills
# from these variables.
set(MACOSX_BUNDLE_BUNDLE_NAME "BanjoRecompiled")
set(MACOSX_BUNDLE_GUI_IDENTIFIER "com.github.Banjorecompiled")
# macOS fork version — independent of upstream's number (this build = macOS fork 1.1.0, based on
# upstream BanjoRecomp 1.0.1). Bump on macOS-fork-visible changes; note the upstream base in the notes.
set(MACOSX_BUNDLE_BUNDLE_VERSION "1.1.0")
set(MACOSX_BUNDLE_SHORT_VERSION_STRING "1.1.0")

# Set bundle properties
set_target_properties(BanjoRecompiled PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_BUNDLE_NAME "${MACOSX_BUNDLE_BUNDLE_NAME}"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${MACOSX_BUNDLE_GUI_IDENTIFIER}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${MACOSX_BUNDLE_BUNDLE_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${MACOSX_BUNDLE_SHORT_VERSION_STRING}"
        MACOSX_BUNDLE_ICON_FILE "appicon"
        MACOSX_BUNDLE_INFO_PLIST ${CMAKE_BINARY_DIR}/Info.plist
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
        XCODE_ATTRIBUTE_CODE_SIGN_ENTITLEMENTS ${ENTITLEMENTS_FILE}
)

# Compile the app icon from the Icon Composer package (icons/appicon.icon).
#
# actool produces:
#   - Assets.car      : the compiled asset catalog, including the Liquid Glass icon used on
#                       macOS 26 (Tahoe) and later.
#   - appicon.icns    : a flattened fallback rendered by actool, used by macOS versions that
#                       predate the Liquid Glass icon system.
#   - a partial Info.plist (its keys, CFBundleIconName/CFBundleIconFile, are already set directly
#                       in Info.plist.in, so the generated partial plist is not consumed here).
# Both Assets.car and appicon.icns are copied into the bundle's Resources directory.
set(ICON_SOURCE ${CMAKE_SOURCE_DIR}/icons/appicon.icon)
set(ICON_COMPILE_DIR ${CMAKE_BINARY_DIR}/AppIconAssets)
set(ASSETS_CAR ${ICON_COMPILE_DIR}/Assets.car)
set(ICNS_FALLBACK ${ICON_COMPILE_DIR}/appicon.icns)
set(ICON_PARTIAL_PLIST ${ICON_COMPILE_DIR}/icon-partial-info.plist)

add_custom_command(
        OUTPUT ${ASSETS_CAR} ${ICNS_FALLBACK}
        COMMAND ${CMAKE_COMMAND} -E make_directory ${ICON_COMPILE_DIR}
        COMMAND xcrun actool ${ICON_SOURCE}
                --compile ${ICON_COMPILE_DIR}
                --app-icon appicon
                --output-partial-info-plist ${ICON_PARTIAL_PLIST}
                --platform macosx
                --target-device mac
                --minimum-deployment-target ${CMAKE_OSX_DEPLOYMENT_TARGET}
                --errors --warnings
        DEPENDS ${ICON_SOURCE}/icon.json
        COMMENT "Compiling app icon (Icon Composer) with actool"
)

# Custom target to ensure the icon is compiled before the bundle is assembled.
add_custom_target(create_icns ALL DEPENDS ${ASSETS_CAR} ${ICNS_FALLBACK})

# Copy the compiled catalog and fallback icns into the bundle's Resources directory.
set_source_files_properties(${ASSETS_CAR} ${ICNS_FALLBACK} PROPERTIES
        GENERATED TRUE
        MACOSX_PACKAGE_LOCATION "Resources"
)
target_sources(BanjoRecompiled PRIVATE ${ASSETS_CAR} ${ICNS_FALLBACK})

# Ensure BanjoRecompiled depends on the icon compilation.
add_dependencies(BanjoRecompiled create_icns)

# Configure Info.plist
configure_file(${CMAKE_SOURCE_DIR}/.github/macos/Info.plist.in ${CMAKE_BINARY_DIR}/Info.plist @ONLY)

# Install the app bundle
install(TARGETS BanjoRecompiled BUNDLE DESTINATION .)

# Ensure the entitlements file exists
if(NOT EXISTS ${ENTITLEMENTS_FILE})
    message(FATAL_ERROR "Entitlements file not found at ${ENTITLEMENTS_FILE}")
endif()

# Post-build steps for macOS bundle
add_custom_command(TARGET BanjoRecompiled POST_BUILD
    # Copy the Info.plist into the bundle explicitly. CMake's MACOSX_BUNDLE_INFO_PLIST wiring does not
    # emit a copy rule here (empirically no Contents/Info.plist edge is generated — this reproduces when
    # the build path contains spaces, e.g. ".../Repo Clones/..."), leaving the bundle with no Info.plist:
    # macOS then can't read CFBundleIconName/CFBundleIconFile so the app shows a generic icon, and the
    # bundle is malformed for codesign. Do it first so every step below sees a well-formed bundle.
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_BINARY_DIR}/Info.plist $<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/Info.plist

    # Copy and fix frameworks first
    COMMAND ${CMAKE_COMMAND} -D CMAKE_BUILD_TYPE=$<CONFIG> -D CMAKE_GENERATOR=${CMAKE_GENERATOR} -P ${CMAKE_SOURCE_DIR}/.github/macos/fixup_bundle.cmake

    # Bundle the real SDL3 next to the SDL2 shim (= @loader_path) so sdl2-compat can dlopen it. SDL3 is
    # self-contained (only system frameworks), so a plain copy is enough; the --deep codesign below
    # re-signs it. The helper no-ops (with a warning) if SDL3 wasn't found at configure time.
    COMMAND ${CMAKE_COMMAND} -D SDL3_DYLIB=${SDL3_DYLIB} -D FRAMEWORKS_DIR=$<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/Frameworks -P ${CMAKE_SOURCE_DIR}/.github/macos/bundle_sdl3.cmake

    # Copy all resources
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/assets ${CMAKE_BINARY_DIR}/temp_assets
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/temp_assets/scss
    COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_BINARY_DIR}/temp_assets $<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/Resources/assets
    COMMAND ${CMAKE_COMMAND} -E remove_directory ${CMAKE_BINARY_DIR}/temp_assets

    # Copy controller database
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_SOURCE_DIR}/recompcontrollerdb.txt $<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/Resources/

    # Set RPATH
    COMMAND install_name_tool -add_rpath "@executable_path/../Frameworks/" $<TARGET_BUNDLE_DIR:BanjoRecompiled>/Contents/MacOS/BanjoRecompiled

    # Sign the bundle
    COMMAND codesign --verbose=4 --options=runtime --no-strict --sign - --entitlements ${ENTITLEMENTS_FILE} --deep --force $<TARGET_BUNDLE_DIR:BanjoRecompiled>

    COMMENT "Performing post-build steps for macOS bundle"
    VERBATIM
)
