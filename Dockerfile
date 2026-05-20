FROM python:3.11-slim
WORKDIR /app
COPY server.py .
EXPOSE 8765
CMD ["python3", "server.py"]
