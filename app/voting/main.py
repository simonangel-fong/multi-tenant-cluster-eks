from fastapi import FastAPI

app = FastAPI(title="Voting API")


@app.get("/")
def root():
    return {"message": "hello world"}


@app.get("/healthz")
def healthz():
    return {"status": "ok"}
