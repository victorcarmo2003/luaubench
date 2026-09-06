# Revisão do fix do achado ALTO (task-cli-030) — vazamento de path interno

**Data:** 2026-09-06 · `revisor-cli` · Read-only, tudo reproduzido pessoalmente. Nenhum self-report do coder aceito sem reprodução própria.

## Veredito

**APROVADO COM RESSALVAS**

O fix resolve exatamente o achado ALTO original, sem tocar fora do território. Uma ressalva nova, achada nesta revisão (não relacionada ao fix em si): flakiness real em um teste pré-existente e não relacionado (`http-audit`, task-cli-026) dentro da mesma suíte.

---

## O que verifiquei e como

### 1. Suítes — números exatos

`lune run src/cli/RunCommand.spec.luau` isolado: **30/30** (bate com o alegado, era 28, +2 novos da Parte 4).

Todas as 16 suítes de `src/cli/*.spec.luau` rodadas: Args 18/18, CloudStore 9/9, Diagnostics 7/7, JsonValue 8/8, Messages 16/16, ModuleLoader 12/12, OutputFormatter 13/13, ProjectFile 17/17, RunCommand 30/30, ScriptEnvironment 8/8, ScriptRunner 7/7, SyncRules 33/33, TreeMaterializer 28/28, TreePlanner 38/38, UnsimulatedGlobals 6/6, init 7/7. Todas verdes nesta rodada.

**Achado novo (fora do escopo do fix, mas real):** rodei `RunCommand.spec.luau` mais 4 vezes seguidas para checar estabilidade. Resultado: **3 de 5 execuções falharam** no teste "Processo real: fixture 'http-audit' ... (achado MÉDIO, revisão task-cli-026)" (`RunCommand.spec.luau:245`), com a asserção de `result.stdout` conter `"got body: " .. RESPONSE_BODY` falhando — o processo real terminou 0 erro/0 warning mas sem o corpo esperado no stdout (aparenta corrida entre o `net.serve` local subir/servir e o `HttpService:GetAsync` do processo `lune` filho, ou timing da porta fixa 47210). Não é meu escopo julgar a causa raiz, mas isto **não é** o teste do fix (`state-unreadable`/`save-failed`), que passou 100% das vezes (5/5) nas mesmas rodadas — a alegação "30/30" é verdadeira em cada rodada individual que passou, mas não é estável run-a-run por causa de um teste alheio (task-cli-026), pré-existente, na mesma suíte. Reportar ao orquestrador para abrir tarefa de flakiness — não bloqueia este fix.

### 2. Reprodução manual independente (processo real, fora do spec do coder)

Criei dois projetos do zero em `scratchpad/` (fora de `%TEMP%/luaubench-runcommand-persist-spec/` usado pelo spec, para não reaproveitar a reprodução do coder) e rodei `lune run src/cli/main.luau run <projeto> --no-color` diretamente:

- **Documento cloud corrompido** (`{ this is not valid json`): saída —
  `error: [cloud/state-unreadable] ... Snapshot.DecodeDocument: invalid JSON: key must be a string at line 1 column 3 -- the file was left untouched; ...` — exit 2. **Sem** `D:\`, sem `\src\`, sem caminho de instalação — só o caminho do projeto do usuário (aceitável) e a mensagem limpa do decoder.
- **`.luaubench` obstruído por um arquivo**: saída —
  `warning: [cloud/save-failed] ... CloudStore: could not create "...\.luaubench": Cannot create a file when that file already exists. (os error 183) -- the script keeps running ...` — exit 0, script rodou até o fim. **Sem** path de instalação.

Confirma de ponta a ponta, com reprodução própria (não a do spec do coder), que os dois pontos do achado original estão corrigidos.

### 3. `TreeMaterializer.StripEngineErrorLocation` — mesma função, não cópia

Lido `TreeMaterializer.luau:242-249`: a função local `stripEngineErrorLocation` é definida uma única vez (regex `^.-:%d+: (.*)$`) e a linha `TreeMaterializer.StripEngineErrorLocation = stripEngineErrorLocation` só atribui essa MESMA closure ao campo do módulo — é a única linha nova do diff deste arquivo (confirmado via `git diff`, o resto é só comentário). `RunCommand.luau:271-273` chama `TreeMaterializer.StripEngineErrorLocation(tostring(err))` diretamente — não há segunda implementação em lugar nenhum.

### 4. `src/services/init.luau` — bug residual confirmado, real

Lido `src/services/init.luau:357-360`:
```lua
local function firstLineOf(err: unknown): string
	local text = tostring(err)
	return string.match(text, "^[^\n]*") or text
end
```
Confirma o achado do coder: essa cópia só corta na primeira quebra de linha, nunca remove o prefixo `<caminho>:<linha>: `. Usada em `Services.FlushCloudState` (linha ~401, `return false, firstLineOf(err)`). Hoje mitigado só porque `RunCommand.luau` reaplica `firstLineOf`/`StripEngineErrorLocation` por fora (defesa em profundidade, confirmada em `makeFlushCloudState`, `RunCommand.luau:297-316`, comentário explícito citando essa mesma lacuna). Se outro chamador de `Services.FlushCloudState()` não reaplicar o strip, o vazamento reaparece — é uma pendência real, fora do território desta correção (`src/services/**`), corretamente reportada e não escondida.

### 5. `--!strict` / zero `any`

Confirmado nos três arquivos (`TreeMaterializer.luau`, `RunCommand.luau`, `RunCommand.spec.luau`): `--!strict` na primeira linha dos três. As únicas ocorrências da palavra `any` nos três são comentários dizendo explicitamente "nunca um `any`"/"sem `any`" — nenhuma anotação de tipo `any` real.

### 6. Território

`git status`/`git diff --stat` mostram 9 arquivos modificados no total (todo o task-cli-030 ainda não commitado), mas o diff específico deste FIX (via grep por `firstLineOf`/`StripEngineErrorLocation`/`stripEngineErrorLocation`) só aparece em `TreeMaterializer.luau`, `RunCommand.luau` e `RunCommand.spec.luau` — os outros 6 arquivos (`Args.luau`/`.spec`, `Messages.luau`/`.spec`, `init.luau`/`.spec`) são trabalho pré-existente da tarefa-mãe task-cli-030 (já revisado em `revisor-cli-task-cli-030-2026-09-06.md`), sem relação com este fix pontual. `src/services/**` confirmado sem nenhuma modificação (`git diff --stat -- src/services/` vazio) — o coder não tocou o território vizinho, mesmo tendo achado o bug lá.

---

## Achado

Nenhum novo achado ALTO/GRAVE. Único ponto levantado nesta revisão (MÉDIO, não bloqueia): flakiness pré-existente em `RunCommand.spec.luau:245` (`http-audit`, task-cli-026) — 3 de 5 rodadas falharam, independente do fix revisado aqui. Recomendo ao orquestrador abrir tarefa de investigação de flakiness (`coder-cli` ou `debugger`) separada.

## O que NÃO é problema (verificado)

- `firstLineOf` de `RunCommand.luau` delega 100% para `TreeMaterializer.StripEngineErrorLocation` — sem lógica duplicada.
- Os dois cenários do achado original (leitura corrompida / escrita obstruída) não vazam mais path de instalação, confirmado por reprodução própria, duas vezes (via spec do coder e via reprodução manual independente).
- Bug residual em `src/services/init.luau` é real, mas está dentro do relatado (não escondido) e mitigado por defesa em profundidade do lado `cli`.
