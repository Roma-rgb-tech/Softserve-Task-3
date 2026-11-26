#!/bin/sh
set -eu

ollama serve &
server=$!

trap 'kill -TERM "$server" 2>/dev/null' TERM INT

until curl -fs http://127.0.0.1:11434 > /dev/null; do
  sleep 1
done

curl -fsS --max-time 600 http://127.0.0.1:11434/api/generate \
  -d "{\"model\":\"${OLLAMA_MODEL}\",\"keep_alive\":-1}" > /dev/null || true

wait "$server"
