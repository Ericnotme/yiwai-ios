#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
python3 scripts/verify-source.py
command -v emcc >/dev/null
command -v emmake >/dev/null
command -v node >/dev/null
command -v make >/dev/null
mkdir -p build
if [ -e build/stockfish ]; then
  echo 'build/stockfish already exists. Use a fresh checkout/build directory.' >&2
  exit 1
fi
mkdir build/stockfish
tar -xzf YiwaiPractice/Resources/Stockfish/stockfish19-source.tar.gz -C build/stockfish
engine=build/stockfish/stockfish.js-54fde71d90c7c403964f6cacef48f7bbec495df1
cp vendor/stockfish/nn-61e7af4bb97d.nnue "$engine/src/nn-61e7af4bb97d.nnue"
cd "$engine"
node build.js --lite --single-threaded --no-split --strict-em-check -f
