-- Fixture end-to-end (task-cli-006): requer um módulo com erro de execução no CORPO, sem pcall --
-- usada para testar a reatribuição de linha/nome do OutputFormatter (o erro deve ser renderizado
-- citando o MÓDULO que de fato errou, não este Script).
require(game.ReplicatedStorage.Modules.Broken)
print("THIS SHOULD NEVER RUN: line after the failing require")
