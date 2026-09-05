# Revisão final — task-services-005 (fecha `services` leva 1)

Escopo: `src/services/init.luau` + `src/services/init.spec.luau` (únicos arquivos de código tocados). Revisão feita rodando tudo de verdade (binário Lune do rokit + `luau-lsp` 1.69.0), nunca por leitura só.

## Verificação item a item (conforme pedido pela thread principal)

1. **Os 3 erros distinguíveis por substring, isolados.** Confirmado rodando `lune run src/services/init.spec.luau` (14/14) — os três testes dedicados passam: `Instance.new("Frmae")` (typo, ausente do manifesto) erra `Unable to create an Instance of type "Frmae"` sem `[LuauBench]`; `Instance.new("Workspace")` (`IsAbstract=true`, confirmado em `generated/Manifest.luau:935`) erra a MESMA mensagem/família; `Instance.new("Frame")` (`generated/Manifest.luau:339`, `IsAbstract=false, Covered=false`) erra COM prefixo `[LuauBench]` citando `0.737.0.7371584`. Teste "os três casos são distinguíveis por substring" também passa.
2. **`Instance.new("Folder")` funciona.** Confirmado (`Services.new('Folder') funciona normalmente` — PASS).
3. **`IsKnownClass("Frame")==true`, `IsSimulatedClass("Frame")==false`.** Confirmado pelo teste dedicado e por inspeção direta do manifesto (`Frame`: `Covered=false`, não está em `generated/Index.luau`).
4. **`GetDumpVersion`.** Lê de `generated/Manifest.luau` (`DumpCommit`/`DumpVersion`), que bate byte-a-byte com `tools/api-dump.lock.json` (`28360dea4b90b35dc3fe9f829baae64fb6c50e75` / `0.737.0.7371584`). Sem literal duplicado em `init.luau` (o antigo `DUMP_COMMIT`/`DUMP_VERSION` foi removido — confirmado no diff).
5. **Smoke test do bootstrap é real.** Lido linha a linha: `Runtime.Sandbox.Run({...})` é chamada de verdade (não há mock/substituto), o script roda `game:GetService("ReplicatedStorage")` + `Instance.new("Folder")` + `folder.Parent = rs` DENTRO do `source` sandboxed, `scheduler:Run(shouldContinue)` é chamado depois (passo 8 real), e a verificação pós-execução usa a MESMA variável `game` (`game:FindService("ReplicatedStorage")` seguido de `FindFirstChild("SmokeFolder")`) — não um clone. Rodei o teste isoladamente: PASS.
6. **`extraGlobals.Instance = { new = Services.new }`.** É exatamente o padrão documentado no cabeçalho de `init.luau` (seção "SEQUÊNCIA DE BOOTSTRAP", passo 7) e o mesmo usado no smoke test (`init.spec.luau`, teste do bootstrap). Não é aproximação — é literalmente o mesmo trecho reaproveitado do desenho do arquiteto ("Quem chama primeiro").
7. **Regressão total.** Rodei TODOS os specs individualmente (não confiei no relato):
   - Runtime: ClassRegistry 29, DataModel 12, Instance 57, Integration 9, Sandbox 7, Scheduler 16, Signal 7, init 6 → **143/143**.
   - Services: init 14, ClassBuilder 9, Context 3, Integration 14, RejectingSignal 5, behavior/Index 4, behavior/Players 8, behavior/RunService 11, behavior/StarterPlayer 3 → **71/71** (64 anteriores de task-003/004 + 7 novos de task-005, todos passando; nenhum arquivo de task-003/004 foi tocado — ver item 8).
8. **`git diff --stat`.** Confirmado: só `.claude/tasks.json`, `src/services/init.luau` e `src/services/init.spec.luau` mudaram. Zero edição em `src/services/generated/`, `src/services/behavior/` ou `src/runtime/`.
9. **Achado de tooling (segundo bug de `luau-lsp`).** Ver seção dedicada abaixo — confirmado pré-existente, mas com uma imprecisão no comentário.

## Achado

```
[BAIXO] src/services/init.spec.luau:57
Problema: o comentário afirma que o TypeError do segundo bug de `luau-lsp` "reproduz IDÊNTICO nos dois `Runtime.Sandbox.Run` já existentes... (linhas 180 e 223)" de `src/runtime/init.spec.luau`, mas isso é impreciso — só a linha 180 tem `extraGlobals` inline; a linha 223 não passa `extraGlobals` nenhum, então não pode (e não reproduz, confirmado empiricamente) o mesmo erro ali.
Cenário de falha: nenhum — é só uma imprecisão factual num comentário de diagnóstico de tooling, sem efeito em código/teste/comportamento. Não é uma regressão nem afeta a conclusão central (o bug é pré-existente, não introduzido por esta tarefa).
Correção: ajustar o comentário para citar só a linha 180 (ou reformular para "reproduz em todo `extraGlobals = {...}` inline com literal de tabela, incluindo pelo menos a linha 180 de src/runtime/init.spec.luau", sem afirmar "nos dois").
```

### Verificação empírica do achado #9 (protocolo pedido: reproduzir, não supor)

- `luau-lsp analyze --platform=standard src/services/init.spec.luau` → cascata de "Unknown require"/"Unknown type" (bug 1, nome começando por `init`), confirmando o mascaramento.
- Copiei `init.spec.luau` para um nome que não começa com `init` (mesma técnica do coder) e rodei de novo: o único `TypeError` restante é exatamente o citado — "Property 'Instance' is not compatible. Expected this to be exactly '{| new: ... |}', but got 'unknown'" — na linha do smoke test (o único `Runtime.Sandbox.Run` do arquivo). Nenhum outro erro sobra.
- Fiz o mesmo com `src/runtime/init.spec.luau` (arquivo já aprovado, fora do território desta tarefa): a cópia renomeada mostra o MESMO TypeError na linha 180 (`extraGlobals = { game = root, report = ... }`), confirmando que o bug é pré-existente em `runtime` e não foi introduzido agora. A linha 223 (`Runtime.Sandbox.Run` sem `extraGlobals`) NÃO produz esse erro — só o erro genérico esperado não aparece ali porque o campo nem existe nessa chamada. Daí o achado BAIXO acima: a alegação "reproduz nos dois" está incorreta para a linha 223 especificamente, mas a conclusão de fundo (pré-existente, não é regressão de `services`) está certa.
- Rodei `luau-lsp analyze --platform=standard src/services/init.luau` diretamente (não via require) — **limpo, zero erros**. Confirma que o próprio arquivo revisado não introduz nenhum problema de tipagem real; os dois achados de tooling são efeitos de análise de `require`/união opcional do `luau-lsp`, não do código de `services`.

## Checks adicionais

- `--!strict` presente em ambos os arquivos; zero ocorrências de `any` (grep).
- Invariante "24 `Covered=true` no Manifest == 24 requires em `generated/Index.luau`" verificada por comparação de conjuntos (não só contagem) — os nomes batem exatamente.
- `Manifest.Classes["Workspace"]` = `{Superclass="WorldRoot", IsService=true, IsAbstract=true, Covered=true}`; `Manifest.Classes["Frame"]` = `{Superclass="GuiObject", IsService=false, IsAbstract=false, Covered=false}` — batem com o que os testes assumem.

## Veredito

## Veredito
APROVADO COM RESSALVAS

Fecha a leva 1 de `services` por completo. A única ressalva é o achado BAIXO acima (imprecisão de comentário sobre onde o bug de tooling reproduz) — não bloqueante, não afeta código/teste/comportamento, e a conclusão central que o comentário defende (bug pré-existente em `runtime`, não regressão desta tarefa) está correta e foi confirmada por mim de forma independente.
