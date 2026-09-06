# Revisão — task-services-033 (strip de localização em `Services.FlushCloudState`)

Data: 2026-09-06
Escopo: `src/services/init.luau`, `src/services/init.spec.luau`

## Veredito

**APROVADO**

## O que foi verificado, com evidência reproduzida (não aceito self-report)

1. **30/30 `init.spec.luau`** — rodado eu mesmo (`lune run src/services/init.spec.luau`), 30/30 passaram, incluindo o teste novo de `task-services-033`.

2. **Reprodução direta do vazamento antes do fix / correção do fix** — escrevi um script temporário (`src/services/_repro_task_033.luau`, removido ao final, `git status` confirma que não sobrou) chamando `Services.Bootstrap` + `Services.FlushCloudState()` diretamente (sem `RunCommand.luau`, sem a defesa em profundidade do `cli`) com um port fake cujo `Save` lança:
   ```
   D:\UserData\Documents\GitHub\luaubench\src\cli\CloudStore:170: CloudStore: could not create "C:\Users\SomeUser\MyRobloxGame\cloud-cache\datastore.json": Cannot create a file when that file already exists. (os error 183)
   ```
   Resultado: `message = CloudStore: could not create "C:\Users\SomeUser\MyRobloxGame\cloud-cache\datastore.json": Cannot create a file when that file already exists. (os error 183)` — caminho de instalação do LuauBench (`D:\...\luaubench\...`) removido, texto substantivo (incluindo o caminho do PROJETO DO USUÁRIO e `os error 183`) preservado.

3. **Regex `^.-:%d+: (.*)$` não corta demais nem de menos** — testei 5 variações, todas corretas:
   - `"...CloudStore:170: could not create \"C:\\path\": os error 5"` → sobrevive `could not create "C:\path": os error 5` intacto (só o PRIMEIRO prefixo `caminho:linha:` cortado, o `:` de `os error 5` sobrevive).
   - Mensagem sem prefixo reconhecível (`"erro cru sem prefixo de localização: apenas texto"`) → devolvida inalterada (não corta de mais).
   - Conteúdo com múltiplos `":"` logo após o prefixo (`"...CloudStore:170: chave: valor: outro: valor2"`) → sobrevive `chave: valor: outro: valor2` completo.
   - Caminho com `:` de unidade Windows antes do número de linha real (`D:\UserData\...\CloudStore:170: mensagem final`) → o padrão não-guloso não para no `D:` (não seguido de dígito+`: `), avança corretamente até `CloudStore:170: `.
   Confirma que a cópia local é comportamentalmente idêntica a `TreeMaterializer.StripEngineErrorLocation` (mesma regex, linha 242-248 daquele arquivo).

4. **Decisão de escopo (só escrita) é razoável e não é regressão nova** — li `loadCloudStateIfPresent`/`Services.Bootstrap` (`src/services/init.luau:324-351`): `Load`/`Snapshot.DecodeDocument` propagam exceção crua, sem `pcall`, por design — comportamento já coberto por dois testes pré-existentes de `task-services-031` (`"...Load lança erro: PROPAGA..."` e `"...Load devolve JSON inválido: PROPAGA..."`), confirmados fora do diff desta task (`git diff --stat` mostra só +91/-0 em `init.spec.luau`, inserção pura antes desses testes, que continuam intocados). Não há alteração de comportamento no caminho de leitura nesta task.

5. **`--!strict` presente nos dois arquivos, zero `any`** — `grep -n '\bany\b'` não encontrou ocorrência real (só a palavra em comentário, se houver, não em anotação de tipo) nos dois arquivos.

6. **Território limpo** — `git diff --stat` mostra mudanças também em `.claude/tasks.json`, `src/services/behavior/Index.luau`, `src/services/generated/Index.luau`, `src/services/generated/Manifest.luau`, `tools/coverage.luau` e arquivos novos de `SoundService`/`tests/scenarios/`. Inspecionei o diff desses arquivos: são inteiramente sobre `SoundService` (task-services-025, concorrente) e cenários do `testador` — nada relacionado a `firstLineOf`/`CloudStore`/prefixo de localização. Confirmado que task-services-033 tocou exclusivamente `src/services/init.luau` + `src/services/init.spec.luau`, como determinado pelo território da task.

7. **`Index.spec.luau`/`HttpService.spec.luau` são de fato não-relacionados** — rodei os dois:
   - `src/services/behavior/Index.spec.luau` falha com `"esperava 17 entradas até esta leva ... recebeu 18"` — exatamente o efeito esperado da entrada nova `SoundService` (task-services-025, concorrente), nada a ver com `firstLineOf`.
   - `src/services/behavior/HttpService.spec.luau` falha com `"a thread não terminou dentro do watchdog de 10s (rede travada?)"` — timeout de rede/DNS ambiental, não relacionado ao fix desta task.
   Confirmado via `git diff` que não toquei nada relacionado a nenhum dos dois.

## Achados

Nenhum achado GRAVE/ALTO/MÉDIO/BAIXO. Comentário de código é longo mas correto e rastreável (cita a linha exata da lógica original em `TreeMaterializer.luau`).
