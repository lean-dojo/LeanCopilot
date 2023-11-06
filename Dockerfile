FROM ubuntu:latest

WORKDIR /LeanInfer
COPY . .

# Install dependencies.
RUN apt-get update && apt-get install -y curl wget git git-lfs cmake clang lld libc++-dev libopenblas-dev

# Install elan.
ENV ELAN_HOME="/.elan"
ENV PATH="${ELAN_HOME}/bin:${PATH}"
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y

# Build the Lean project.
RUN lake build
RUN lake script run LeanInfer/download
RUN lake build LeanInferTests