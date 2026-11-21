#!/usr/bin/env bash
set -euo pipefail

cmake --version
git clone --depth 1 https://github.com/jmpews/Dobby
cd Dobby
mkdir b
cd b
cmake .. \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_SYSTEM_PROCESSOR=arm64 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_BUILD_TYPE=Release \
  -DDOBBY_GENERATE_SHARED=OFF
make -j4
mkdir -p "$GITHUB_WORKSPACE/vendor/dobby/include"
cp libdobby.a "$GITHUB_WORKSPACE/vendor/dobby/"
lipo -info "$GITHUB_WORKSPACE/vendor/dobby/libdobby.a"
cp ../include/*.h "$GITHUB_WORKSPACE/vendor/dobby/include/"
