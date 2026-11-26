FROM ollama/ollama:0.40.18

ENV OLLAMA_HOST=0.0.0.0:11434
ENV OLLAMA_KEEP_ALIVE=-1
ENV OLLAMA_MODEL=qwen2.5:3b

RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

COPY --chmod=0755 pull-model.sh entrypoint.sh /usr/local/bin/

RUN pull-model.sh

EXPOSE 11434

ENTRYPOINT ["entrypoint.sh"]
