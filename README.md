LeanInfer
=========

Neural network inference in Lean 4 via FFI.


## Requirements

* Supported platform: Linux and macOS
* [Clang](https://clang.llvm.org/) (:warning: GCC not supported)
* [Lean 4](https://leanprover.github.io/lean4/doc/quickstart.html)
* [ONNX Runtime](https://github.com/microsoft/onnxruntime/releases) for optimized inference in C++


## Building LeanInfer

1. Download the model ([LeanDojo's tactic generator in ONNX format](https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small)) into the root of the repo. If you have [Git LFS](https://git-lfs.com/), this can be done by `git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small`. See [here](https://huggingface.co/docs/hub/models-downloading) for details.
1. Add the ONNX Runtime source directory (the directory that contains `onnxruntime_cxx_api.h`) to the environment variable `CPATH`. Add the ONNX Runtime library directory (the directory that contains `libonnxruntime.so` or `libonnxruntime.dylib`) to `LD_LIBRARY_PATH` (Linux), `DYLD_LIBRARY_PATH` (macOS), and `LIBRARY_PATH` (all platforms). If you are using Lean in VSCode, also add these environment variables to the `Lean4: Server Env` setting in VSCode.
1. If your default C++ compiler is not Clang (e.g., in most Linux systems), add LLVM's libc++ directory (the directory that contains `libc++.so`) to `LD_LIBRARY_PATH` (Linux), `DYLD_LIBRARY_PATH` (macOS), and `LIBRARY_PATH`. If you are using Lean in VSCode, also add it to `Lean4: Server Env`.
1. Run `lake script run check` and fix problems (if any).
1. Run `lake build`.


## Using LeanInfer in Your Project

1. Edit `lakefile.lean` to add the dependency `require LeanInfer from git "https://github.com/lean-dojo/LeanInfer.git"` and package configuration option `moreLinkArgs := #["-lonnxruntime", "-lstdc++"]`.
1. Run `lake update`.
1. Follow the steps above to download the model, set environment variables, run checks, and build the project.



## Questions and Bugs

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanInfer/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information, the version of LeanInfer, and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 
* If you cannot build the project, our [Dockerfile](./Dockerfile) may be helpful.


## Related Links

* [LeanDojo Website](https://leandojo.org/)
* [LeanDojo](https://github.com/lean-dojo/LeanDojo) 
* [ReProver](https://github.com/lean-dojo/ReProver)


## Acknowledgements

* Our frontend for displaying tactic suggestions is from [llmstep](https://github.com/wellecks/llmstep).



## Citation

```bibtex
@misc{leaninfer,
  author = {Song, Peiyang and Yang, Kaiyu and Anandkumar, Anima},
  title = {LeanInfer: Neural Network Inference in Lean 4},
  year = {2023},
  publisher = {GitHub},
  journal = {GitHub repository},
  howpublished = {\url{https://github.com/lean-dojo/LeanInfer}},
}
```


## Code Formatting

The C++ code in this project is formatted using [ClangFormat](https://clang.llvm.org/docs/ClangFormat.html). To format the code, run
```bash
clang-format --style Google -i ffi.cpp
```
