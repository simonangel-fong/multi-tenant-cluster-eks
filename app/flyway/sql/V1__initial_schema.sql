CREATE TABLE polls (
    id          BIGSERIAL PRIMARY KEY,
    title       TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closes_at   TIMESTAMPTZ
);

CREATE TABLE options (
    id       BIGSERIAL PRIMARY KEY,
    poll_id  BIGINT NOT NULL REFERENCES polls(id) ON DELETE CASCADE,
    label    TEXT   NOT NULL
);

CREATE INDEX idx_options_poll_id ON options(poll_id);

CREATE TABLE votes (
    id          BIGSERIAL   PRIMARY KEY,
    poll_id     BIGINT      NOT NULL REFERENCES polls(id)   ON DELETE CASCADE,
    option_id   BIGINT      NOT NULL REFERENCES options(id) ON DELETE CASCADE,
    voter_id    TEXT        NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- one vote per voter per poll
    CONSTRAINT uq_votes_poll_voter UNIQUE (poll_id, voter_id)
);

CREATE INDEX idx_votes_poll_option ON votes(poll_id, option_id);
