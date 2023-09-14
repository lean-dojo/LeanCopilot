LeanInfer: Neural Network Inference in Lean 4
=============================================

LeanInfer provides tactic suggestions by running LLMs through Lean's foreign function interface (FFI). 

<img width="1087" alt="LeanInfer" src="https://github.com/lean-dojo/LeanInfer/assets/5431913/f87ec407-29a5-4468-b2fb-a2f6e9105ae9">

It is in an early stage of development. In the long term, we aim to integrate Lean and machine learning by providing a general and efficient way to run the inference of neural networks in Lean. The network can be of arbitrary model architectures and trained using arbitrary deep learning frameworks. After training, it is converted into the ONNX format, which can be run as a shared library using [ONNX Runtime](https://onnxruntime.ai/) and integrated into Lean through FFI. 



## Requirements

* Supported platforms: Linux and macOS (:warning: maybe also Windows WSL, but untested)


## Adding LeanInfer as a Dependency to Your Project

1. Download the model ([LeanDojo's tactic generator in ONNX format](https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small)) into the root of the repo. If you have [Git LFS](https://git-lfs.com/), this can be done by `git lfs install && git clone https://huggingface.co/kaiyuy/onnx-leandojo-lean4-tacgen-byt5-small`. Otherwise, see [here](https://huggingface.co/docs/hub/models-downloading).
2. Add the package configuration option `moreLinkArgs := #[s!"-L./lake-packages/LeanInfer/build/lib", "-lonnxruntime", "-lstdc++"]` to lakefile.lean. Also add LeanInfer as a dependency:
```lean
require LeanInfer from git "https://github.com/lean-dojo/LeanInfer.git"@"v0.0.3" with
  if let some noLeanInferCloudRelease := get_config? noLeanInferCloudRelease then
    NameMap.empty.insert `noCloudRelease noLeanInferCloudRelease
  else
    NameMap.empty
```
3. Run `lake update` for the changes to take effect. Finally, if you're using Linux or macOS (Intel), run `lake build`. If you're using macOS (Apple Silicon), run `lake build -KnoLeanInferCloudRelease=true`.

You may also see the [example here](https://github.com/yangky11/lean4-example/blob/LeanInfer-demo). If you have problems building the project, our [Dockerfile](./Dockerfile), [build.sh](scripts/build.sh) or [build_example.sh](scripts/build_example.sh) may be helpful.


## Using LeanInfer's Tactic Generator

After `import LeanInfer`, you can use the tactic `suggest_tactics` (see the image above and [this example](https://github.com/yangky11/lean4-example/blob/ab7bc199aedb66992689412ceb8b5a1e44af7ec5/Lean4Example.lean#L12)).


## Building LeanInfer

You don't need to build LeanInfer directly if you use it in a downstream package. Nevertheless, if you really need to build LeanInfer, you can run `lake build`. It shouldn't have any problem on macOS. On Linux, you need LLVM (w/ at least [Clang](https://clang.llvm.org/), [LLD](https://lld.llvm.org/), [libc++](https://libcxx.llvm.org/), [libc++abi](https://libcxxabi.llvm.org/), and [libunwind](https://github.com/llvm/llvm-project/tree/main/libunwind)). We recommend downloading clang+llvm from [here](https://github.com/llvm/llvm-project/releases/tag/llvmorg-16.0.0) and setting the environment variables `PATH`, `LIBRARY_PATH`, and `LD_LIBRARY_PATH` accordingly ([example here](./scripts/build.sh)). 

:warning: LLVM installed by `apt-get` may be incomplete. 
:warning: GCC is not supported.




## Questions and Bugs

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanInfer/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 


## Related Links

* [LeanDojo Website](https://leandojo.org/)
* [LeanDojo](https://github.com/lean-dojo/LeanDojo) 
* [ReProver](https://github.com/lean-dojo/ReProver)


## Acknowledgements

* [llmstep](https://github.com/wellecks/llmstep) is another tool providing tactic suggestions using LLMs. We use their frontend for displaying tactics but a different mechanism for running the model.
* We thank Scott Morrison for suggestions on simplifying the installation process and Mac Malone for helping implement it. Both Scott and Mac work for the [Lean FRO](https://lean-fro.org/).



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
