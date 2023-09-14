FROM ubuntu:latest

WORKDIR /LeanInfer
COPY . .

# Install dependencies.
RUN apt-get update && apt-get install -y curl wget git git-lfs clang lld libc++-dev

# Install elan.
ENV ELAN_HOME="/.elan"
ENV PATH="${ELAN_HOME}/bin:${PATH}"
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y

# Download the ONNX model.
RUN git lfs install
RUN git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small

# Build the Lean project.
RUN lake update
RUN lake build
