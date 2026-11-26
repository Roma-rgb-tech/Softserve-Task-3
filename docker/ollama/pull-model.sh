#!/bin/sh
set -eu

ollama serve > /dev/null 2>&1 &

until ollama list > /dev/null 2>&1; do
  sleep 1
done

ollama pull "$OLLAMA_MODEL"
