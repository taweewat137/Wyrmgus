# Building Wyrmgus on Ubuntu 24.04 (GCC 13)

This documents a reproducible Linux build of Wyrmgus as of October 2026.
Measured on Ubuntu 24.04.5, GCC 13.3.0, CMake 3.28.3, 4 CPU cores.

The upstream Linux CI image (`.github/Dockerfile-jammy`) is Qt5-based and no
longer matches `CMakeLists.txt`, which requires **Qt 6.8** including
`Qt6::Location`. Ubuntu 24.04 ships Qt 6.4.2 and no `qt6-location` package at
all, so Qt has to come from elsewhere (section 2).

## 1. apt packages

```sh
sudo apt-get install -y \
  build-essential cmake git ninja-build \
  libsdl2-dev libsdl2-mixer-dev libpng-dev zlib1g-dev \
  liblua5.1-0-dev libtolua++5.1-dev libboost-all-dev \
  libgl1-mesa-dev xvfb
```

On a stock Ubuntu 24.04 image the following were missing and had to be
installed: `libsdl2-dev libsdl2-mixer-dev liblua5.1-0-dev libtolua++5.1-dev
libboost-all-dev libgl1-mesa-dev` (plus `ninja-build`, needed only for the Qt
module builds below). The Ubuntu `qt6-*-dev` packages are **not** sufficient
and are not needed if you follow section 2.

## 2. Qt 6.8 with QtLocation

`qt6-main` and `qt6-multimedia` 6.8.x are available on conda-forge; QtLocation
and QtPositioning are not, so they are built from source against that Qt.

```sh
# micromamba (any conda front end works)
mkdir -p /opt/micromamba/bin
curl -L -o /opt/micromamba/bin/micromamba \
  https://github.com/mamba-org/micromamba-releases/releases/latest/download/micromamba-linux-64
chmod +x /opt/micromamba/bin/micromamba
export MAMBA_ROOT_PREFIX=/opt/micromamba/root

# Qt 6.8.x into /opt/qt68 (Core, Gui, Network, Widgets, Qml, Quick, ShaderTools, Multimedia)
/opt/micromamba/bin/micromamba create -y -p /opt/qt68 -c conda-forge \
  'qt6-main>=6.8,<6.9' 'qt6-multimedia>=6.8,<6.9'

# QtPositioning + QtLocation, same version as the installed Qt (6.8.4 here)
export PATH=/opt/qt68/bin:$PATH
mkdir -p /opt/qtsrc && cd /opt/qtsrc
git clone --depth 1 --branch v6.8.4-lts-lgpl https://github.com/qt/qtpositioning.git
git clone --depth 1 --branch v6.8.4-lts-lgpl https://github.com/qt/qtlocation.git
for m in qtpositioning qtlocation; do
  cmake -S $m -B $m/build -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH=/opt/qt68 -DCMAKE_INSTALL_PREFIX=/opt/qt68 \
    -DQT_BUILD_TESTS=OFF -DQT_BUILD_EXAMPLES=OFF
  cmake --build $m/build --parallel
  cmake --install $m/build
done
```

Check the installed Qt version with `grep PACKAGE_VERSION
/opt/qt68/lib/cmake/Qt6/Qt6ConfigVersion.cmake` and pick the matching
`v6.8.x-lts-lgpl` tag.

## 3. Source patches

Two of the GCC fixes live in the `archimedes` submodule, which is pinned to
upstream. They are kept as patch files in `patches/archimedes/` and applied by
`apply-patches.sh` (idempotent; safe to re-run):

| Patch | What it fixes |
|---|---|
| `0001-gcc-libstdcxx-portability.patch` | `aggregate_exception::what()` lacked `noexcept` (hard error on GCC); `database.cpp` only recognised MSVC spellings of `std::string` / `std::filesystem::path` type names, so loading any game database failed at runtime with libstdc++ |

Fixes applied directly in this repository:

- `src/network/net_message.cpp`: include `<arpa/inet.h>` on non-Windows for `htonl`/`ntohl`.
- `src/stratagus/stratagus.cpp`: build the `stdout.txt`/`stderr.txt` log paths with `std::filesystem::path` instead of a hard-coded `\`.
- `CMakeLists.txt`: adds `-Wno-changes-meaning` for GCC >= 13 (set before `add_subdirectory(archimedes)` so it covers the submodule). GCC 13 otherwise rejects `character_base`'s `gender` member, which shadows its enum type.

## 4. Configure and build

```sh
git clone --recursive https://github.com/taweewat137/Wyrmgus.git
cd Wyrmgus
./apply-patches.sh

export PATH=/opt/qt68/bin:$PATH
cmake -B build -DCMAKE_BUILD_TYPE=Release \
  -DENABLE_STATIC=OFF -DOpenGL_GL_PREFERENCE=GLVND \
  -DWITH_GEOJSON=OFF -DWITH_X11=ON \
  -DCMAKE_PREFIX_PATH=/opt/qt68
cmake --build build -j"$(nproc)" --target wyrmgus_main wyrmgus_test
(cd build && ctest -R wyrmgus_test --output-on-failure)
```

These are the flags from `.github/workflows/testing.yml` plus
`CMAKE_PREFIX_PATH`. `-DWITH_WARNINGS_AS_ERRORS=ON` (also used by CI) is not
recommended yet: the build still emits a few hundred `-Wall` warnings, mostly
`inline function ... used but never defined` from
`archimedes/src/util/fractional_int.h`.

## 5. Measured build times (4 cores, Release, unity build)

| Step | Time |
|---|---|
| QtPositioning 6.8.4 from source | 54 s |
| QtLocation 6.8.4 from source | 1 min 37 s |
| `cmake -B build` (configure) | about 5 s |
| `wyrmgus_main` + `wyrmgus_test` from scratch | 4 min 57 s to 5 min 36 s |
| `ctest` (`wyrmgus_test`, 4 cases) | under 1 s |

## 6. Running headless (smoke test as in CI)

```sh
git clone --depth 1 https://github.com/Andrettin/Wyrmsun build/Wyrmsun
Xvfb :0 -screen 0 1280x720x24 &
export DISPLAY=:0 LANG=C.UTF-8 SDL_AUDIODRIVER=dummy
timeout 300 build/wyrmgus -t -d build/Wyrmsun/     # -t: load everything, then exit 0
```

`SDL_AUDIODRIVER=dummy` is needed because the `libSDL2` that ends up on the
RPATH comes from the conda prefix (a dependency of `qt6-multimedia`) and has no
ALSA backend, and containers usually have no PulseAudio server. The game writes
its own `stdout.txt`/`stderr.txt` into the data directory; a harmless
`PulseAudioService: pa_context_connect() failed` from Qt Multimedia is expected
there. The `-t` run loads about 3,400 `data/**/*.txt` files and about 500 Lua
scripts from Wyrmsun before exiting.

## 7. Continuous integration

`.github/workflows/testing.yml` runs the same recipe on a stock
`ubuntu-24.04` GitHub runner: it applies the submodule patches, installs the
apt packages from section 1, installs Qt 6.8 (with `qtpositioning`,
`qtlocation`, `qtmultimedia`, `qtshadertools`) through
`jurplel/install-qt-action`, builds `wyrmgus_main` and `wyrmgus_test`, runs
`ctest -R wyrmgus_test`, and finally runs the Wyrmsun smoke test under Xvfb
with `SDL_AUDIODRIVER=dummy`. The game's `stdout.txt` and `stderr.txt` are
printed at the end of every run. On a fork, GitHub Actions has to be enabled
once from the repository's Actions tab before the workflow can run.
