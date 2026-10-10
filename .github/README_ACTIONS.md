![pipeline status](
https://github.com/Andrettin/Wyrmgus/workflows/CMake/badge.svg?branch=master)

# GitHub Actions for Wyrmgus

Directory contains all necessary files for running CI processes on GitHub.
[workflows/testing.yml](workflows/testing.yml) builds and smoke-tests Wyrmgus
on a stock `ubuntu-24.04` runner, installing Qt 6.8 (with QtLocation) through
`jurplel/install-qt-action`; see [BUILD-UBUNTU.md](../BUILD-UBUNTU.md) for the
same recipe run by hand.

[Dockerfile-jammy](Dockerfile-jammy) is the old Qt5-based image used by the
previous pipeline. It no longer satisfies `CMakeLists.txt` (Qt 6.8 required)
and is kept only for reference. To build an image run command in directory
with the Dockerfile:
```
$ docker image build -f Dockerfile-name --tag 'image_name:tag' --compress --force-rm .
```

Pipeline may be ran locally with [act](https://github.com/nektos/act) tool. To
do so run act at root of the repository with a trigger name (requires Docker):
```
$ act -v push`
```

The `-v` key for verbose output.
