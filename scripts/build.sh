#!/bin/sh

# This script demonstrates how to build LeanInfer in GitHub Codespace. 
# 1. Launch a codespace for LeanInfer.
# 2. Run `source scripts/build.sh`.

# Install OpenBLAS.
sudo apt-get update && sudo apt-get install -y libopenblas-dev

# Set up elan.
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y
source $HOME/.elan/env

# Build the project.
lake build
lake script run LeanInfer/download
lake build LeanInferTests
