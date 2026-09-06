-- Fixture end-to-end (task-cli-026, achado MÉDIO da revisão): Script sob ServerScriptService que
-- faz UMA requisição HTTP real (HttpService:GetAsync) contra um servidor HTTP LOCAL que o PRÓPRIO
-- teste sobe via `net.serve` (RunCommand.spec.luau, "PARTE 2") -- nunca uma dependência externa.
-- Existe para fechar a lacuna encontrada na revisão: nenhum teste automatizado do território `cli`
-- exercitava o contrato `OnHttpRequest`/`Messages.HttpRequestAuditLine` de ponta a ponta contra
-- uma requisição HTTP de verdade (só havia teste unitário de cada lado, nunca os dois fiados
-- juntos por um processo real).
--
-- Porta FIXA (47210), combinada com a constante homônima em RunCommand.spec.luau -- mesmo padrão
-- já usado por HttpService.spec.luau (TEST_PORT = 47182) para o canário `net.serve` local: como o
-- fixture é um arquivo estático em disco e o sandbox do script não expõe variável de ambiente
-- nenhuma (regra 00: script do usuário é código arbitrário, superfície é só a que o Roblox real
-- exporia), o número da porta precisa ser combinado entre os dois lados em vez de passado em
-- tempo de execução.
--
-- `--allow-http-local` (exigida pelo teste que roda este fixture) é necessária porque "127.0.0.1"
-- é destino loopback -- bloqueado por padrão mesmo com "--allow-http" sozinho (endurecimento
-- deliberado de task-services-026, ver HttpService.luau).
local HttpService = game:GetService("HttpService")

local body = HttpService:GetAsync("http://127.0.0.1:47210/")
print("got body: " .. body)
