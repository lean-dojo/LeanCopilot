#!/bin/sh

# This script demonstrates how to build a repo that depends on LeanInfer in GitHub Codespace. 
# 1. Launch a codespace for LeanInfer.
# 2. Run `source scripts/build_example.sh`.

# Set up elan.
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y
source $HOME/.elan/env

# Set up lean4-example.
cd /workspaces
git clone https://github.com/yangky11/lean4-example
cd lean4-example
git checkout LeanInfer-demo

# Download the ONNX model.
rm -rf onnx-leandojo-lean4-tacgen-byt5-small
git lfs install
git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small

# Double-check and build.
lake update
lake build
