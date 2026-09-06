# Revisão — task-services-023 (CollisionGroups + WorldRoot + PhysicsService)

Revisor: `revisor-services`. Read-only, nenhum arquivo de `src/services/` foi editado nesta revisão
(script de verificação temporário `src/services/__revisor_verify_023.luau` foi criado, executado e
apagado antes de terminar — `git status` confirmado idêntico ao estado inicial).

## Veredito

**APROVADO**

## O que foi verificado por reprodução própria (não aceito por self-report)

1. **Suíte completa `src/services/` + `tools/`**: rodei `lune run` em todos os 30 arquivos `.spec.luau`
   (29 em `src/services/**`, 1 em `tools/`) individualmente — 0 falhas. Números exatos confirmados
   rodando cada spec: `CollisionGroups.spec.luau` 23/23, `WorldRoot.spec.luau` 12/12,
   `PhysicsService.spec.luau` 15/15.
2. Script de verificação independente (não herdado do coder, escrito do zero por mim, temporário,
   removido ao final) confirmou via `lune run`, batendo com o board:
   - Delegação cruzada nos dois sentidos: `PhysicsService:RegisterCollisionGroup("X")` →
     `workspace:IsCollisionGroupRegistered("X") == true`, e o inverso via `workspace:Register`.
   - `GetMaxCollisionGroups() == 32`; `"Default"` pré-registrado; dois grupos novos colidem por
     padrão (`CollisionGroupsAreCollidable`).
   - Registrar o 33º grupo (acima do limite de 32, já contando "Default") erra.
   - `Register("Default")` erra (nome reservado — distinto do caso idempotente); `Register("Dup")`
     chamado duas vezes com o mesmo nome NÃO erra (idempotente, conforme decisão documentada).
   - Os 7 métodos `Deprecated` de `PhysicsService` (`CreateCollisionGroup`, `GetCollisionGroupId`,
     `GetCollisionGroupName`, `GetCollisionGroups`, `RemoveCollisionGroup`,
     `SetPartCollisionGroup`, `CollisionGroupContainsPart`) erram com o stub `[LuauBench] ... not
     simulated by LuauBench yet` — não crasham o processo, não fingem comportamento.
   - Duas instâncias de `Workspace` de dois `Services.Bootstrap`/`DataModel` distintos têm
     registros de colisão isolados — estado por instância confirmado na prática, não só por
     inspeção de código (já era testado também em `WorldRoot.spec.luau`).
3. **Mecanismo `Initialize` só na classe exata**: confirmado lendo `src/runtime/ClassRegistry.luau`
   diretamente (`NewEngineInstance`, linhas ~326-367) — `descriptor = registry[className]` é
   resolvido para o `className` EXATO passado (`"Workspace"` na prática), e só
   `descriptor.Initialize` (dessa classe exata) é chamado; `resolveClassChain`/achatamento de
   `Methods`/`Schema` percorre a cadeia inteira, mas `Initialize` não. Isso confirma a alegação do
   coder — `WorldRoot.Initialize` de fato nunca rodaria para uma instância de `Workspace`, e o
   desenho get-or-create preguiçoso via `InstanceState` é a solução correta, não um workaround.
4. **Regeneração determinística**: rodei `lune run tools/generate-services` duas vezes, comparando
   bytes de `generated/Index.luau`, `generated/Manifest.luau`,
   `generated/classes/PhysicsService.luau` e `tools/coverage.luau` antes/depois — idênticos.
   `PhysicsService` confirmada presente em `tools/coverage.luau` com comentário explicando por que
   `WorldRoot` não precisa de entrada própria (fecho de superclasses de `Workspace`).
5. **`--!strict`/zero `any`**: confirmado nos 6 arquivos novos (`CollisionGroups.luau`+`.spec`,
   `WorldRoot.luau`+`.spec`, `PhysicsService.luau`+`.spec`) — todos com `--!strict` na primeira
   linha, nenhuma ocorrência de `any` como tipo.
6. **Território limpo**: `git diff --stat` isolado por arquivo confirma que os únicos arquivos
   tocados que pertencem à superfície de 023 são exatamente os listados na tarefa. `Context.luau`/
   `Types.luau`/`HttpService.luau`/os `src/cli/*` modificados no working tree pertencem a
   task-services-026/task-cli-026 (em paralelo, territórios diferentes — `Context.IsHttpAllowed`/
   `BootstrapOptions.AllowHttp` não têm nenhuma relação com colisão/`WorldRoot`). A mudança de
   `behavior/Index.luau`/`Index.spec.luau` documenta as duas tarefas juntas mas o diff real de
   registro é só 2 linhas novas (`WorldRoot`/`PhysicsService` no `BehaviorIndex`) — sem
   contaminação cruzada de lógica.

## Avaliação da decisão de design (item 8 do pedido)

Não implementar a restrição cliente/servidor de `Unregister`/`RenameCollisionGroup` como branch
`if isClient() then error() end` é razoável e consistente com precedente já existente no
repositório: `behavior/RunService.luau` já fixa `IsServer() -> true`/`IsClient() -> false` sem
RunContext simulado (confirmado lendo o arquivo). Um branch client-only seria código morto e
impossível de testar honestamente sob essa mesma premissa arquitetural — documentar em vez de
implementar é a aplicação correta da regra 01 ("teste o que for prático executar de verdade") e
evita esconder uma lacuna atrás de uma implementação que nunca executaria de fato.

## Achados

Nenhum GRAVE/ALTO/MÉDIO. Dois BAIXO, não bloqueantes:

**[BAIXO]** `src/services/behavior/PhysicsService.luau:71-80` (`getWorkspaceRegistry`)
Problema: erro interno usa string `[LuauBench]` misturada com `Workspace` — mensagem correta, mas é
uma invariante interna inalcançável por script de usuário comum (Workspace é sempre registrada);
apenas notando que não há teste cobrindo esse ramo (razoável, já que é inalcançável na prática).
Cenário de falha: nenhum realista — exigiria um bug de bootstrap prévio para nunca acontecer.
Correção: nenhuma ação necessária; comentário já documenta isso.

**[BAIXO]** `src/services/CollisionGroups.luau:57-65` (`GetRegisteredCollisionGroups` retorna só
`{ Name: string }`)
Problema: divergência de forma de retorno do Roblox real não confirmada (dump não documenta tipo de
elemento do Array) — já declarada extensivamente no cabeçalho, mas vale registrar como pendência de
pesquisa caso uma citação futura apareça.
Cenário de falha: um script real que espera `.Mask` ou id numérico no retorno quebraria — cenário
improvável dado que não há doc oficial do formato.
Correção: nenhuma ação agora; revisitar se `pesquisador` achar citação verbatim do formato real.

## O que NÃO foi verificado a fundo (fora do escopo pedido)

- Não reexaminei os 2 achados mecânicos já corrigidos pelo orquestrador (título do teste de
  HttpService, contagens hardcoded de `generate-services.spec.luau`) — conferidos de relance ao
  rodar a suíte completa (passam), não reabertos.
- Não avaliei task-services-026/task-cli-026 em si (fora do escopo desta revisão, territórios/
  tarefas diferentes, ainda `in-progress`).
