FROM prom/prometheus:v3.16.0

COPY prometheus.yml /etc/prometheus/prometheus.yml

RUN promtool check config /etc/prometheus/prometheus.yml

CMD [ \
  "--config.file=/etc/prometheus/prometheus.yml", \
  "--storage.tsdb.path=/prometheus", \
  "--storage.tsdb.retention.time=15d", \
  "--web.enable-remote-write-receiver", \
  "--web.enable-otlp-receiver" \
]

EXPOSE 9090
