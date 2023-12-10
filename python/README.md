Python Server for External Models
=================================

## Requirements

```bash
conda create --name lean-copilot python=3.10 python numpy
conda activate lean-copilot
pip install torch --index-url https://download.pytorch.org/whl/cu121  # Depending on whether you have CUDA and the CUDA version; see https://pytorch.org/.
pip install fastapi unicorn loguru transformers openai
```


## Running the Server

```bash
uvicorn server:app --port 23337
```