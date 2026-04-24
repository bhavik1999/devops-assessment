import time
import random
import logging
import os
from fastapi import FastAPI, HTTPException, Request
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from starlette.responses import Response
import uvicorn

# --- Logging Setup ---
logging.basicConfig(
    level=logging.INFO,
    format='{"time": "%(asctime)s", "level": "%(levelname)s", "message": "%(message)s"}'
)
logger = logging.getLogger(__name__)

# --- Tracing Setup (OpenTelemetry → Tempo via OTLP) ---
TEMPO_ENDPOINT = os.getenv("TEMPO_ENDPOINT", "http://tempo.observability.svc.cluster.local:4317")
provider = TracerProvider()
exporter = OTLPSpanExporter(endpoint=TEMPO_ENDPOINT, insecure=True)
provider.add_span_processor(BatchSpanProcessor(exporter))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer(__name__)

# --- Metrics Setup (Prometheus) ---
REQUEST_COUNT = Counter(
    "api_request_total", "Total API Requests",
    ["method", "endpoint", "status"]
)
REQUEST_LATENCY = Histogram(
    "api_request_duration_seconds", "API Request Latency",
    ["endpoint"]
)
ERROR_COUNT = Counter(
    "api_error_total", "Total API Errors",
    ["endpoint"]
)

# --- FastAPI App ---
app = FastAPI(title="Sample DevOps API", version="1.0.0")
FastAPIInstrumentor.instrument_app(app)

@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.time()
    response = await call_next(request)
    duration = time.time() - start
    endpoint = request.url.path
    REQUEST_COUNT.labels(request.method, endpoint, response.status_code).inc()
    REQUEST_LATENCY.labels(endpoint).observe(duration)
    return response

@app.get("/")
def root():
    logger.info("Root endpoint hit")
    return {"status": "ok", "service": "sample-api", "version": "1.0.0"}

@app.get("/health")
def health():
    return {"status": "healthy"}

@app.get("/users")
def list_users():
    with tracer.start_as_current_span("list-users"):
        logger.info("Listing users")
        time.sleep(random.uniform(0.01, 0.1))
        users = [
            {"id": 1, "name": "Alice", "role": "admin"},
            {"id": 2, "name": "Bob", "role": "developer"},
            {"id": 3, "name": "Charlie", "role": "viewer"},
        ]
        return {"users": users, "total": len(users)}

@app.get("/users/{user_id}")
def get_user(user_id: int):
    with tracer.start_as_current_span("get-user") as span:
        span.set_attribute("user.id", user_id)
        logger.info(f"Fetching user {user_id}")
        time.sleep(random.uniform(0.01, 0.05))
        if user_id > 100:
            ERROR_COUNT.labels("/users/{user_id}").inc()
            logger.error(f"User {user_id} not found")
            raise HTTPException(status_code=404, detail=f"User {user_id} not found")
        return {"id": user_id, "name": f"User-{user_id}", "role": "developer"}

@app.post("/orders")
def create_order(request: Request):
    with tracer.start_as_current_span("create-order") as span:
        order_id = random.randint(1000, 9999)
        span.set_attribute("order.id", order_id)
        logger.info(f"Order created: {order_id}")
        time.sleep(random.uniform(0.05, 0.2))
        return {"order_id": order_id, "status": "created"}

@app.get("/orders/{order_id}/status")
def order_status(order_id: int):
    with tracer.start_as_current_span("order-status"):
        statuses = ["pending", "processing", "shipped", "delivered"]
        status = random.choice(statuses)
        logger.info(f"Order {order_id} status: {status}")
        return {"order_id": order_id, "status": status}

@app.get("/slow")
def slow_endpoint():
    with tracer.start_as_current_span("slow-operation"):
        delay = random.uniform(0.5, 2.0)
        logger.warning(f"Slow endpoint called, sleeping {delay:.2f}s")
        time.sleep(delay)
        return {"message": "This was slow", "delay_seconds": round(delay, 2)}

@app.get("/error")
def error_endpoint():
    ERROR_COUNT.labels("/error").inc()
    logger.error("Intentional error triggered")
    raise HTTPException(status_code=500, detail="Intentional server error for testing")

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
