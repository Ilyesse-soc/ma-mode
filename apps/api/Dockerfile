FROM mirror.gcr.io/library/python:3.13-alpine@sha256:2d9aefe2fef018a7eb2c13064c89c71929800fd2e5dccdbf52ea5da5bb8d929a AS builder
WORKDIR /build
RUN apk add --no-cache build-base libffi-dev openssl-dev cargo jpeg-dev zlib-dev
COPY pyproject.toml requirements.txt ./
RUN python -m venv /opt/venv --without-pip \
    && pip --python /opt/venv install --no-cache-dir --require-hashes -r requirements.txt

FROM mirror.gcr.io/library/python:3.13-alpine@sha256:2d9aefe2fef018a7eb2c13064c89c71929800fd2e5dccdbf52ea5da5bb8d929a
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PATH="/opt/venv/bin:$PATH"
WORKDIR /srv/app
RUN apk upgrade --no-cache \
    && apk add --no-cache libffi libstdc++ libjpeg-turbo zlib \
    && addgroup -S app && adduser -S -G app appuser \
    && rm -rf /usr/local/lib/python3.13/site-packages/pip* \
              /usr/local/lib/python3.13/site-packages/setuptools* \
              /usr/local/lib/python3.13/site-packages/pkg_resources* \
              /usr/local/lib/python3.13/ensurepip /usr/local/bin/pip*
COPY --from=builder /opt/venv /opt/venv
COPY --chown=appuser:app app ./app
COPY --chown=appuser:app alembic ./alembic
COPY --chown=appuser:app alembic.ini ./
COPY --chown=appuser:app scripts ./scripts
USER appuser
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD python -c "import urllib.request;urllib.request.urlopen('http://127.0.0.1:8000/health')"
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --no-access-log"]
