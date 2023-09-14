#!/bin/sh
# This is WIP. Don't use it yet!

rm -rf build_x86_64 build_arm64

lake update

lake clean
lake build -KtargetArch="x86_64-apple-macos"
rm build/ir/LeanInfer/*.o build/ir/LeanInfer/*.o.trace
rm build/lib/*.dylib build/lib/*.dylib.trace
mv build build_x86_64

lake clean
lake build -KtargetArch="arm64-apple-macos"
rm build/ir/LeanInfer/*.o build/ir/LeanInfer/*.o.trace
rm build/lib/*.dylib build/lib/*.dylib.trace
cp -r build build_arm64

rm build/cpp/generator.o build/cpp/retriever.o build/lib/libleanffi.a
lipo -create -output build/cpp/generator.o build_arm64/cpp/generator.o build_x86_64/cpp/generator.o
lipo -create -output build/cpp/retriever.o build_arm64/cpp/retriever.o build_x86_64/cpp/retriever.o
lipo -create -output build/lib/libleanffi.a build_arm64/lib/libleanffi.a build_x86_64/lib/libleanffi.a
