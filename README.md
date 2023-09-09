LeanInfer: Neural Network Inference in Lean 4
=============================================

LeanInfer provides tactic suggestions by running LLMs through Lean's foreign function interface (FFI). 

<img width="1087" alt="LeanInfer" src="https://github.com/lean-dojo/LeanInfer/assets/5431913/f87ec407-29a5-4468-b2fb-a2f6e9105ae9">

It is in an early stage of development. In the long term, we aim to integrate Lean and machine learning by providing a general and efficient way to run the inference of neural networks in Lean. The network can be of arbitrary model architectures and trained using arbitrary deep learning frameworks. After training, it is converted into the ONNX format, which can be run as a shared library using [ONNX Runtime](https://onnxruntime.ai/) and integrated into Lean through FFI. 



## Requirements

* Supported platforms: Linux and macOS (:warning: maybe also Windows, but not tested)
* [Clang](https://clang.llvm.org/) (:warning: GCC not supported)
* [Lean 4](https://leanprover.github.io/lean4/doc/quickstart.html)
* [ONNX Runtime](https://github.com/microsoft/onnxruntime/releases) for optimized inference in C++


## Adding LeanInfer as a Dependency to Your Project

1. Edit `lakefile.lean` to add the dependency `require LeanInfer from git "https://github.com/lean-dojo/LeanInfer.git"` and package configuration option `moreLinkArgs := #["-lonnxruntime", "-lstdc++"]` (see [this example](https://github.com/yangky11/lean4-example/blob/LeanInfer-demo/lakefile.lean)). Run `lake update` for the changes to take effect.
1. Download the model ([LeanDojo's tactic generator in ONNX format](https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small)) into the root of the repo. If you have [Git LFS](https://git-lfs.com/), this can be done by `git lfs install && git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small`. Otherwise, see [here](https://huggingface.co/docs/hub/models-downloading).
1. Add the ONNX Runtime source directory (the directory that contains `onnxruntime_cxx_api.h`) to the environment variable `CPATH`. Add the ONNX Runtime library directory (the directory that contains `libonnxruntime.so` or `libonnxruntime.dylib`) to `LD_LIBRARY_PATH` (Linux), `DYLD_LIBRARY_PATH` (macOS), and `LIBRARY_PATH` (all platforms). If you are using Lean in VSCode, also add these environment variables to the `Lean4: Server Env` setting in VSCode.
1. If your default C++ compiler is not Clang (e.g., in most Linux systems), add LLVM's libc++ directory (the directory that contains `libc++.so`) to `LD_LIBRARY_PATH` (Linux), `DYLD_LIBRARY_PATH` (macOS), and `LIBRARY_PATH`. If you are using Lean in VSCode, also add it to `Lean4: Server Env`.
1. Run `lake script run LeanInfer/check` and fix problems (if any). Finally, run `lake build`.


If you have problems building the project, our [Dockerfile](./Dockerfile) may be helpful as a reference. Note that it doesn't need Step 4 because the base Ubuntu image has no compiler pre-installed.


## Using LeanInfer's Tactic Generator

After `import LeanInfer`, you can use the tactic `suggest_tactics` (see the image above and [this example](https://github.com/yangky11/lean4-example/blob/e3bf4abc62fdf6566a01ce9066d152fde3f888d1/Lean4Example.lean#L12)).


## Questions and Bugs

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanInfer/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 


## Related Links

* [LeanDojo Website](https://leandojo.org/)
* [LeanDojo](https://github.com/lean-dojo/LeanDojo) 
* [ReProver](https://github.com/lean-dojo/ReProver)


## Acknowledgements

* Our frontend for displaying tactics is from [llmstep](https://github.com/wellecks/llmstep).



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

