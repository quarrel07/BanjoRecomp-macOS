# Copies the real SDL3 dylib into the app bundle's Frameworks dir next to the SDL2 shim.
#
# Modern Homebrew's `sdl2` is sdl2-compat — a shim that dlopens the real SDL3 at runtime
# (`@loader_path/libSDL3.dylib`). fixup_bundle only follows load commands, never a dlopen, so it
# bundles the shim but never SDL3, and the .app aborts on launch with "Failed loading SDL3 library."
# Dropping libSDL3.dylib next to the shim (= @loader_path) satisfies the dlopen.
#
# Invoked from apple_bundle.cmake's POST_BUILD block with -D SDL3_DYLIB=<path> -D FRAMEWORKS_DIR=<dir>.
# SDL3_DYLIB is resolved at configure time; if it was empty (SDL3 not installed), this no-ops with a
# warning rather than failing the build — a real SDL2 (non-shim) build doesn't need SDL3 at all.

if (NOT SDL3_DYLIB OR SDL3_DYLIB STREQUAL "")
    message(WARNING "bundle_sdl3: no SDL3 dylib was resolved at configure time; not bundling SDL3. "
                    "If the linked SDL2 is the sdl2-compat shim, the .app will abort on launch.")
    return()
endif()

if (NOT EXISTS "${SDL3_DYLIB}")
    message(WARNING "bundle_sdl3: SDL3 dylib '${SDL3_DYLIB}' no longer exists; not bundling SDL3.")
    return()
endif()

# SDL3_DYLIB is typically a Homebrew symlink (libSDL3.dylib -> libSDL3.0.dylib). Resolve it to the real
# versioned file and copy THAT as a regular file named libSDL3.dylib: copying the symlink itself would
# leave a dangling link in the bundle (the versioned target isn't bundled), which also breaks codesign.
file(REAL_PATH "${SDL3_DYLIB}" SDL3_REAL)
if (NOT EXISTS "${SDL3_REAL}")
    message(WARNING "bundle_sdl3: resolved SDL3 path '${SDL3_REAL}' does not exist; not bundling SDL3.")
    return()
endif()

get_filename_component(_sdl3_real_name "${SDL3_REAL}" NAME)
file(COPY "${SDL3_REAL}" DESTINATION "${FRAMEWORKS_DIR}")
if (NOT _sdl3_real_name STREQUAL "libSDL3.dylib")
    file(REMOVE "${FRAMEWORKS_DIR}/libSDL3.dylib")
    file(RENAME "${FRAMEWORKS_DIR}/${_sdl3_real_name}" "${FRAMEWORKS_DIR}/libSDL3.dylib")
endif()
message(STATUS "bundle_sdl3: bundled ${SDL3_REAL} -> ${FRAMEWORKS_DIR}/libSDL3.dylib")
