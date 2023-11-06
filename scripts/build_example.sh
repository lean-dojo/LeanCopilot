#!/bin/sh

# This script demonstrates how to build a repo that depends on LeanInfer in GitHub Codespace. 
# 1. Launch a codespace for LeanInfer.
# 2. Run `source scripts/build_example.sh`.

# Install OpenBLAS.
sudo apt-get update && sudo apt-get install -y libopenblas-dev

# Set up elan.
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y
source $HOME/.elan/env

# Set up lean4-example.
cd /workspaces
git clone https://github.com/yangky11/lean4-example
cd lean4-example
git checkout LeanInfer-demo

# Build lean4-example.
lake script run LeanInfer/download
lake build
