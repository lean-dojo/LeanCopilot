LeanInfer
=========

Neural network inference in Lean 4.


## Requirements

* Supported platform: Linux and macOS
* Clang or GCC
* [Lean 4](https://leanprover.github.io/lean4/doc/quickstart.html)
* [ONNX Runtime](https://github.com/microsoft/onnxruntime/releases) for optimized inference in C++


## Using LeanInfer in Your Project

1. Download [the ONNX model](https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small) into the root of your repo (`./onnx-leandojo-lean4-tacgen-byt5-small`). If you have [Git LFS](https://git-lfs.com/), this can be done by `git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small`. See [here](https://huggingface.co/docs/hub/models-downloading) for details.
1. Edit your `lakefile.lean`. Add a dependency `require leanml from git "https://github.com/Peiyang-Song/leanml.git" @ "peiyang"` and package configuration option `moreLinkArgs := #["-lonnxruntime", "-lstdc++"]`.
1. Add the ONNX Runtime source directory (the directory that contains `onnxruntime_cxx_api.h`) to the environment variable `CPATH`. Add the ONNX Runtime library directory (the directory that contains `libonnxruntime.so` or `libonnxruntime.dylib`) to `LD_LIBRARY_PATH` (Linux), `DYLD_LIBRARY_PATH` (macOS), and `LIBRARY_PATH` (all platforms). If you are using Lean in VSCode, also add these environment variables to the `Lean4: Server Env` setting in VSCode.
2. If you are working on Linux, also add the C++ standard library directory (the directory that contains "libc++.so") to `LD_LIBRARY_PATH` and `LIBRARY_PATH`. If you are using Lean in VSCode, also add this additional environment path to the `Lean4: Server Env` setting in VSCode.
1. Run `lake update` and `lake build`.


## Code Format

`clang-format --style Google -i ffi.cpp`



## Questions and Bugs

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanInfer/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information, the version of LeanInfer, and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 


## Related Links

* [LeanDojo Website](https://leandojo.org/)
* [LeanDojo](https://github.com/lean-dojo/LeanDojo) 
* [ReProver](https://github.com/lean-dojo/ReProver)


## Acknowledgements

* [llmstep](https://github.com/wellecks/llmstep)
* [lean-gptf](https://github.com/jesse-michael-han/lean-gptf)
* [Sagredo](https://www.youtube.com/watch?v=CEwRMT0GpKo)



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


## FAQ

`libc++abi: terminating with uncaught exception of type Ort::Exception: Load model from onnx-leandojo-lean4-tacgen-byt5-small/encoder_model.onnx failed:Load model onnx-leandojo-lean4-tacgen-byt5-small/encoder_model.onnx failed. File doesn't exist`: Make sure you have downloaded the ONNX model.


`docker build . -t leanml`