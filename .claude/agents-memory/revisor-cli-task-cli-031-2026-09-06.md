# Revisão task-cli-031 — RunBindToCloseCallbacks em RunCommand

Read-only. Todas as evidências abaixo foram reproduzidas por mim, não aceitas do self-report do coder.

## O que foi verificado, com evidência reproduzida

1. **Suítes**: `lune run src/cli/RunCommand.spec.luau` → 18/18. Rodei individualmente as 16 suítes
   de `src/cli/` (`lune run` em cada uma) e somei os totais impressos: 16+9+7+7+8+12+12+13+17+8+7+33
   +28+38+6+18 = **239/239**, batendo exatamente com o alegado.

2. **`RunCommand.Execute` chama `Runtime.DataModel.RunBindToCloseCallbacks(game, scheduler)`**
   em `src/cli/RunCommand.luau:307`, depois de `scheduler:Run(buildShouldContinue(options.Timeout))`
   (linha 287) e antes de `printDiagnostics`/sumário (linhas 309-312) — passo 12 do pipeline. Também
   confirmei que `RunBindToCloseCallbacks` já está no agregador público de `runtime`
   (`src/runtime/init.luau:216`, decisão de task-runtime-033) — não é acesso a módulo interno.

3. **Processo real, fixture `bindtoclose`** (`lune run src/cli/main.luau run
   src/cli/fixtures/run-e2e/bindtoclose --no-color`): stdout contém, NESTA ORDEM, "main script ran"
   → "bindtoclose: simple callback ran" → "bindtoclose: yielding callback finished" (task.wait(0.05)
   dentro do callback) → só depois a linha de sumário "Script(s) executed". Confirma disparo real E
   espera real do callback que cede.

4. **Processo real, fixture `bindtoclose-error`**: exit code 0, "main script ran" e "bindtoclose:
   second callback still ran despite the first one erroring" ambos em stdout — o erro no primeiro
   callback não impede o segundo nem muda o exit code.

5. **Achado do coder é REAL, reproduzido de forma independente**: rodei
   `lune run src/cli/main.luau run src/cli/fixtures/run-e2e/bindtoclose-error --no-color` capturando
   stdout/stderr separadamente. Resultado: exit code 0, stderr **vazio**, stdout sem qualquer menção
   ao erro, e a linha de sumário final diz literalmente **"0 error(s), 0 warning(s)"** — apesar de um
   `error("bindtoclose boom...")` ter de fato disparado dentro de um callback de `BindToClose`.
   Causa raiz confirmada por leitura: `ScriptRunner.Run`/`Sandbox.Run` só se inscreve em
   `scheduler.ThreadError` filtrando pelas threads que ELE PRÓPRIO criou (`ownThreads`, ver
   `ModuleLoader.luau`/`Sandbox.luau`); as threads de `BindToClose` são criadas depois, direto por
   `DataModel.RunBindToCloseCallbacks` via `scheduler:Spawn`, sem nenhum listener de `ThreadError`
   conectado a elas em `RunCommand.luau`. O erro sai por `ThreadError` como o `runtime` promete (não
   é bug de `runtime`), mas nada no `cli` traduz esse `ThreadError` específico em output — do ponto
   de vista do usuário é silêncio total, inclusive na contagem de erros do sumário e no exit code.

6. **Regressão (`basic`, sem `BindToClose`)**: processo real confirma zero linhas contendo
   "bindtoclose" no stdout, exit code 0 — comportamento idêntico ao anterior à task.

7. **`--!strict`/zero `any`**: `luau-lsp analyze --platform=standard --settings=".luaurc"` limpo
   (exit 0, zero diagnósticos) em `RunCommand.luau` e `RunCommand.spec.luau` analisados
   individualmente. (Analisá-los junto com `src/services/init.luau` produz um `SyntaxError` na
   linha 337 daquele arquivo — reproduzi e confirmei que é artefato do analyzer ao processar múltiplos
   arquivos juntos: `src/services/init.luau` sozinho analisa limpo, e `lune run` executa a suíte
   inteira sem erro nenhum. Não é regressão desta task nem relacionado a `RunCommand`.) Nenhum `any`
   real — só uma menção em comentário.

8. **Território limpo**: `git status` restrito a `src/cli/` mostra só `RunCommand.luau`,
   `RunCommand.spec.luau` modificados, e os dois diretórios novos de fixture
   (`fixtures/run-e2e/bindtoclose`, `fixtures/run-e2e/bindtoclose-error`). Nenhum outro arquivo do
   território tocado.

## Avaliação do achado fora de escopo (erro silencioso em BindToClose)

O achado é real e a análise de causa do coder está correta. Quanto à severidade: o acceptance
literal de task-cli-031 pedia só "não derruba o processo, não impede os demais" — que está
satisfeito. Só que o gap tem peso prático alto porque o caso de uso central do projeto
(CLAUDE.md: "a gravação final de sessão do ProfileStore mora exatamente dentro de um
BindToClose") é exatamente o cenário afetado: um bug no código de save-on-close do usuário vira
"0 error(s)" e exit code 0 — sucesso aparente para uma falha real de persistência. Isso colide
com regra 01 ("nunca engolir erro sem logar") e regra 04 ("erro formatado como Output do Studio")
em espírito, mesmo não sendo um `pcall` silencioso escrito por este código (é ausência de listener,
não supressão ativa). Não é bloqueante para ESTA task (escopo explicitamente restrito à chamada
básica), mas recomendo abrir task nova de prioridade alta agora — não deixar como débito indefinido
— para conectar `ThreadError` das threads de `BindToClose` a `OutputFormatter`/contagem de erro do
sumário.

## Veredito

APROVADO COM RESSALVAS — ressalva: abrir task de prioridade alta para reportar erro de
`BindToClose` no output/exit code (gap real, não bloqueante para task-cli-031, mas não deixar sem
task registrada dado o impacto no caso de uso central do projeto).
