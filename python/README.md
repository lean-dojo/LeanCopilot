Python Server for External Models
=================================

This folder contains code that enables running some of the leading general-purpose or math-specific models. It is also fairly easy to adapt the existing code and run other external models you would like to bring.

## Requirements

The setup steps are pretty simple. The script below is sufficient to run all external models already supported in this folder. If you only want to run a subset of them, you may not need all packages in the last step of pip installation.

```bash
conda create --name lean-copilot python=3.10 python numpy
conda activate lean-copilot
pip install torch --index-url https://download.pytorch.org/whl/cu121  # Depending on whether you have CUDA and, if so, your CUDA version; see https://pytorch.org/.
pip install fastapi uvicorn loguru transformers openai anthropic google.generativeai vllm
```

## Running the Server

```bash
uvicorn server:app --port 23337
```

After the server is up running, you can go to `LeanCopilotTests/ModelAPIs.lean` to try your external models out!

## Contributions

We welcome contributions. If you think it would beneficial to add some other external models, or if you would like to make other contributions regarding the external model support in Lean Copilot, please feel free to open a PR. The main entry point is this `python` folder as well as the `ModelAPIs.lean` file under `LeanCopilotTests`.

We use [`black`](https://pypi.org/project/black/) to format code in this folder.
