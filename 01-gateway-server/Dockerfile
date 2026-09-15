FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt -i https://pypi.tuna.tsinghua.edu.cn/simple

COPY gateway_server.py .
COPY snapshot_loader.py .
COPY router.py .
COPY config/ ./config/

EXPOSE 8000

CMD ["python", "gateway_server.py"]
