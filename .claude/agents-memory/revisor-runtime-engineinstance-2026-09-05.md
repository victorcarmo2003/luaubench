# Revisão — task-runtime-023 (ClassRegistry.NewEngineInstance / NotCreatable vs. abstrata)

Revisor: revisor-runtime. Data: 2026-09-05. Escopo: `src/runtime/ClassRegistry.luau`,
`DataModel.luau`, `init.luau` + os 3 specs correspondentes. Quarto patch em `ClassRegistry.luau`
na sessão — revisão feita com rigor elevado por instrução explícita do usuário, sem confiar no
relato do coder em nenhum ponto crítico.

## Metodologia

Não confiei nos specs do coder para os pontos críticos (1)-(4) do pedido — escrevi um script
próprio (`verify_task023_scratch.luau`, na raiz do repo, `require("./src/runtime")` real, API
pública, nunca módulo interno), rodei via `lune run`, apaguei ao final (não commitado, não deixa
resíduo — `git status --short` confirmado limpo depois). 20 asserções próprias, 20/20 OK.

Rodei cada spec de `src/runtime/*.spec.luau` individualmente via `lune run` (binário
`~/.rokit/bin/lune`), sem confiar no "143/143" relatado sem checar: Signal 7, Instance 57,
Scheduler 16, ClassRegistry 29, DataModel 12, Integration 9, init 6, Sandbox 7 = **143/143,
bate exatamente**. `luau-lsp analyze --platform=standard` limpo em `ClassRegistry.luau`,
`DataModel.luau`, `ClassRegistry.spec.luau`, `DataModel.spec.luau`; `init.luau`/`init.spec.luau`
reproduzem só o bug de tooling já documentado (init* + luau-lsp 1.69.0), não bloqueante. Zero
`any` real nos 6 arquivos (grep confirmou a única ocorrência da palavra é um comentário citando a
regra 01). `--!strict` na primeira linha dos 6 arquivos. `git diff --stat` confirma **zero
arquivo de `src/services/` tocado**.

Para cada um dos 3 specs alterados (`ClassRegistry.spec.luau`, `DataModel.spec.luau`,
`init.spec.luau`) rodei `git diff` linha a linha: em todos os três, a única mudança sobre um
teste PRÉ-EXISTENTE é a atualização da string esperada em "new() erra claramente para classe
abstrata" (mensagem nova, mudança documentada e esperada) — todo o resto é bloco novo, no fim do
arquivo. `makeServiceDescriptor` (DataModel.spec.luau) — o fixture do bug — passou a nascer
`IsAbstract = true` por default quando `IsService = true`; conferi os 5 call sites pré-existentes
da função (`TestServiceSingleton`, `TestNaoService`, `TestServiceFind`, `TestServiceNuncaCriado`,
`TestServiceIsolamento`) e nenhum deles instancia via `ClassRegistry.new` diretamente (só
`GetService`/`FindService`), então a mudança de default não altera o comportamento de nenhum
teste antigo — confirmado pela execução (12/12 passa).

## Checklist dos 10 pontos pedidos

1. **`GetService` de descriptor `IsService=true` E `IsAbstract=true` constrói o singleton de
   verdade** — CONFIRMADO com script próprio (não só o spec do coder): ClassName/Name/Parent
   corretos, segunda chamada devolve o MESMO objeto.
2. **`ClassRegistry.new` sobre o MESMO descriptor continua errando**, mensagem cita
   `NotCreatable` e nomeia `NewEngineInstance` — CONFIRMADO, mensagem real capturada:
   `classe 'ReviewerRealService' não é criável por script (tag NotCreatable do Roblox API Dump);
   construção interna do motor usa ClassRegistry.NewEngineInstance`.
3. **Instância de `NewEngineInstance` é COMPLETA** — CONFIRMADO nos 5 aspectos, com classes de
   teste próprias (não as do coder): cadeia aplicada (`IsA` de ancestral indireto e de
   `"Instance"`), método de classe instalado e chamável, schema instalado com `Default` semeado,
   `Signal` fresco por instância para `Kind == "Event"` (duas instâncias, `Signal`s diferentes por
   identidade), `Initialize` executado.
4. **Forma `StarterPlayerScripts` (`IsAbstract=true`, `IsService=false`)** — CONFIRMADO: construível
   por `NewEngineInstance`, rejeitada por `.new`, `GetService` continua errando com a mensagem
   "não é um Service" (a guarda é `IsService`, nunca `IsAbstract`).
5. **Auditoria de nível de erro** — majoritariamente correta, **UM ACHADO** (ver seção abaixo).
6. **Erros de ciclo de herança e superclasse órfã disparam pelas duas entradas** com a mensagem
   certa — confirmado pelos testes (i)/(j) de `ClassRegistry.spec.luau`, rodados e passando; não
   reproduzi manualmente porque a asserção já cobre literalmente o pedido (mensagem de conteúdo,
   não de prefixo `arquivo:linha:`).
7. **`NewEngineInstance` exportada; `NewBase`/`SetClassChain`/`SetClassMethods`/`SetClassSchema`/
   `ThreadBroker` continuam ausentes** — confirmado por leitura de `init.luau` (só
   `NewEngineInstance` foi adicionada à sub-tabela `ClassRegistry`) e pelo teste de vazamento em
   `init.spec.luau` (intocado, roda e passa).
8. **`DataModel.GetService`/`FindService`/`export type DataModel`** — `git diff` mostra ZERO
   mudança na declaração de tipo; só o corpo do closure de `GetService` mudou (troca de
   `ClassRegistryModule.new` por `.NewEngineInstance`, mais comentários).
9. **Zero arquivo de `src/services/` tocado** — `git diff --stat` confirma; só
   `.claude/agents-memory/*.md`, `.claude/tasks.json` e os 6 arquivos de `src/runtime/` listados
   na tarefa.
10. **Regressão total 143/143**, nenhum teste pré-existente alterado (só adição, exceto a mensagem
    de "TestAbstrata") — confirmado por execução + diff linha a linha dos 3 specs.

## Achados

```
[MÉDIO] src/runtime/ClassRegistry.luau:205-210
Problema: o comentário da auditoria obrigatória afirma que Instance.SetClassMethods é "chamada em
um ÚNICO ponto, sempre de dentro de NewEngineInstance (nunca diretamente por ClassRegistry.new)" —
isso é factualmente falso: src/runtime/DataModel.luau:116 chama
InstanceModule.SetClassMethods(instance, DataModelMethods) DIRETO, fora de NewEngineInstance e
fora de qualquer caminho de ClassRegistry inteiramente (DataModel.new monta a raiz à mão, sem
passar por ClassRegistry).
Cenário de falha: hoje nenhum erro real dispara desse segundo call site (DataModelMethods é uma
tabela fixa, congelada, sem colisão com FIXED_PROPERTY_KEYS/SIGNAL_KEYS) — não há bug de
comportamento em produção agora. O risco é de processo: um mantenedor futuro que precise mexer em
SetClassMethods ou em DataModel.new lê esse comentário, confia que "único ponto, sempre dentro de
NewEngineInstance" é verdade, e não reavalia o nível de erro do call site de DataModel.luau se ele
um dia deixar de ser uma chamada direta (ex.: DataModel.new passar a delegar para algum wrapper
intermediário) — é exatamente o padrão que causou o bug de resolveClassChain que esta mesma tarefa
corrigiu (uma função presumida de "chamador único" ganhando um segundo call site sem ninguém
reavaliar a suposição de nível). A auditoria pedida pelo arquiteto era para ser completa o
suficiente pra fechar esse tipo de landmine para sempre; este comentário específico não é.
Correção: no comentário de ClassRegistry.luau:205-210, trocar "chamadas em um ÚNICO ponto, sempre
de dentro de NewEngineInstance" por algo como "chamadas em pontos fixos e diretos (dentro de
NewEngineInstance para toda classe via ClassRegistry, e diretamente em DataModel.new para a raiz)
— em ambos os casos o nível 2 aponta para o call site correto porque a chamada é direta, sem
wrapper de profundidade variável entre o chamador e SetClassMethods/SetClassSchema". Não precisa
mudar nível de erro nenhum — só o texto do comentário, que está fazendo uma afirmação factual
verificável e errada.
```

Não achei mais nada além disso, apesar de ter procurado ativamente por um "quinto caso" dado o
histórico de 4 patches:

- Enumerei TODOS os call sites de produção de `ClassRegistry.new`/`NewEngineInstance` no runtime
  (grep completo) — só os 2 já mapeados pelo arquiteto (delegação interna `.new` -> `NewEngineInstance`,
  e `DataModel.GetService`).
- Reconferi manualmente `Instance.NewBase` (sem `error()`), `resolveClassMethods`/
  `resolveClassSchema` (sem `error()`), e o próprio `error(...)` de "classe não registrada" dentro
  de `NewEngineInstance`: esse é inalcançável via `.new()` porque `.new()` já faz seu próprio
  lookup e erra antes de delegar (o "lookup duplicado deliberado" documentado no código) — então o
  nível 2 dentro de `NewEngineInstance` só é alcançado pela via direta, single-hop, estável. Mesmo
  raciocínio para o erro de `IsAbstract` dentro de `.new()`.
- Conferi que nenhum teste pré-existente de `Signal.spec`/`Instance.spec`/`Scheduler.spec`/
  `Sandbox.spec`/`Integration.spec` foi tocado (fora do escopo da tarefa, mas granularidade
  máxima pedida) — `git diff --stat` já mostra que esses 5 arquivos nem aparecem no diff.

## Veredito

APROVADO COM RESSALVAS
