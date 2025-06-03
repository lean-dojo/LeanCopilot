FROM python:3.10-slim

WORKDIR /

# Install dependencies
RUN pip install --no-cache-dir runpod transformers torch loguru numpy pydantic

# Copy your handler file
COPY runpod_handler.py /

# Start the container
CMD ["python3", "-u", "runpod_handler.py"]