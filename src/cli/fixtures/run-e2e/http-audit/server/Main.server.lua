-- Fixture end-to-end (task-cli-026, achado MÉDIO da revisão): Script sob ServerScriptService que
-- faz UMA requisição HTTP real (HttpService:GetAsync) contra um servidor HTTP LOCAL que o PRÓPRIO
-- teste sobe via `net.serve` (RunCommand.spec.luau, "PARTE 2") -- nunca uma dependência externa.
-- Existe para fechar a lacuna encontrada na revisão: nenhum teste automatizado do território `cli`
-- exercitava o contrato `OnHttpRequest`/`Messages.HttpRequestAuditLine` de ponta a ponta contra
-- uma requisição HTTP de verdade (só havia teste unitário de cada lado, nunca os dois fiados
-- juntos por um processo real).
--
-- ATUALIZAÇÃO (task-cli-034): a porta 47210 abaixo é só EXEMPLO/referência de formato -- o teste
-- real (RunCommand.spec.luau, "PARTE 2") não executa mais este arquivo estático diretamente. Ele
-- gera uma CÓPIA MUTÁVEL deste script em tempo de execução (`freshHttpAuditProject`) com uma porta
-- ESCOLHIDA DINAMICAMENTE a cada execução do spec, porque a porta fixa original colidia sempre que
-- duas instâncias do spec rodavam concorrentemente (Windows: "Only one usage of each socket
-- address... is normally permitted. (os error 10048)", reproduzido ao vivo nesta tarefa -- ver
-- comentário no topo de RunCommand.spec.luau, "CAUSA RAIZ DE INSTABILIDADE"). O sandbox do script
-- continua sem receber variável de ambiente nenhuma (regra 00) -- a porta é embutida diretamente
-- no texto do script gerado, não passada por env.
--
-- `--allow-http-local` (exigida pelo teste que roda este fixture) é necessária porque "127.0.0.1"
-- é destino loopback -- bloqueado por padrão mesmo com "--allow-http" sozinho (endurecimento
-- deliberado de task-services-026, ver HttpService.luau).
local HttpService = game:GetService("HttpService")

local body = HttpService:GetAsync("http://127.0.0.1:47210/")
print("got body: " .. body)
