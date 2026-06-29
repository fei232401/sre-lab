FROM python:3.11-slim
WORKDIR /app

# 安装依赖
RUN pip install --no-cache-dir \
    fastapi>=0.100.0 \
    uvicorn>=0.22.0 \
    aiohttp>=3.8.0 \
    pyyaml>=6.0 \
    pyjwt>=2.8.0 \
    prometheus-client>=0.19.0

# 复制代码
COPY 01-scheduler-core/ ./01-scheduler-core/
COPY 02-unified-api/ ./02-unified-api/
COPY config/ ./config/

EXPOSE 9000 9100

CMD ["python", "02-unified-api/unified_gateway.py"]
