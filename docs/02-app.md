# App

- [App](#app)
  - [layout](#layout)
  - [delivery phase](#delivery-phase)
  - [REST API](#rest-api)
  - [Development](#development)
    - [Init](#init)
    - [Flyway](#flyway)

---

- **Goal:** a simple voting API backend.
- **Done when:** two `X-User-Id`s can cast one vote each on the same poll, the tally is correct, and a duplicate from the same voter is rejected with `409`.

---

## layout

```
app/
├─ voting/          # FastAPI package (config, db, models, schemas, routers)
├─ flyway/sql/      # Flyway migrations (V1__init.sql, V2__..., ...)
├─ tests/           # pytest
├─ pyproject.toml
└─ README.md
```

---

## delivery phase

| #   | phase         | description                                             |
| --- | ------------- | ------------------------------------------------------- |
| 01  | project init  | initialize FastAPI app; `GET /` → hello world           |
| 02  | health        | add `/healthz`                                          |
| 03  | db connection | add config + engine; prove `SELECT 1`                   |
| 04  | readiness     | add `/readyz`                                           |
| 05  | migration     | Flyway service in compose runs `V1__initial_schema.sql` |
| 06  | poll entity   | `POST /polls`, `GET /polls`, `GET /polls/{id}`          |
| 07  | vote + tally  | `POST /polls/{id}/vote`, `GET /polls/{id}/results`      |
| 08  | pytest        | real-Postgres test suite covering the endpoint table    |

---

## REST API

All JSON. `X-User-Id` header required only on `POST /vote` (missing/blank → `400`).

| Method | Path                  | Body                             | Response (success)                                                     | Errors                                                                           |
| ------ | --------------------- | -------------------------------- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| POST   | `/polls`              | `{title, options[], closes_at?}` | `201 {id, title, options:[{id,label}], created_at, closes_at}`         | `422` empty title / <2 options / duplicate labels / past `closes_at`             |
| GET    | `/polls`              | —                                | `200 [{id, title, created_at, closes_at}, ...]`                        | —                                                                                |
| GET    | `/polls/{id}`         | —                                | `200 {id, title, options:[{id,label}], created_at, closes_at}`         | `404`                                                                            |
| POST   | `/polls/{id}/vote`    | `{option_id}`                    | `201 {poll_id, option_id, voter_id, created_at}`                       | `400` no `X-User-Id`; `403` closed; `404` poll/option not found; `409` duplicate |
| GET    | `/polls/{id}/results` | —                                | `200 {poll_id, total_votes, tallies:[{option_id, label, votes}, ...]}` | `404`                                                                            |
| GET    | `/healthz`            | —                                | `200 {"status":"ok"}`                                                  | —                                                                                |
| GET    | `/readyz`             | —                                | `200 {"status":"ready"}` if `SELECT 1` works                           | `503` DB unreachable                                                             |

---

## Development

### Init

```sh
cd app
uv sync
uv run uvicorn voting.main:app --reload

curl http://127.0.0.1:8000/
# {"message":"hello world"}

curl http://127.0.0.1:8000/healthz
# {"status":"ok"}

curl http://127.0.0.1:8000/readyz
# {"status":"ready"}

docker compose stop postgres
curl -i http://127.0.0.1:8000/readyz
```
---

### Flyway

```sh
docker compose down -v
docker compose up -d
docker compose logs flyway
# voting-flyway  | Database: jdbc:postgresql://postgres:5432/voting (PostgreSQL 16.14)
# voting-flyway  | Schema history table "public"."flyway_schema_history" does not exist yet
# voting-flyway  | Successfully validated 1 migration (execution time 00:00.027s)
# voting-flyway  | Creating Schema History table "public"."flyway_schema_history" ...
# voting-flyway  | Current version of schema "public": << Empty Schema >>
# voting-flyway  | Migrating schema "public" to version "1 - initial schema"
# voting-flyway  | Successfully applied 1 migration to schema "public", now at version v1 (execution time 00:00.081s)
```