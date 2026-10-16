-- +goose Up
CREATE TABLE channels (
    id uuid PRIMARY KEY,
    code text NOT NULL UNIQUE,
    name text NOT NULL CHECK (char_length(name) > 0),
    initially_visible boolean NOT NULL DEFAULT false,
    display_order integer NOT NULL UNIQUE CHECK (display_order > 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO channels (id, code, name, initially_visible, display_order)
VALUES
    ('5f6f4f88-8f64-4bb2-9d34-000000000001', 'vent', '吐槽', true, 10),
    ('5f6f4f88-8f64-4bb2-9d34-000000000002', 'warning', '避雷', true, 20),
    ('5f6f4f88-8f64-4bb2-9d34-000000000003', 'recommendation', '安利', true, 30),
    ('5f6f4f88-8f64-4bb2-9d34-000000000004', 'buddy', '搭子', true, 40),
    ('5f6f4f88-8f64-4bb2-9d34-000000000005', 'emotion', '情感', true, 50),
    ('5f6f4f88-8f64-4bb2-9d34-000000000006', 'mutual_help', '互助', false, 60),
    ('5f6f4f88-8f64-4bb2-9d34-000000000007', 'technology', '科技', false, 70)
ON CONFLICT (code) DO NOTHING;

-- +goose Down
DROP TABLE channels;
