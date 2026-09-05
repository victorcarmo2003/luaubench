# Pesquisa — Lute vs. Lune (para decisão de troca de runtime do LuauBench)

Pergunta original do usuário: "o Lute seria melhor que o Lune?" — pesquisa factual, sem recomendação de troca (isso é decisão do usuário, invariante 3 do projeto).

Todas as fontes abaixo são primárias (repositório oficial, docs oficiais, GitHub API) — nenhuma inferência não marcada.

## 1. O que é o Lute e quem mantém

**Fonte oficial (não inferência):** [`luau-lang/lute`](https://github.com/luau-lang/lute) (README, `primary` branch, lido em 2026-09-05).

- Repositório vive na organização GitHub `luau-lang` — a mesma organização da linguagem Luau em si (Roblox é quem desenvolve Luau). O próprio README diz: *"We're working within Roblox to make `std` a shared interface across our Luau runtimes."* — confirma que é projeto interno da Roblox/time do Luau, não comunidade terceira.
- É um **runtime standalone**, não SDK/lib embarcável: "Lute is a standalone runtime for general-purpose programming in Luau." Tem CLI própria com subcomandos: `check`, `compile`, `debug`, `lint`, `pkg`, `run`, `self`, `setup`, `test`, `transform` (fonte: https://lute.luau.org/cli).
- Objetivo declarado: fazer Luau funcionar como linguagem de propósito geral fora do Roblox — mesmo nicho que o Lune ocupa hoje.
- Licença: **MIT** (via GitHub API `license.spdx_id`). Sem restrição para uso pessoal/distribuição via Rokit.

## 2. Maturidade

- **Release "estável" única:** `v1.0.0`, publicada em **2026-04-16** (confirmado via `gh api repos/luau-lang/lute/releases`, é o único release marcado `prerelease: false`).
- Desde então, só saíram **nightlies pré-release** (`v1.0.1-nightly.*`), a mais recente `v1.0.1-nightly.20260904` (04/09/2026 — véspera de hoje). Ou seja: nenhuma release estável nova em quase 5 meses, mas desenvolvimento ativo continua diariamente em pré-release.
- **Palavras do próprio README (citação direta, não parafraseada):**
  > "Neither of these facts are intended to suggest that Lute is a finished product, and we expect to continue to develop it further in the future. [...] There are still many gaps and areas we'd like to improve, and we expect it will take plenty of time to get there."
- Página de docs do `@lute/fs` traz aviso explícito: *"These APIs are still open to future evolution. In new major versions, they may change in backwards incompatible ways."*
- Comparação de tração via GitHub API (`gh api repos/<org>/<repo>`, 2026-09-05):

  | | Lute | Lune |
  |---|---|---|
  | Criado em | 2024-10-20 | 2023-01-18 |
  | Stars | 336 | 942 |
  | Forks | 56 | 134 |
  | Issues abertas | 106 | 72 |
  | Último push | 2026-09-05 | 2026-07-03 |
  | Licença | MIT | MPL-2.0 |

  Lute é mais novo, menor em adoção/comunidade, mas com desenvolvimento mais ativo recentemente (push de hoje vs. Lune parado desde julho).

**Conclusão de maturidade:** oficialmente descrito pelos próprios mantenedores como não-finalizado, com "muitas lacunas" e API sujeita a quebra em major versions futuras. Não é "experimental" no sentido de brinquedo — já é usado internamente na Roblox para infra/tooling — mas também não é uma base tão testada em produção externa quanto o Lune (que está em produção pública desde 2023).

## 3. `fs.watch` — o ponto mais importante

**CONFIRMADO, existe nativamente.** Fonte: https://lute.luau.org/lute/fs (docs oficiais, lido em 2026-09-05).

```luau
fs.watch: (path: string, callback: (filename: string, event: WatchEvent) -> ()) -> WatchHandle

type WatchEvent = {
    change: boolean,
    rename: boolean,
}
```

- `WatchHandle` tem método `:close()` para parar o watcher.
- Implementação é baseada em **libuv** (mesma lib que o Node.js usa para `fs.watch` — cross-platform, inclusive Windows). Confirmado pelo histórico de issues do repositório: issue [#298 "`fs.watch` libuv binding"](https://github.com/luau-lang/lute/issues/298) — **fechada** (implementada).
- Isso resolveria diretamente o bloqueio atual do LuauBench: Lune 0.10.5 não tem watcher nativo (issue aberta desde 2023, sem previsão), forçando o `--watch` mode do LuauBench a ficar bloqueado ou implementar polling (proibido pela regra `.claude/rules/04-cli-rokit.md`, que exige "observador de filesystem do Lune, nunca por polling").

**Limites e pegadinhas encontrados:**
- `WatchEvent` só tem dois booleanos (`change`/`rename`) — não distingue create/delete/modify separadamente, nem confirma watch recursivo de subdiretórios (não documentado na página).
- Issue aberta e não resolvida: [#1143 "more expressive file watcher"](https://github.com/luau-lang/lute/issues/1143) — o próprio time do Lute considera a API atual limitada/básica.
- Histórico de flakiness: issue [#639 "flaky test: fs.test.luau:watch_iterator_on_change"](https://github.com/luau-lang/lute/issues/639) — fechada, mas indica que já houve instabilidade nos testes do watcher.
- Aviso geral já citado: API pode quebrar em versões futuras (breaking changes ainda esperadas).

## 4. Compilação para executável standalone

**CONFIRMADO.** Fonte: https://lute.luau.org/cli.

- Subcomando `lute compile` — descrito na doc oficial como *"Compile a Luau script into a standalone executable"* — equivalente direto ao `lune build`.
- Binários pré-compilados existem para Windows: todo release/nightly inclui `lute-windows-x86_64.zip` (além de linux-x86_64, linux-aarch64, macos-aarch64), confirmado via `gh api repos/luau-lang/lute/releases`.
- Importante não confundir: `luthier` (`tools/luthier.luau` no repo do Lute) é a ferramenta de build do **próprio Lute** (bootstrapping do runtime em C++/CMake/Ninja) — não é a ferramenta que o usuário final usaria para compilar *seus* scripts. Essa é o `lute compile` do CLI do binário já compilado.
- Distribuição via Rokit: o próprio README do Lute cita `rokit` como uma das formas de instalar um `lute` já compilado para build de desenvolvimento (`rokit install` busca uma versão do `lute` para build) — mas isso é sobre instalar o *Lute* via Rokit, não confirma diretamente se um executável **gerado pelo LuauBench com `lute compile`** se encaixaria no fluxo de publicação em GitHub Release + Rokit da mesma forma que hoje com `lune build`. Como é "só" um binário standalone publicado em GitHub Release, a expectativa razoável é que sim (Rokit não se importa com o que gerou o binário) — mas isso é **inferência minha, não confirmado por fonte primária testando esse fluxo específico**.

## 5. Compatibilidade de API com o que o LuauBench já usa do Lune

**Resposta curta: API diferente, não é substituição direta — exigiria reescrever a camada de I/O.**

Comparação módulo a módulo (fontes: https://lute.luau.org/lute/{fs,net,process,task,io} e https://lute.luau.org/std/json para o lado Lute; https://lune-org.github.io/docs/api-reference/{serde,stdio} para o lado Lune):

| Módulo Lune | Equivalente no Lute | Compatível? |
|---|---|---|
| `@lune/fs` | `@lute/fs` — `open/read/write/close/stat/copy/move/remove/mkdir/rmdir/listdir/symlink/link/type/exists/watch` | Cobertura de funcionalidade parecida, mas **paradigma diferente**: Lute usa `FileHandle` (abrir/ler/escrever/fechar, estilo POSIX de baixo nível); precisa confirmar se Lune tem equivalente por handle ou só por path — de qualquer forma, nomes e assinaturas não batem 1:1. Reescrita necessária, não port trivial. |
| `@lune/net` | `@lute/net` (submódulos `client`/`server`) — tem tipos para `Response`, `WebSocket`, `Server`, `Handler` | Só confirmei tipos, não os nomes de função exatos (`net.request`? `net.serve`?) — **não confirmado** se os nomes batem com `@lune/net`. |
| `@lune/process` | `@lute/process` — `process.run()`, `process.system()`, `process.exit()`, `process.env`, `process.args`, `process.cwd()`, `process.pid()`, `process.onSignal()` | Forma parecida, mas nomes diferem (ex.: Lute usa `process.run`, não confirmei se Lune usa `process.spawn` — nomes não idênticos de qualquer forma). |
| `@lune/task` | `@lute/task` — `task.spawn`, `task.wait`, `task.delay`, `task.defer` | **Mais próximo dos quatro** — mesmos nomes de função. Ainda assim, semântica exata (ordem de scheduler) não foi verificada a fundo aqui. |
| `@lune/serde` (json + **yaml** + **toml** + compressão gzip/zlib/lz4/brotli/zstd + hash/hmac) | `@std/json` — só **serialize/deserialize/asObject/asArray/object**, só JSON | **Lacuna real confirmada.** Não encontrei módulo YAML/TOML/compressão no `@std` do Lute nem em `@lute` builtins. Se o LuauBench depender de `@lune/serde` além de JSON puro, é funcionalidade que falta no Lute hoje. |
| `@lune/stdio` (`color`, `style`, `format`, `prompt`, `write`, `ewrite`, `readLine`, `readToEnd`) | `@lute/io` — só **`io.read()`** e **`io.write()`** | **Lacuna real confirmada.** Sem cor/estilo ANSI, sem `prompt`, sem `format` com syntax highlighting. Isso importa porque a regra `.claude/rules/04-cli-rokit.md` pede saída formatada "como o Output do Studio" — hoje dependeria de reimplementar isso à mão sobre `io.write` cru. |

## 6. Razões práticas para NÃO trocar agora

1. **Autoavaliação dos próprios mantenedores:** "not a finished product", "many gaps", API "open to future evolution" com possíveis breaking changes em major versions — dito no README e na doc oficial, não é interpretação minha.
2. **Só uma release estável (`v1.0.0`, abril/2026) há 5 meses**, com todo o resto sendo nightly pré-release — pinar uma versão reprodutível (exigido pela regra `03-services-api-dump.md` por analogia de reprodutibilidade) significa pinar em algo rotulado pré-release ou ficar preso à `v1.0.0` que pode já estar desatualizada frente aos nightlies.
3. **Lacunas de biblioteca confirmadas:** sem YAML/TOML/compressão (`serde`) e sem cor/estilo/prompt (`stdio`) no que documentação oficial mostra hoje — teria que ser escrito à mão dentro do LuauBench ou aguardar o Lute preencher.
4. **API não é compatível** com o que já foi usado como referência de `@lune/*` no projeto — troca não é "mudar um require", é reescrever a camada de I/O inteira do `cli` (e onde mais o Lune for chamado).
5. **Comunidade/maturidade menor:** 336 stars / 56 forks / 106 issues abertas vs. 942 / 134 / 72 do Lune, e Lune está em produção pública há 3 anos a mais.
6. **`fs.watch` em si já tem uma issue reconhecida pelo próprio time do Lute pedindo uma API mais expressiva** (#1143) — resolve o problema central de watch nativo, mas não é garantidamente estável/completo.
7. Fluxo de publicação de um binário compilado com `lute compile` em GitHub Release + Rokit **não foi testado/confirmado** por mim como equivalente 1:1 ao pipeline atual com `lune build` — é inferência razoável, não fato verificado.

## Fontes consultadas

- https://github.com/luau-lang/lute (README, branch `primary`, lido 2026-09-05)
- https://github.com/luau-lang/lute/releases (via `gh api`, lido 2026-09-05)
- https://lute.luau.org/ , /lute/ , /lute/fs , /lute/net , /lute/process , /lute/task , /lute/io , /cli , /std , /std/json (docs oficiais, lidas 2026-09-05)
- https://github.com/luau-lang/lute/issues/298, #1143, #639 (via `gh api`, lido 2026-09-05)
- https://lune-org.github.io/docs/api-reference/serde e /stdio (docs oficiais do Lune, lidas 2026-09-05, para comparação)
- `gh api repos/luau-lang/lute` e `repos/lune-org/lune` (estatísticas de repositório, lido 2026-09-05)

## Incerto / não confirmado

- Nomes de função exatos de `@lute/net` (só os tipos foram documentados na página consultada).
- Se `fs.watch` do Lute suporta watch recursivo de subdiretórios — não documentado explicitamente.
- Se um executável gerado por `lute compile` se publica em Rokit exatamente como um `lune build` hoje (inferência razoável, não testada).
- Semântica fina do scheduler (`task.wait`/`task.spawn`) do Lute vs. Lune — só confirmei que os nomes de função existem, não o comportamento de ordenação interno.
