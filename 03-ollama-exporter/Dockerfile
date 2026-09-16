FROM python:3.11-slim

ARG GIT_SHA=unknown
ENV GIT_SHA=${GIT_SHA}

WORKDIR /app

COPY exporter.py /app/exporter.py

EXPOSE 9101

CMD ["python", "/app/exporter.py"]
