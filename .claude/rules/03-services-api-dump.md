# Regra 03 — Services e Roblox API Dump (`src/services/`)

## Fonte única

- Toda classe de Service (`Workspace`, `Players`, `ReplicatedStorage`, `DataStoreService`, `RunService`, `TweenService`, etc.) e toda propriedade/evento/método de qualquer Instance simulada é gerada ou verificada contra o `Full-API-Dump.json` oficial ([MaximumADHD/Roblox-Client-Tracker](https://github.com/MaximumADHD/Roblox-Client-Tracker)).
- Versão do dump usada é fixada e registrada (arquivo/commit de referência) — não "a mais recente sempre", para que o build seja reproduzível. Atualizar a versão do dump é uma decisão explícita, não automática a cada build.
- Propriedade marcada como `Deprecated` no dump é implementada só se algum projeto real ainda depender dela; sinalize no relatório em vez de implementar tudo cegamente.

## Geração vs. mão

- Preferir gerar o esqueleto de uma classe (nomes de propriedade, tipo, assinatura de método/evento) a partir do dump, com um script/módulo de geração — não copiar campo a campo na mão para as centenas de classes do Roblox.
- Comportamento (o que a propriedade/método realmente *faz* na simulação) é escrito à mão — o dump só dá a superfície (o "o quê"), nunca o "como".
- Service não coberto ainda (fora da leva atual) não é stub silencioso que finge funcionar — `Instance.new`/acesso a um Service não implementado retorna erro claro ("Service X ainda não simulado no LuauBench"), nunca `nil` silencioso ou tabela vazia.

## Prioridade de cobertura

Ordem sugerida ao priorizar qual Service simular primeiro (ajustável pelo `arquiteto`/`planejador` conforme o pedido do usuário):

1. `Workspace`, `Players`, `ReplicatedStorage`, `ServerStorage`, `ServerScriptService`, `StarterPlayer`/`StarterGui` — a árvore básica que todo projeto Rojo tem.
2. `RunService`, `TweenService` — scheduler/animação, muito usado em lógica pura.
3. `DataStoreService`, `HttpService`, `MessagingService` — data management, o caso de uso central citado pelo usuário (ProfileStore e afins).
4. Services físicos/render (`Lighting`, `SoundService`, `PhysicsService`) — cobertura mínima de API, comportamento simplificado e documentado (ver `.claude/rules/02-runtime-simulation.md`).

## Contrato com `runtime`

- `services` só usa a API pública que `runtime` expõe para criar/registrar Instance e Service — nunca acessa estrutura interna do `runtime` por fora dessa API.
- Toda classe nova registrada por `services` é discoverable por `runtime`/`cli` sem que eles precisem conhecer o nome da classe de antemão (registro central, não `if ClassName == "Workspace" then`).

## Testes

- Toda classe de Service simulada tem teste cobrindo: instanciação, ao menos uma propriedade lida/escrita, e ao menos um evento disparando na ordem certa — na mesma tarefa que implementa a classe.
