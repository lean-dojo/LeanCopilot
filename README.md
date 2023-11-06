LeanInfer: Native Neural Network Inference in Lean 4
=============================================

<img width="1087" alt="LeanInfer" src="https://github.com/lean-dojo/LeanInfer/assets/5431913/f87ec407-29a5-4468-b2fb-a2f6e9105ae9">

LeanInfer provides tactic suggestions by running LLMs through Lean's foreign function interface (FFI). It is in an early stage of development. In the long term, we aim to integrate Lean and machine learning by providing a general and efficient way to run the inference of neural networks in Lean. 


## Requirements

* Supported platforms: Linux and macOS (:warning: maybe also Windows WSL, but untested)
* Git LFS
* A C++17 compatible compiler, e.g., recent versions of GCC or Clang
* CMake >= 3.7
* Optional (recommended if you have a [CUDA-enabled GPU](https://developer.nvidia.com/cuda-gpus)): CUDA and [cuDNN](https://developer.nvidia.com/cudnn)

**Please run `lake script run LeanInfer/check` to check if the requirements have been satisfied.**

## Adding LeanInfer as a Dependency to Your Project

1. Add the package configuration option `moreLinkArgs := #["-L./lake-packages/LeanInfer/build/lib", "-lonnxruntime", "-lctranslate2"]` to lakefile.lean. Also add LeanInfer as a dependency:
```lean
require LeanInfer from git "https://github.com/lean-dojo/LeanInfer.git" @ "main"
```
2. Run `lake update LeanInfer && lake build`

You may also see the [example here](https://github.com/yangky11/lean4-example/blob/LeanInfer-demo). If you have problems building the project, our [Dockerfile](./Dockerfile), [build.sh](scripts/build.sh) or [build_example.sh](scripts/build_example.sh) may be helpful.


## Using LeanInfer's Tactic Generator

After `import LeanInfer`, you can use the tactic `suggest_tactics` (see the image above and [this example](https://github.com/yangky11/lean4-example/blob/ab7bc199aedb66992689412ceb8b5a1e44af7ec5/Lean4Example.lean#L12)). 

For the first time, it may ask you to download the model by running `suggest_tactics!`. The model will be downloaded to `~/.cache/lean_infer/` by default, but the path can be overridden by the `LEAN_INFER_CACHE_DIR` environment variable.


## Questions and Bugs

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanInfer/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 


## Related Links

* [LeanDojo Website](https://leandojo.org/)
* [LeanDojo](https://github.com/lean-dojo/LeanDojo) 
* [ReProver](https://github.com/lean-dojo/ReProver)


## Acknowledgements

* [llmstep](https://github.com/wellecks/llmstep) is another tool providing tactic suggestions using LLMs. We use their frontend for displaying tactics but a different mechanism for running the model.
* We thank Scott Morrison for suggestions on simplifying LeanInfer's installation and Mac Malone for helping implement it. Both Scott and Mac work for the [Lean FRO](https://lean-fro.org/).
* We thank Jannis Limperg for integrating our LLM-generated tactics into aesop (https://github.com/leanprover-community/aesop/pull/70).



## Citation

```bibtex
@inproceedings{song2023towards,
  title={Towards Large Language Models as Copilots for Theorem Proving in {Lean}},
  author={Song, Peiyang and Yang, Kaiyu and Anandkumar, Anima},
  comment={The last two authors advised equally.},
  booktitle={The 3rd Workshop on Mathematical Reasoning and AI at NeurIPS'23},
  year={2023}
}
```


## Code Formatting

The C++ code in this project is formatted using [ClangFormat](https://clang.llvm.org/docs/ClangFormat.html). To format the code, run
```bash
clang-format --style Google -i cpp/*.cpp
```
