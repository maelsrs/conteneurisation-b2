CREATE TABLE produits (
    id      SERIAL PRIMARY KEY,
    nom     TEXT NOT NULL,
    prix    NUMERIC(8,2) NOT NULL
);

INSERT INTO produits (nom, prix) VALUES
    ('1',   2),
    ('2',    4),
    ('3',    6),
    ('4',    8);
