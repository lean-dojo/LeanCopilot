FROM ubuntu:latest

WORKDIR /workspace

# Install dependencies.
RUN apt-get update && apt-get install -y curl wget git git-lfs clang lld libc++-dev

# Install elan.
ENV ELAN_HOME="/.elan"
ENV PATH="${ELAN_HOME}/bin:${PATH}"
RUN curl https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -sSf | bash -s -- -y

# Install ONNX Runtime.
RUN wget https://github.com/microsoft/onnxruntime/releases/download/v1.15.1/onnxruntime-linux-x64-1.15.1.tgz
RUN tar -xf onnxruntime-linux-x64-1.15.1.tgz && rm onnxruntime-linux-x64-1.15.1.tgz
ENV LIBRARY_PATH="/workspace/onnxruntime-linux-x64-1.15.1/lib:${LIBRARY_PATH}"
ENV LD_LIBRARY_PATH="/workspace/onnxruntime-linux-x64-1.15.1/lib:${LD_LIBRARY_PATH}"
ENV CPATH="/workspace/onnxruntime-linux-x64-1.15.1/include:${CPATH}"

RUN git clone https://github.com/lean-dojo/LeanInfer
WORKDIR /workspace/LeanInfer

# Download the ONNX model.
RUN git lfs install
RUN git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small

# Build the Lean project.
RUN lake build
