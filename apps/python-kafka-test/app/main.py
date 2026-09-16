from confluent_kafka import Producer, Consumer
from time import sleep
import itertools
import os

SECURITY_PROTOCOL = "SASL_PLAINTEXT"
SASL_MECHANISM = "SCRAM-SHA-512"
PRODUCE_INTERVAL_SECONDS = 3

KAFKA_TOPIC = os.environ.get("KAFKA_TOPIC")

conf_base = {
    'bootstrap.servers': os.environ.get('KAFKA_HOST'),
    'sasl.mechanisms': SASL_MECHANISM,
    'security.protocol': SECURITY_PROTOCOL,
    'sasl.username': os.environ.get('KAFKA_USERNAME'),
    'sasl.password': os.environ.get('KAFKA_PASSWORD'),
}


def acked(err, msg):
    if err is not None:
        print(f"Failed to deliver message: {err.str()}")
    else:
        print(f"Produced to: {msg.topic()} [{msg.partition()}] @ {msg.offset()}")


producer = Producer(conf_base)

conf_consumer = {
    **conf_base,
    'group.id': "my-group",
    'auto.offset.reset': "earliest",
}

consumer = Consumer(conf_consumer)
consumer.subscribe([KAFKA_TOPIC])

try:
    for i in itertools.count(1):
        producer.produce(KAFKA_TOPIC, key="test", value=f'hello python {i}', callback=acked)
        producer.poll(0)

        msg = consumer.poll(1.0)
        if msg is not None:
            if msg.error():
                print(f"Error: {msg.error()}")
            else:
                print(f"{msg.key()}: {msg.value()}")

        sleep(PRODUCE_INTERVAL_SECONDS)
except KeyboardInterrupt:
    pass
finally:
    producer.flush(10)
    consumer.close()
