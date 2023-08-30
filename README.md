# leanml

## Prerequisites

* Supported platform: Linux
* Git >= 2.25
* Lean 4
* 3.9 <= Python < 3.11
  * Packages: transformers, optimum.onnxruntime
* Clang+llvm 12.0.0
  * We heard that Clang might not be backward compatible
* ONNX Runtime 1.8.0
  * Our tool is built upon this specific version of ONNX Runtime. Other (especially later) versions may not be compatible
  * Here are some scripts that worked for my Linux platform. To obtain it,
    ```
    git clone --recursive https://github.com/Microsoft/onnxruntime
    cd onnxruntime/
    git checkout v1.8.0
    ```
    Then to compile the modules,
    ```
    ./build.sh --skip_tests --config Release --build_shared_lib
    ```
    Note that the compilation on GPU may need more args than the command above.
    A good sign for having gone through a successful installation is that you can find both `libonnxruntime.so.1.8.0` and `libonnxruntime.so` being compiled.
    Please do refer to ONNX Runtime's official documents and releases for detailed installation process.

## Installation

In an existing Lean project, you can include our tool as simple as by adding
```
require leanml from git
  "https://github.com/Peiyang-Song/leanml.git" @ "main"
```
to your lakefile.
Also, we would recommend adding a direct linker argument for the ONNX Runtime dynamic libraries to your package config. E.g.,
```
package «lean4-example» {
  precompileModules := true
  moreLinkArgs := #[
    "-L", "/home/peiyang/onnxruntime/build/Linux/RelWithDebInfo", "-lonnxruntime"
  ]
}
```
The next `lake build` or `lake update` will install the whole package for you.

## Usage

In this project, we choose to use [ReProver](https://github.com/lean-dojo/ReProver) for tactic suggestion, which will be the assuption for the guides below. However, you can easily adopt another model by changing the model names in both `PyONNX.py` and `ffi.cpp`. Both can be set by directly changing the one constant at the beginning of the file.

Assuming you are using ReProver, first run `python lake-packages/leanml/PyONNX.py` to get the ONNX intermediate representation of the model. Then you are ready to import `import Leanml` and insert `trace_goal_state` at any point of your Lean 4 proof file. See [this repo](https://github.com/yangky11/lean4-example/tree/peiyang-leanml-demo) for a simple example.

## Current status

Our ultimate goal is that wherever you call `trace_goal_state` in a Lean 4 proof file, we should be able to output you a list of tactic suggestions, displayed under `messages` in the InfoView. The current status is that the general code pipeline is indeed working, as `lake build` does give the desired outputs in step 3 via stdout. However the InfoView is not working since the file cannot compile.
