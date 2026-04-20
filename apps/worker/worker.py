import os
import time
import pika

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq.default.svc.cluster.local")
RABBITMQ_QUEUE = os.getenv("RABBITMQ_QUEUE", "jobs")

credentials = pika.PlainCredentials(
    os.getenv("RABBITMQ_USERNAME", "guest"),
    os.getenv("RABBITMQ_PASSWORD", "guest")
)


def handle_message(ch, method, properties, body):
    payload = body.decode("utf-8")
    print(f"processing {payload}")
    time.sleep(2)
    ch.basic_ack(delivery_tag=method.delivery_tag)


def main():
    while True:
        try:
            params = pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credentials)
            connection = pika.BlockingConnection(params)
            channel = connection.channel()
            channel.queue_declare(queue=RABBITMQ_QUEUE, durable=True)
            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(queue=RABBITMQ_QUEUE, on_message_callback=handle_message)
            print("waiting for messages")
            channel.start_consuming()
        except Exception as exc:
            print(f"consumer error: {exc}")
            time.sleep(5)


if __name__ == "__main__":
    main()
