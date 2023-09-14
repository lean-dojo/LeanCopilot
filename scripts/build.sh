#!/bin/sh

# This script demonstrates how to build LeanInfer in GitHub Codespace. 
# 1. Launch a codespace for LeanInfer.
# 2. Run `source scripts/build.sh`.

# Set up LLVM.
wget https://github.com/llvm/llvm-project/releases/download/llvmorg-16.0.0/clang+llvm-16.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
tar -xf clang+llvm-16.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz -C /workspaces/ && rm clang+llvm-16.0.0-x86_64-linux-gnu-ubuntu-18.04.tar.xz
LLVM_HOME="/workspaces/clang+llvm-16.0.0-x86_64-linux-gnu-ubuntu-18.04"
export PATH="${LLVM_HOME}/bin":$PATH
export LIBRARY_PATH="${LLVM_HOME}/lib/x86_64-unknown-linux-gnu":$LIBRARY_PATH
export LD_LIBRARY_PATH="${LLVM_HOME}/lib/x86_64-unknown-linux-gnu":$LD_LIBRARY_PATH

# Set up elan.
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y
source $HOME/.elan/env

# Download the ONNX model.
git lfs install && git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small

# Double-check and build.
lake build
lake build Examples
