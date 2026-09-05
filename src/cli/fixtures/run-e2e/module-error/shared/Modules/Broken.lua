-- Fixture end-to-end (task-cli-006): erro de execução dentro do CORPO do módulo -- indexar nil
-- dispara um erro do próprio motor Luau, sem nenhum error() explícito. A linha exata do erro é a
-- da última linha deste arquivo ("return nothing.explode") -- RunCommand.spec.luau lê este
-- arquivo para descobrir o número em vez de hardcodar, e assim nunca dessincroniza.
local nothing = nil
return nothing.explode
