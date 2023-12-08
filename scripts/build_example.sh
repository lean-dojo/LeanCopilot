#!/bin/sh

# This script demonstrates how to build a repo that depends on Lean Copilot in GitHub Codespace. 
# 1. Launch a codespace for LeanCopilot.
# 2. Run `source scripts/build_example.sh`.

# Set up elan.
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y
source $HOME/.elan/env

# Set up lean4-example.
cd /workspaces
git clone https://github.com/yangky11/lean4-example
cd lean4-example
git checkout LeanCopilot-demo

# Build lean4-example.
lake exe LeanCopilot/download
lake build
