-- Fixture end-to-end (task-cli-006): Script com Enabled = false (via Muted.meta.json, ao lado) --
-- carregado mas nunca executado. Se esta linha aparecer no stdout de um teste, o acceptance de
-- "Enabled = false não executa" falhou.
print("THIS SHOULD NEVER RUN: Muted (Enabled = false) executed")
