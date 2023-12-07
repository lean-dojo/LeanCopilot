Lean Copilot: LLMs as Copilots for Theorem Proving in Lean
==========================================================

Lean Copilot allows large language models (LLMs) to be used in Lean for proof automation, e.g., suggesting tactics/premises and searching for proofs. Users can use our built-in models from [LeanDojo](https://leandojo.org/) or bring their own models that run either locally (w/ or w/o GPUs) or on the cloud (such as GPT-4).



## Table of Contents

1. [Requirements](#requirements)  
2. [Using Lean Copilot in Your Project](#using-lean-copilot-in-your-project)
   1. [Adding Lean Copilot as a Dependency](#adding-lean-copilot-as-a-dependency)
   3. [Getting Started with Lean Copilot](#getting-started-with-lean-copilot)
      1. [Tactic Suggestion](#tactic-suggestion)
      2. [Proof Search](#proof-search)
      3. [Premise Selection](#premise-selection)
5. [Advanced Usage](#advanced-usage)
   1. [Model APIs](#model-apis)
   2. [Bring Your Own Model](#bring-your-own-model)
   3. [Tactic APIs](#tactic-apis)
7. [Building Lean Copilot](#building-lean-copilot)
8. [Questions and Bugs](#questions-and-bugs)
9. [Acknowledgements](#acknowledgements)
10. [Citation](#citation)


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


### Getting Started with Lean Copilot

#### Tactic Suggestion

After `import LeanCopilot`, you can use the tactic `suggest_tactics` to generate tactic suggestions. You can click on any of the suggested tactics to use it in the proof.

<img width="977" alt="suggest_tactics" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/e6ca8280-1b8d-4431-9f2b-8ec3bc4d6706">

You can provide a prefix to constrain the generated tactics. The example below only generates tactics starting with `simp`.

<img width="915" alt="suggest_tactics_simp" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/e55a21d4-8191-4c18-8902-7590d5f17053">


#### Proof Search

You can combine LLM-generated tactics with [aesop](https://github.com/leanprover-community/aesop) to search for multi-tactic proofs, by simply adding `#configure_llm_aesop` before using `aesop`, `aesop?`, or `search_proof` (just an alias of `aesop?`). When a proof is found, you can click on it to insert it into the editor. Note that the theorem below cannot be proved with the original aesop (without `#configure_llm_aesop`).

<img width="824" alt="search_proof" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/0748b9b1-8eb0-4437-bcbf-12e4ea939943">



#### Premise Selection

At any point in the proof, you can use the `select_premises` tactic to retrieve a list of potentially useful premises. Currently, we use the retriever in [LeanDojo](https://leandojo.org/) to select premises from a fixed snapshot of Lean and [mathlib4](https://github.com/leanprover-community/mathlib4/tree/3ce43c18f614b76e161f911b75a3e1ef641620ff), so it cannot select new lemmas in your project. 

![select_premises](https://github.com/lean-dojo/LeanCopilot/assets/5431913/1ab1cc9b-39ac-4f40-b2c9-40d57e235d3e)



#### Running LLMs

You can also run the inference of any LLMs in Lean, which can be used to build customized proof automation or other LLM-based applications (not limited to theorem proving). It's possible to run arbitrary models either locally or remotely (see [Bring Your Own Model](#bring-your-own-model)). 

<img width="1123" alt="run_llms" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/a4e5b84b-a797-4216-a416-2958448aeb07">



## Advanced Usage

### Model APIs

### Bring Your Own Model

### Tactic APIs


Coming soon.


## Building Lean Copilot

You don't need to build Lean Copilot directly if you use it only in downstream packages. However, you may need to do that in some cases, e.g., if you want to contribute to Lean Copilot. You can run `lake build`, but make sure you have installed these dependencies:
* CMake >= 3.7
* A C++17 compatible compiler, e.g., recent versions of GCC or Clang


## Questions and Bugs

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanCopilot/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 


## Acknowledgements

* [llmstep](https://github.com/wellecks/llmstep) is another tool providing tactic suggestions using LLMs. We use their frontend for displaying tactics but a different mechanism for running the model.
* We thank Scott Morrison for suggestions on simplifying Lean Copilot's installation and Mac Malone for helping implement it. Both Scott and Mac work for the [Lean FRO](https://lean-fro.org/).
* We thank Jannis Limperg for integrating our LLM-generated tactics into Aesop (https://github.com/leanprover-community/aesop/pull/70).



## Citation

```BibTeX
@inproceedings{song2023towards,
  title={Towards Large Language Models as Copilots for Theorem Proving in {Lean}},
  author={Song, Peiyang and Yang, Kaiyu and Anandkumar, Anima},
  comment={The last two authors advised equally.},
  booktitle={The 3rd Workshop on Mathematical Reasoning and AI at NeurIPS'23},
  year={2023}
}
```
