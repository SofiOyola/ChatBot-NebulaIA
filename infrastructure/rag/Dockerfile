FROM python:3.11.14-slim
WORKDIR /app
COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir .
USER 65532:65532
EXPOSE 8091
CMD ["sh", "-c", "exec gunicorn --bind \"${RAG_HTTP_HOST:-127.0.0.1}:${RAG_HTTP_PORT:-8091}\" --workers 2 --timeout 45 'nebula_rag.server:create_application()'"]
