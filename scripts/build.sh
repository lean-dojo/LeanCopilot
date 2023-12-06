#!/bin/sh

# This script demonstrates how to build LeanCopilot in GitHub Codespace. 
# 1. Launch a codespace for LeanCopilot.
# 2. Run `source scripts/build.sh`.

# Set up elan.
curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y
source $HOME/.elan/env

# Build the project.
lake build
lake script run LeanCopilot/download
lake build LeanCopilotTests
