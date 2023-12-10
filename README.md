Lean Copilot: LLMs as Copilots for Theorem Proving in Lean
==========================================================

Lean Copilot allows large language models (LLMs) to be used in Lean for proof automation, e.g., suggesting tactics/premises and searching for proofs. You can use our built-in models from [LeanDojo](https://leandojo.org/) or bring your own models that run either locally (w/ or w/o GPUs) or on the cloud.



## Table of Contents

1. [Requirements](#requirements)  
2. [Using Lean Copilot in Your Project](#using-lean-copilot-in-your-project)
   1. [Adding Lean Copilot as a Dependency](#adding-lean-copilot-as-a-dependency)
   3. [Getting Started with Lean Copilot](#getting-started-with-lean-copilot)
      1. [Tactic Suggestion](#tactic-suggestion)
      2. [Proof Search](#proof-search)
      3. [Premise Selection](#premise-selection)
5. [Advanced Usage](#advanced-usage)
   1. [Tactic APIs](#tactic-apis)
   2. [Model APIs](#model-apis)
   3. [Bring Your Own Model](#bring-your-own-model)
8. [Caveats](#caveats)
9. [Getting in Touch](#getting-in-touch)
10. [Acknowledgements](#acknowledgements)
11. [Citation](#citation)


## Requirements

* Supported platforms: Linux, macOS and Windows WSL
* [Git LFS](https://git-lfs.com/)
* Optional (recommended if you have a [CUDA-enabled GPU](https://developer.nvidia.com/cuda-gpus)): CUDA and [cuDNN](https://developer.nvidia.com/cudnn)
* Required for building Lean Copilot itself (rather than a downstream package): CMake >= 3.7 and a C++17 compatible compiler

## Using Lean Copilot in Your Project

:warning: Your project must use a Lean version of at least `lean4:v4.3.0-rc2`.

### Adding Lean Copilot as a Dependency

1. Add the package configuration option `moreLinkArgs := #["-L./.lake/packages/LeanCopilot/.lake/build/lib", "-lctranslate2"]` to lakefile.lean. Also add the following line:
```lean
require LeanCopilot from git "https://github.com/lean-dojo/LeanCopilot.git" @ "v1.0.0"
```
3. Run `lake update LeanCopilot`
4. Run `lake exe LeanCopilot/download` to download the built-in models from Hugging Face to `~/.cache/lean_copilot/`
5. Run `lake build`

[Here](https://github.com/yangky11/lean4-example/blob/LeanCopilot-demo) is an example of a Lean package depending on Lean Copilot. If you have problems building the project, our [Dockerfile](./Dockerfile), [build.sh](scripts/build.sh) or [build_example.sh](scripts/build_example.sh) may be helpful.


### Getting Started with Lean Copilot


#### Tactic Suggestion

After `import LeanCopilot`, you can use the tactic `suggest_tactics` to generate tactic suggestions. You can click on any of the suggested tactics to use it in the proof.

<img width="977" alt="suggest_tactics" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/e6ca8280-1b8d-4431-9f2b-8ec3bc4d6706">

You can provide a prefix (e.g., `simp`) to constrain the generated tactics:

<img width="915" alt="suggest_tactics_simp" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/e55a21d4-8191-4c18-8902-7590d5f17053">


#### Proof Search

The tactic `search_proof` combines LLM-generated tactics with [aesop](https://github.com/leanprover-community/aesop) to search for multi-tactic proofs. When a proof is found, you can click on it to insert it into the editor. 

<img width="824" alt="search_proof" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/0748b9b1-8eb0-4437-bcbf-12e4ea939943">



#### Premise Selection

The `select_premises` tactic retrieves a list of potentially useful premises. Currently, it uses the retriever in [LeanDojo](https://leandojo.org/) to select premises from a fixed snapshot of Lean and [mathlib4](https://github.com/leanprover-community/mathlib4/tree/3ce43c18f614b76e161f911b75a3e1ef641620ff).

![select_premises](https://github.com/lean-dojo/LeanCopilot/assets/5431913/1ab1cc9b-39ac-4f40-b2c9-40d57e235d3e)



#### Running LLMs

You can also run the inference of any LLMs in Lean, which can be used to build customized proof automation or other LLM-based applications (not limited to theorem proving). It's possible to run arbitrary models either locally or remotely (see [Bring Your Own Model](#bring-your-own-model)). 

<img width="1123" alt="run_llms" src="https://github.com/lean-dojo/LeanCopilot/assets/5431913/a4e5b84b-a797-4216-a416-2958448aeb07">



## Advanced Usage

**This section is only for advanced users who want to change the default behavior of `suggest_tactics`, `search_proof`, or `select_premises`, e.g., to use different models or hyperparameters.**

### Tactic APIs

* Examples in [TacticSuggestion.lean](LeanCopilotTests/TacticSuggestion.lean) showcase how to configure `suggest_tactics`, e.g., to use different models or generate different numbers of tactics.
* Examples in [ProofSearch.lean](LeanCopilotTests/ProofSearch.lean) showcase how to configure the proof search using options provided by [aesop](https://github.com/leanprover-community/aesop).
* Examples in [PremiseSelection.lean](LeanCopilotTests/PremiseSelection.lean) showcase how to set the number of retrieved premises for `select_premises`.




### Model APIs

**Examples in [ModelAPIs.lean](LeanCopilotTests/ModelAPIs.lean) showcase how to run the inference of different models and configure their parameters (temperature, beam size, etc.).** 

Lean Copilot supports two kinds of models: generator and encoder. Generators must implement the `TextToText` interface:
```lean
class TextToText (τ : Type) where
  generate (model : τ) (input : String) (targetPrefix : String) : IO $ Array (String × Float)
```
* `input` is the input string
* `targetPrefix` is used to constrain the generator's output. `""` means no constraint.
* `generate` should return an array of `String × Float`. Each `String` is an output from the model, and `Float` is the corresponding score.

We provide three types of Generators:
* [`NativeGenerator`](LeanCopilot/Models/Native.lean) runs locally powered by [CTranslate2](https://github.com/OpenNMT/CTranslate2) and is linked to Lean using Foreign Function Interface (FFI).
* [`ExternalGenerator`](LeanCopilot/Models/External.lean) is hosted either locally or remotely. See [Bring Your Own Model](#bring-your-own-model) for details.
* [`GenericGenerator`](LeanCopilot/Models/Generic.lean) can be anything that implements the `generate` function in the `TextToText` typeclass.


Encoders must implement `TextToVec`:
```lean
class TextToVec (τ : Type) where
  encode : τ → String → IO FloatArray
```
* `input` is the input string
* `encode` should return a vector embedding produced by the model.

Similar to generators, we have `NativeEncoder`, `ExternalEncoder`, and `GenericEncoder`.


### Bring Your Own Model

In principle, it is possible to run any model using Lean Copilot through `ExternalGenerator` or `ExternalEncoder` (examples in [ModelAPIs.lean](LeanCopilotTests/ModelAPIs.lean)). To use a model, you need to wrap it properly to expose the APIs in [external_model_api.yaml](./external_model_api.yaml). As an example, we provide a [Python API server](./python) and use it to run a few models, including [llmstep-mathlib4-pythia2.8b](https://huggingface.co/wellecks/llmstep-mathlib4-pythia2.8b).



## Caveats

* Lean may occasionally crash when restarting or editing a file. Restarting the file again should fix the problem.
* `select_premises` always retrieves the original form of a premise. For example, `Nat.add_left_comm` is a result of the theorem below. In this case, `select_premises` retrieves `Nat.mul_left_comm` instead of `Nat.add_left_comm`.
```lean
@[to_additive]
theorem mul_left_comm : ∀ a b c : G, a * (b * c) = b * (a * c)
```
* In some cases, `search_proof` produces an erroneous proof with error messages like `fail to show termination for ...`. A temporary workaround is changing the theorem's name before applying `search_proof`. You can change it back after `search_proof` completes.



## Getting in Touch

* For general questions and discussions, please use [GitHub Discussions](https://github.com/lean-dojo/LeanCopilot/discussions).  
* To report a potential bug, please open an issue. In the issue, please include your OS information and the exact steps to reproduce the error. The more details you provide, the better we will be able to help you. 
* Feature requests and other suggestions are extremely welcome. Please feel free to start a discussion!


## Acknowledgements

* We use the frontend of [llmstep](https://github.com/wellecks/llmstep) for displaying tactics.
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
