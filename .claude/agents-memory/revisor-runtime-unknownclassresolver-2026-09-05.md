# Revisão — task-runtime-030 (`UnknownClassResolver` + `GetService`/`FindService` reescritos)

Data: 2026-09-05. Revisor: `revisor-runtime` (read-only). Estado do board no momento da revisão: `task-runtime-030` em `in-progress` (coder não marcou `done`, aguardando esta revisão — comportamento correto do fluxo).

Toda verificação abaixo foi **reproduzida por mim**, não aceita por alegação do coder. Onde criei script descartável dentro de `src/runtime/` para testar algo que os specs oficiais não cobrem isoladamente, deletei o arquivo logo em seguida (`git status` confirmado limpo antes/depois).

## 1. Suite de runtime — 8 specs, rodados um a um por mim

```
ClassRegistry.spec.luau  -> 29/29
DataModel.spec.luau      -> 16/16
Instance.spec.luau       -> 63/63
Integration.spec.luau    -> 9/9
Sandbox.spec.luau        -> 20/20
Scheduler.spec.luau      -> 16/16
Signal.spec.luau         -> 7/7
init.spec.luau           -> 6/6
TOTAL PASSADO: 166/166
```

Zero falha, zero regressão. Baseline anterior à tarefa (medido pelo `coder-cli` em `task-cli-015`, registrado em `.claude/tasks.json`: "8 specs de runtime (162/162)") + 4 testes novos desta tarefa (3 vereditos + 1 sequestro) = 166. Bate exatamente.

**Discrepância no self-report:** o coder alegou "154/154 testes de runtime passando (8 specs)". O número correto, reproduzido por mim de forma determinística (rodei duas vezes), é **166/166**. Não é uma regressão nem uma mentira sobre resultado (todos os testes realmente passam), mas é uma contagem incorreta no relatório — ver achado BAIXO abaixo.

## 2. `UnknownClassResolver.luau` — módulo folha, zero `require`

Confirmado por leitura: nenhum `require` no arquivo (nem de `Instance.luau`). `Set`/`Resolve` com as assinaturas exatas do desenho.

Testei eu mesmo a sobrescrita silenciosa (script descartável, depois removido):
- `Set(resolverA)` → `Resolve("X")` devolve o veredito de A.
- `Set(resolverB)` → `Resolve("X")` (mesma classe) devolve o veredito de B, nunca mais A.

Confirmado: a segunda chamada vale, sem erro, sem acumulação.

## 3. Ordem de `GetService`/`FindService`

Lido o código reescrito em `DataModel.luau`. Ordem exata do desenho:
1. `ClassRegistry.Get(className)` primeiro, sempre.
2. Se `descriptor ~= nil`: gate `IsService` ANTES de qualquer busca de filho — `not descriptor.IsService` retorna `nil` imediatamente, sem chamar `FindFirstChildOfClass`.
3. Só dentro do ramo `IsService == true` é que `FindFirstChildOfClass`/`NewEngineInstance` rodam.
4. Se `descriptor == nil`: só aí o resolvedor é consultado.

`FindService` tem o mesmo gate (`Get` + `IsService`) antes de `FindFirstChildOfClass`, nunca consulta o resolvedor, nunca erra — confirmado por leitura direta.

## 4. Teste de sequestro (reproduzido por mim, fora do spec oficial)

Registrei uma classe `FolderProbe` (`IsService = false`), criei uma instância e parentei direto sob a raiz (`DataModel`). Confirmado:
- `dataModel:GetService("FolderProbe")` → `nil` (não devolve o Folder do usuário).
- `dataModel:FindService("FolderProbe")` → `nil` pelo mesmo motivo.

Sanity check incluído: `dataModel:FindFirstChild("FolderProbe")` confirma que o Folder realmente está parentado ali — o `nil` de `GetService` não é por falta do filho, é o gate funcionando.

## 5. Os 4 casos de `GetService`, com resolvedor falso instalado por mim (fora do spec oficial)

- **NotAClass** → `GetService("Doge")` erra com `'Doge' is not a valid Service name` (aspas simples, S maiúsculo, sem prefixo, sem `[LuauBench]`). Mensagem batida caractere por caractere.
- **NotAService** → `GetService("Frame")` devolve `nil`, sem erro.
- **ServiceNotSimulated** → `GetService("TestServiceAindaNaoSimuladoProbe")` erra com a `Message` do veredito **verbatim** (runtime não reformata nada).
- **Sem resolvedor instalado** (processo Lune limpo, novo, sem nenhum `Set` chamado): `GetService("Workspace")` erra com `GetService: nenhum resolvedor de classe desconhecida instalado -- Services.Register()/Services.Bootstrap() precisa ter rodado antes...`, mensagem em português citando `Services.Bootstrap`.

Todos os 4 casos batem exatamente com a acceptance.

## 6. Nível de erro (level 2)

Confirmado com script próprio: chamando `GetService` de dentro de uma função nomeada no meu script de sondagem, o erro devolvido aponta para a linha do MEU script (linha do `pcall`/chamada), nunca para uma linha de `DataModel.luau`. Testado nos ramos `NotAClass` e `ServiceNotSimulated`; o ramo "sem resolvedor" também aponta para a linha do script chamador (confirmado no teste do item 5). Não há vazamento de path interno do LuauBench na mensagem de erro.

## 7. Terceiro teste ajustado — `TestStarterPlayerScriptsShape`

Lido o diff completo. Antes: `GetService` de uma classe `IsAbstract=true, IsService=false` esperava erro "não é um Service" (a guarda documentada já era `IsService`, nunca `IsAbstract`). Depois: espera `nil`, pela MESMA razão categórica que inverteu os outros dois testes-gatilho — toda classe registrada com `IsService=false` agora devolve `nil` em vez de erro, e esta forma (StarterPlayerScripts) é só mais uma instância dessa mesma categoria (registrada, `IsService=false`, adicionalmente `IsAbstract=true`, o que é irrelevante para o gate de `GetService`). O ajuste é coerente com a mudança de comportamento documentada no design, não uma correção forçada para maquiar problema — o comentário inline "AJUSTE task-runtime-030" explica exatamente isso e a explicação bate com o código.

## 8. Tipos `-> Instance?`

Confirmado no diff: `GetService: (self: DataModel, className: string) -> Instance?` (era `-> Instance`) e `FindService` já era `-> Instance?`. `luau-lsp analyze --platform=standard` roda limpo nos 4 arquivos tocados (exit sem erro).

## 9. `init.luau` reexporta só `Set` + tipos

Confirmado: `Runtime.UnknownClassResolver = { Set = UnknownClassResolverModule.Set }` e os dois tipos exportados (`UnknownClassVerdict`, `UnknownClassResolver`). `Resolve` não aparece na tabela pública nem como export de tipo além do que já é exposto.

## 10. `ClassRegistry.luau` não editado

`git diff --stat HEAD -- src/runtime/ClassRegistry.luau` devolve vazio. Confirmado.

## 11. Sem `require` novo para `services`, sem vocabulário proibido no código operante

`grep -rn "require.*services" src/runtime/` só bate em comentários pré-existentes (prosa, não `require` de verdade) em `ClassRegistry.luau`/`Instance.luau`/`init.spec.luau`, nenhum deles tocado por esta tarefa.

Quanto a "API Dump"/"manifesto"/"cobertura"/"versão": esses termos **aparecem em comentários de documentação** dentro de `UnknownClassResolver.luau`, `DataModel.luau` e `DataModel.spec.luau` (explicando o "porquê" da divisão de território — inclusive o próprio cabeçalho de `UnknownClassResolver.luau` cita "API Dump" na frase que explica que o módulo NÃO usa esse vocabulário operacionalmente). Nenhuma dessas ocorrências está em código executável, identificador ou string de erro construída em `runtime` — as duas mensagens que `runtime` de fato constrói (`notAValidServiceNameMessage` e o erro de "nenhum resolvedor instalado") não citam nenhum desses termos; a única mensagem que cita `[LuauBench]`/versão do dump (`ServiceNotSimulated.Message`) chega pronta de `services` e é repassada verbatim. Este padrão já existia em `DataModel.luau:19` (pré-existente, "Toda Service do Roblox API Dump carrega a tag NotCreatable") antes desta tarefa. Não considero isto violação da regra 02/acceptance — a leitura literal ("nenhuma menção") entraria em conflito com a própria exigência de documentar decisões de arquitetura (regra 00). Registro aqui para o usuário decidir se quer uma leitura mais estrita.

## 12. Zero arquivo fora de `src/runtime/` tocado

`git status --porcelain` mostra só `.claude/tasks.json` (board, mudança de coluna `todo`→`in-progress`, não código) e os 4 arquivos de `src/runtime/`. Confirmado.

## 13. `--!strict` sem `any` novo

`UnknownClassResolver.luau` começa com `--!strict`. Grep por `\bany\b` nos arquivos tocados não encontra ocorrência de tipo `any` (só a palavra dentro de comentários em português, não como anotação de tipo).

## 14. Cenário adversarial — resolvedor instalado por `services` que chama `error()` internamente

Testado com script descartável: instalei um resolvedor falso que chama `error("resolvedor mal-comportado...")` sem nível explícito (nível 1 default). Resultado: o erro sobe através de `UnknownClassResolver.Resolve` → `DataModel.GetService` **sem ser interceptado** — `GetService` não envolve a chamada a `Resolve` em `pcall`. O erro chega ao chamador com a localização de onde o `error()` foi chamado dentro do próprio resolvedor (no meu teste, a linha do resolvedor no meu script de sondagem).

Isso significa que, na integração real com `task-services-011`, se `resolveUnknownClass` (o resolvedor real que `services` vai instalar) chamar `error()` por engano — violando o contrato PURO/TOTAL documentado — a mensagem de erro que chega ao script do usuário citaria a localização interna de `src/services/init.luau`, não uma mensagem formatada por `DataModel`. Isso não derruba o processo (o `pcall` do `Sandbox` em volta da execução do script do usuário ainda captura, já que o erro sobe como um `error()` Luau comum através da cadeia de chamadas do próprio script) — mas produziria uma mensagem inconsistente com as três famílias documentadas (Roblox/`[LuauBench]`/engenharia interna em português), potencialmente vazando path de arquivo interno do LuauBench para o Output do usuário.

**Não é bloqueante para esta tarefa**: o desenho já deixa explícito, no cabeçalho de `UnknownClassResolver.luau` e na seção de riscos do `arquiteto-runtime-2026-09-04.md` ("Riscos e decisões"), que o contrato é garantido por convenção entre territórios, não por validação em runtime — "`runtime` não sabe de onde a função veio" é uma decisão deliberada, não uma omissão. Registro aqui como observação para quem revisar `task-services-011`: vale conferir que `resolveUnknownClass` realmente nunca lança erro (é puro/total por construção — consulta de tabela), e não há necessidade de `runtime` se defender disso.

## Achados

**[BAIXO] task-runtime-030 (self-report do coder)**
Problema: o coder relatou "154/154 testes de runtime passando (8 specs)"; a contagem real, reproduzida por mim duas vezes de forma determinística, é 166/166 (162 pré-existentes + 4 novos desta tarefa).
Cenário de falha: nenhum — todos os 166 testes realmente passam, zero regressão. É uma imprecisão de relato, não um defeito de código.
Correção: nenhuma ação de código necessária; ajustar a prática de contagem do self-report (somar os "X/X testes passaram" de cada um dos 8 specs, não estimar).

**[BAIXO / observação, não bloqueante] `src/runtime/UnknownClassResolver.luau`, `DataModel.luau`, `DataModel.spec.luau`**
Problema: comentários de documentação mencionam literalmente "API Dump"/"manifesto"/"cobertura"/"versão", o que uma leitura estritamente literal da acceptance ("nenhuma menção... dentro de src/runtime/") marcaria como violação.
Cenário de falha: nenhum em tempo de execução — são comentários, não código operante; as mensagens de erro que `runtime` de fato constrói não usam esse vocabulário. Padrão já presente antes desta tarefa (`DataModel.luau:19`).
Correção: nenhuma ação necessária na minha leitura (documentar o "porquê" da fronteira exige citar os termos que ela evita); registrado só para transparência.

**[nota, não bloqueante] Cenário adversarial — resolvedor que chama `error()` internamente**
Ver item 14 acima. `GetService` não se defende de um resolvedor mal-comportado (decisão deliberada, documentada). Vale conferência quando `task-services-011` for revisada: confirmar que `resolveUnknownClass` realmente nunca lança erro.

Nenhum achado GRAVE, ALTO ou MÉDIO. Ordem de `GetService`/`FindService`, tipos, contrato entre territórios, ausência de `require` cruzado, `ClassRegistry.luau` intocado, zero arquivo fora do território, `--!strict` sem `any`, nível de erro 2 em todos os ramos, e os 4 casos de classificação — todos confirmados por reprodução própria, não por alegação do coder.

## Veredito

APROVADO COM RESSALVAS — a única ressalva de fato é a contagem incorreta no self-report (154 vs. 166 real); o código em si está correto, completo e fiel ao desenho em todos os pontos verificados.
