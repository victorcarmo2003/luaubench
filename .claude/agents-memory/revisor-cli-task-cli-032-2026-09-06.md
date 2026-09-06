# Revisão task-cli-032 — erro em BindToClose engolido silenciosamente

Território: `src/cli/RunCommand.luau` + `src/cli/RunCommand.spec.luau`. Read-only, tudo reproduzido
por mim (não aceitei self-report do coder).

## Verificação 1 — suítes (rodei eu mesmo)

- `lune run src/cli/RunCommand.spec.luau` → **18/18**.
- Rodei cada um dos 16 `*.spec.luau` de `src/cli/` individualmente e somei: 16+9+7+8+12+12+13+17+18+8+7+33+28+38+6+7 = **239/239**. Confere com o alegado.

## Verificação 2, 3, 4 — cenários do acceptance (evidência do próprio processo real, `lune run src/cli/main.luau run <fixture>`, dentro da suíte)

- Fixture `bindtoclose-error`: stderr contém `error ServerScriptService.Main:6: bindtoclose boom (...)`, exit code 1, sumário `1 error(s), 0 warning(s)`, e o SEGUNDO callback (`bindtoclose: second callback still ran...`) aparece no stdout — confirma erro formatado igual a erro de script normal, contagem, exit code, e não-interrupção dos demais callbacks.
- Fixture `bindtoclose` (sem erro): stderr sem nenhuma linha `error `, sumário `0 error(s)` — confirma regressão zero de task-cli-031 (callback sem erro continua silencioso).

Nada disso é "confiar no coder" — rodei os processos reais e li stdout/stderr eu mesmo.

## Verificação 5 — limitação documentada (dupla contagem): CONFIRMADA REPRODUZÍVEL NA PRÁTICA, não só teórica

Construí um fixture próprio fora do repositório (`ProjectPath` externo, nenhum arquivo de
`src/cli/` tocado) com:
- `game:BindToClose(function() task.wait(0.5) end)` (callback que CEDE, abrindo uma janela longa).
- Script principal com `while true do n+=1; task.wait(0.05); if n==5 then error(...) end end`.
- `--timeout 0.1` (expira bem antes do script principal chegar a `n==5`, deixando a thread do
  script principal ainda suspensa em `task.wait` quando `scheduler:Run` do passo 11 retorna).

Rodei via `RunCommand.Execute` real (mesmo módulo, sem cópia). Resultado:

```
error ServerScriptService.Main:13: leftover thread boom (double-count repro)
error ServerScriptService.Main:13: leftover thread boom (double-count repro)
2 error(s), 0 warning(s).
ExitCode=1 ErrorCount=2 WarningCount=0
```

**Um único `error()` real virou 2 no sumário.** Mecanismo confirmado lendo o código:
`Sandbox.Run` (`src/runtime/Sandbox.luau:525`) conecta um listener em `scheduler.ThreadError` e
**nunca desconecta** (a `Connection` nem é armazenada) — ele filtra por `ownThreads`, então fica
inofensivo depois que o Script termina, EXCETO se uma thread daquele `ownThreads` for retomada
mais tarde. `DataModel.RunBindToCloseCallbacks` chama `scheduler:Run(anyStillAlive)`
(`DataModel.luau:370`), cujo laço interno (`Scheduler.Run`, `Scheduler.luau:449-472`) drena
`self.waiting`/`self.delayed` inteiros — não só as threads de BindToClose — então a thread do
script principal, ainda viva na fila `waiting`, é retomada dentro dessa janela, erra, e o mesmo
`ThreadError:Fire` é recebido tanto pelo listener antigo (nunca desconectado, filtro por
`ownThreads` bate) quanto pelo listener novo desta task (sem filtro nenhum). Dois `OutputRecord`
para um erro só.

Isto bate exatamente com o que o comentário de `RunCommand.luau` (linhas 352-367) já descreve —
não é invenção minha, é a mesma limitação, só que **verificada como reproduzível de fato** (via
`--timeout` + BindToClose com callback que cede), não apenas teórica. Cenário exige as duas
condições ao mesmo tempo (timeout expirado + thread principal ainda suspensa + erro durante a
janela do BindToClose que cede) — não acontece em nenhum caso do acceptance desta task (nenhum dos
fixtures de teste usa `--timeout` + `BindToClose`), então não bloqueia esta tarefa. Ainda assim é
um achado real (sumário mente sobre a contagem de erro), não hipotético, e vale abrir task nova no
board (`runtime`: expor os handles de `RunBindToCloseCallbacks`, ou `cli`: dar um jeito de marcar
"threads pré-existentes" antes de conectar o listener sem filtro).

## Verificação 6 — `--!strict` / `any`

Ambos os arquivos começam com `--!strict`. `grep '\bany\b'` só encontra a palavra dentro de um
comentário que EXPLICA a ausência de `any` (linha 294) — zero uso real.
`luau-lsp analyze --platform=standard` limpo nos dois arquivos (sem diagnósticos).

## Verificação 7 — território

`git status` atual mostra só `src/cli/RunCommand.luau` e `src/cli/RunCommand.spec.luau`
modificados dentro de `src/cli/` (outros arquivos de `cli` que apareciam no snapshot inicial da
conversa já estavam commitados por `1175dc4` antes desta revisão começar). `git diff --stat`
confere: 2 arquivos, 119 inserções/5 remoções. Território limpo.

## Verificação 8 — duplicação de `parseBindToCloseThreadError`

Comparei as 3 cópias: `Sandbox.splitErrorMessage` (`src/runtime/Sandbox.luau`, ancorada a
`scriptName`), `OutputFormatter.tryReattributeModuleError` (`src/cli/OutputFormatter.luau:90-96`,
MESMO regex `'%[string "(.-)"%]:(%d+): (.*)$'`, não ancorada) e a nova
`parseBindToCloseThreadError` (mesmo regex não ancorado + a mesma lógica de corte na primeira
quebra de linha). É de fato praticamente idêntica a `tryReattributeModuleError` — as duas vivem em
`src/cli/`, então uma extração para uma função compartilhada dentro do próprio território era
tecnicamente possível sem cruzar fronteira nenhuma.

Avaliação: a descrição da própria task no board já restringe o escopo a "só
`src/cli/RunCommand.luau` + spec", o que tecnicamente impede tocar `OutputFormatter.luau` sem
violar o próprio acceptance. Aceito como débito técnico documentado nesta rodada — mas é a
**terceira** cópia do mesmo padrão mágico (achado incidental já citado em pelo menos uma revisão
anterior no board, task de `TreeMaterializer`/"achado MÉDIO", como precedente do mesmo tipo de
duplicação). Recomendo abrir uma task nova e explícita de consolidação (pelo menos as 2 cópias
dentro de `cli`: `OutputFormatter.tryReattributeModuleError` + `RunCommand.parseBindToCloseThreadError`
→ uma função exportada única) antes que uma quarta cópia apareça.

## Veredito

APROVADO COM RESSALVAS.

- MÉDIO/ALTO (não bloqueante desta task, já declarado e fora do acceptance): dupla contagem de
  erro confirmada reproduzível na prática com `--timeout` + `BindToClose` que cede — abrir task de
  correção em `runtime` (expor handles) ou `cli` (marcador de geração de thread).
- BAIXO/MÉDIO: `parseBindToCloseThreadError` é a 3ª cópia do mesmo parsing de erro (2 delas já
  dentro do próprio território `cli`) — abrir task de consolidação em vez de deixar acumular.

Tudo mais (12/12 pontos de verificação pedidos, specs, comportamento real, território, tipagem)
confere com o alegado, verificado por mim de ponta a ponta.
