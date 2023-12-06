Lean Copilot: LLMs as Copilots for Theorem Proving in Lean
==========================================================

Lean Copilot allows large language models (LLMs) to be used in Lean for proof automation, e.g., suggesting tactics/premises and searching for proofs. Users can use our built-in models from [LeanDojo](https://leandojo.org/) or bring their own models that run either locally (w/ or w/o GPUs) or on the cloud (such as GPT-4).


## Requirements

* Supported platforms: Linux, macOS and Windows WSL
* [Git LFS](https://git-lfs.com/)
* Optional (recommended if you have a [CUDA-enabled GPU](https://developer.nvidia.com/cuda-gpus)): CUDA and [cuDNN](https://developer.nvidia.com/cudnn)


## Using Lean Copilot in Your Project

:warning: Your project must use a Lean version of at least `lean4:v4.3.0-rc2`.

### Adding Lean Copilot as a Dependency

1. Add the package configuration option `moreLinkArgs := #["-L./.lake/packages/LeanCopilot/.lake/build/lib", "-lctranslate2"]` to lakefile.lean. Also add the following line:
```lean
require LeanCopilot from git "https://github.com/lean-dojo/LeanCopilot.git" @ "v0.1.0"
```
3. Run `lake update LeanCopilot`
4. Run `lake exe LeanCopilot/download` to download the built-in models from Hugging Face to `~/.cache/lean_copilot/`
5. Run `lake build`

[Here](https://github.com/yangky11/lean4-example/blob/LeanCopilot-demo) is an example of a Lean package depending on Lean Copilot. If you have problems building the project, our [Dockerfile](./Dockerfile), [build.sh](scripts/build.sh) or [build_example.sh](scripts/build_example.sh) may be helpful.


### Using LeanCopilot

#### Tactic Suggestions

After `import LeanCopilot`, you can use the tactic `suggest_tactics` to generate tactic suggestions. You can click on any of the suggested tactics to use it in the proof.
<img width="977" alt="suggest_tactics" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/e6ca8280-1b8d-4431-9f2b-8ec3bc4d6706">

You can provide a prefix to constrain the generated tactics. The example below only generates tactics starting with `simp`.

<img width="915" alt="suggest_tactics_simp" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/e55a21d4-8191-4c18-8902-7590d5f17053">

#### Proof Search

You can combine the LLM-generated tactic suggestions with [aesop](https://github.com/leanprover-community/aesop) to search for complete proofs. To do this, simply add `#configure_llm_aesop` before using aesop (see [this example](LeanCopilotTests/Aesop.lean)). 


#### Premise Selection

Coming soon.*



#### Running LLMs



## Building LeanCopilot

You don't need to build LeanCopilot directly if you use it in a downstream package. Nevertheless, if you really need to build LeanCopilot, it can be done by `lake build`. However, make sure you have installed these dependencies:
* CMake >= 3.7
* A C++17 compatible compiler, e.g., recent versions of GCC or Clang


## Questions and Bugs

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanCopilot/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 


## Related Links

* [LeanDojo Website](https://leandojo.org/)
* [LeanDojo](https://github.com/lean-dojo/LeanDojo) 
* [ReProver](https://github.com/lean-dojo/ReProver)


## Acknowledgements

* [llmstep](https://github.com/wellecks/llmstep) is another tool providing tactic suggestions using LLMs. We use their frontend for displaying tactics but a different mechanism for running the model.
* We thank Scott Morrison for suggestions on simplifying LeanCopilot's installation and Mac Malone for helping implement it. Both Scott and Mac work for the [Lean FRO](https://lean-fro.org/).
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
