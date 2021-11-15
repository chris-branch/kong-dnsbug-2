FROM kong:2.5.1-alpine

COPY ./test-config.yaml /test-config.yaml

ENV KONG_DECLARATIVE_CONFIG=/test-config.yaml
ENV KONG_DATABASE=off
ENV KONG_ADMIN_LISTEN=0.0.0.0:8001

USER root
RUN apk update && apk add bind-tools

EXPOSE 8000 8001
