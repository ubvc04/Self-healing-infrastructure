import os
import time
from flask import Flask, jsonify, request
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import pika
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

app = Flask(__name__)

REQUEST_COUNT = Counter("api_requests_total", "Total API requests", ["method", "endpoint", "status"])
REQUEST_LATENCY = Histogram("api_request_latency_seconds", "API request latency", ["endpoint"])

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq.default.svc.cluster.local")
RABBITMQ_QUEUE = os.getenv("RABBITMQ_QUEUE", "jobs")

resource = Resource.create({"service.name": "platform-api"})
provider = TracerProvider(resource=resource)
provider.add_span_processor(
    BatchSpanProcessor(
        OTLPSpanExporter(endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector.observability.svc.cluster.local:4317"), insecure=True)
    )
)
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)


def publish_message(payload: str) -> None:
    credentials = pika.PlainCredentials(
        os.getenv("RABBITMQ_USERNAME", "guest"),
        os.getenv("RABBITMQ_PASSWORD", "guest")
    )
    parameters = pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credentials)
    connection = pika.BlockingConnection(parameters)
    channel = connection.channel()
    channel.queue_declare(queue=RABBITMQ_QUEUE, durable=True)
    channel.basic_publish(
        exchange="",
        routing_key=RABBITMQ_QUEUE,
        body=payload.encode("utf-8"),
        properties=pika.BasicProperties(delivery_mode=2),
    )
    connection.close()


@app.route("/healthz", methods=["GET"])
def healthz():
    REQUEST_COUNT.labels("GET", "/healthz", "200").inc()
    return jsonify({"status": "ok"}), 200


@app.route("/enqueue", methods=["POST"])
def enqueue():
    with tracer.start_as_current_span("enqueue_handler"):
        start = time.time()
        body = request.get_json(silent=True) or {}
        payload = body.get("payload", f"job-{int(time.time())}")

        publish_message(payload)
        latency = time.time() - start
        REQUEST_LATENCY.labels("/enqueue").observe(latency)
        REQUEST_COUNT.labels("POST", "/enqueue", "202").inc()
        return jsonify({"accepted": True, "payload": payload}), 202


@app.route("/metrics", methods=["GET"])
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
