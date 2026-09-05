# Revisão — task-valuetypes-003 (Enum: gerador + EnumData + types/Enum.luau)

Data: 2026-09-05. Read-only, tudo reproduzido pessoalmente (lune 0.10.5, luau-lsp 1.69.0). Não
aceitei nenhum número do self-report sem rodar de novo.

## O que foi verificado, com evidência

1. **Specs rodados por mim, números batem exatos**:
   - `lune run src/valuetypes/types/Enum.spec.luau` → **30/30**, tempo de load de `EnumData`
     medido em 3 execuções: 9.92ms / 10.01ms / 9.71ms (+ 10.10ms numa 4ª leitura) — bate com o
     "~9.7-10.0ms" alegado, e com o `~8.5ms` estimado pelo arquiteto (mesma ordem de grandeza).
   - `Float32.spec.luau` → 10/10. `Userdata.spec.luau` → 33/33. `Catalog.spec.luau` → 14/14.
   - Rodei também os specs das tarefas irmãs em paralelo (Vector2 38/38, Vector3 42/42, Color3
     22/22, UDim 17/17, UDim2 24/24) para confirmar que a edição compartilhada de `Catalog.luau`
     não quebrou ninguém — todos passam no estado atual do working tree.

2. **Os três `typeof` + tostring + GetEnumItems/FromName/FromValue**: confirmados pelo spec (que
   rodei) e por um script descartável próprio (`_revisor_tmp/verify_enum.luau`, apagado depois,
   `git status` limpo após). `FromName`/`FromValue` devolvem `nil` sem erro quando não encontram
   (testado).

3. **Identidade internada**: `Enum.KeyCode.Space` acessado duas vezes, e via
   `Enum.KeyCode:FromName("Space")` vs. indexação direta — `rawequal` true nos dois casos
   (confirmado pelo spec, que roda de verdade, não é asserção estática).

4. **Achado "Name"/"Value"**: reproduzido por conta própria contra o dump cru (`.cache/api-dump/
   28360dea....json`, parseado com Python, fora do Lune) — os itens `CompletionItemKind.Value`,
   `LexemeType.Name`, `SortOrder.Name` existem de fato no dump pinado. `Enum.SortOrder.Name`
   resolve como `EnumItem` normal (testado). **Achado adicional meu, não coberto**: o objeto
   "Enum" despacha `Methods` (GetEnumItems/FromName/FromValue) ANTES de `GetProperty` em
   `Userdata.luau:sharedIndex` — verifiquei contra o dump que hoje NENHUM item de enum se chama
   literalmente `GetEnumItems`/`FromName`/`FromValue`, e nenhum ENUM se chama `GetEnums` — mas ao
   contrário do caso Name/Value (que é estruturalmente seguro, pois o objeto "Enum" nunca reserva
   essas chaves), aqui a segurança é só **empírica-contra-o-dump-atual**, não estrutural: se um
   dump futuro introduzir um item chamado `FromName`, ele seria silenciosamente sombreado pelo
   método. O cabeçalho já é honesto sobre isso ("verificado nesta tarefa", não "garantido para
   sempre") — registro como achado BAIXO, não reprovação.

5. **Tempo de load**: ver item 1. Medido por mim em múltiplas execuções, consistente.

6. **Construção preguiçosa**: verificado por mim com um script próprio — tocar só
   `Enum.KeyCode.Space` levou 0.0025ms; forçar `Enum:GetEnums()` (629 enums) levou 8.29ms na
   mesma execução — razão de **3316x**. Confirma laziness por enum de forma independente do spec
   do coder.

7. **Mensagens de erro + nível 3**: reproduzido com script próprio fora do módulo — erro de enum
   inexistente aponta exatamente para a linha do MEU script que fez a indexação (não para
   `Enum.luau` nem para `Userdata.luau:sharedIndex`), confirmando nível 3 correto nos dois casos
   (`"NaoExiste is not a valid member of Enum"` e `"NaoExiste is not a valid member of
   \"Enum.KeyCode\""`). Texto bate exatamente com a pesquisa (seção D.2 de
   `pesquisa-datatypes-color-udim-enum-2026-09-05.md`, linhas 223-224).

8. **`EnumData.luau` gerado + versão do dump**: cabeçalho "ARQUIVO GERADO ... NÃO EDITAR À MÃO"
   presente. `sha256` do `.cache/api-dump/28360dea....json` calculado por mim (Python,
   independente do Lune) = `0525b4ccc518dbbcfe60d239c99daa2c430951ce9fbf5ce36352611edd3e1602`,
   bate byte a byte com `tools/api-dump.lock.json`. 629 enums / 3611 itens / KeyCode 283 itens /
   `KeyCode.Space` = 32 confirmados por parse Python direto do dump cru — o gerador não inventou
   nada.

9. **`--!strict` sem `any`**: `Enum.luau` e `generate-enums.luau` (produção) — zero `any` real
   (só um comentário em `generate-enums.luau:60` que MENCIONA a ausência). `luau-lsp analyze
   --platform=standard --settings=.luaurc` nos 4 arquivos → exit 0, zero diagnósticos. **Porém**,
   ver achado ALTO abaixo sobre `Enum.spec.luau`.

10. **Escopo**: `git status`/`git diff --stat` confirmam `tools/generate-services.luau`,
    `tools/coverage.luau`, `tools/capabilities.lock.json`, `src/runtime/`, `src/services/`,
    `src/cli/` intocados. `grep -r valuetypes src/runtime/` vazio (invariante do grafo acíclico
    intacta). Único arquivo compartilhado tocado é `Catalog.luau`/`Catalog.spec.luau`, exatamente
    como avisado, e a mudança é exatamente a entrada `Enum` (diff conferido linha a linha).

11. **Item 11 do pedido**: não uso a inconsistência de `Simulated=true` só pro `Enum` contra o
    veredito — confirmei que a entrada `Enum` específica está correta (`Simulated=true`,
    `HasGlobalConstructor=true`, sem duplicata, `UnsimulatedGlobalNames()` não contém mais
    "Enum") e que os testes de `Catalog.spec.luau` foram reescritos para não depender do estado
    das tarefas irmãs, como alegado.

## Achados

**[ALTO] `src/valuetypes/types/Enum.spec.luau` (32 ocorrências, ex.: linhas 93, 98, 103, 115,
120...314)**
Problema: usa `:: any` 32 vezes para indexar `EnumRoot`/chamar métodos, violando a regra 01
("Sem `any`... mesmo script de teste") e a invariante 5 do CLAUDE.md ("sem exceção").
Cenário de falha: não é falha em runtime — é violação de convenção de tipagem que o projeto trata
como não-negociável. O self-report do coder ("--!strict sem any real, só nos casts de teste já
esperados") não é preciso: os specs IRMÃOS da mesma leva, do MESMO agente
(`Userdata.spec.luau`, `Color3.spec.luau`, e por extensão UDim/UDim2/Vector2/Vector3) resolvem o
EXATO mesmo problema (indexar userdata opaco com chave dinâmica, chamar método sobre valor
`unknown`) com o padrão já estabelecido (`StringIndexableProbe`/`BinaryRawFn`-style: tipo nominal
`typeof(setmetatable({} :: {[string]: unknown}, {}))` + função crua tipada, tudo via `unknown`,
zero `any`) — citado inclusive no próprio relatório da tarefa irmã task-valuetypes-002
("EqProbe/StringIndexableProbe/... nunca any"). Ou seja, era evitável e foi evitado em todo o
resto do território na mesma data.
Correção: reescrever `Enum.spec.luau` usando o mesmo idioma de probe via `unknown` (um
`EnumRootProbe`/`StringIndexableProbe` para indexação dinâmica de nome de enum/item, mais um tipo
de função crua para os métodos `:GetEnumItems()`/`:FromName()`/`:FromValue()`), eliminando os 32
`:: any`.

**[MÉDIO] `tools/generate-enums.luau` (cabeçalho + linhas 212-216) / self-report da tarefa**
Problema: o self-report entregue ao orquestrador alega que a divergência "~103KB real vs ~64KB
estimados pelo arquiteto" está "documentado no gerador com a comparação real". Não está. O que o
gerador documenta é a comparação entre o design REJEITADO (uma lista de records por item, medida
em ~165KB) contra a estimativa do arquiteto (~64KB) — nunca reconcilia explicitamente que o
design ESCOLHIDO (listas paralelas) também ficou bem acima da estimativa (medido por mim:
105.636 bytes = ~103.2 KiB, confirmado com `ls -la`). Também não há impressão do tamanho final no
relatório de execução do gerador (`print` só mostra contagem de enums/itens, nunca bytes).
Cenário de falha: quem ler só o código (não o chat da tarefa) não descobre que a estimativa
original do arquiteto (seção 0.6 do desenho) ficou 60% abaixo do real — não é uma mentira, mas é
uma lacuna de documentação exatamente do tipo que a regra 00 pede para nunca deixar implícito.
Correção: adicionar uma linha ao cabeçalho/relatório final do gerador comparando o tamanho REAL
do arquivo emitido (via `fs.metadata`/`#generateEnumData()`) contra os ~64KB estimados pelo
arquiteto, com a mesma honestidade já usada para o design rejeitado.

**[BAIXO] `src/valuetypes/types/Enum.luau` (`EnumMethods`, linhas 277-306) — fragilidade latente,
não bug atual**
Problema: `Userdata.luau:sharedIndex` despacha `Methods` antes de `GetProperty`. Um item de enum
futuro chamado literalmente `GetEnumItems`/`FromName`/`FromValue` (ou um enum chamado `GetEnums`)
seria silenciosamente sombreado pelo método, ao contrário do caso `Name`/`Value` (que é seguro
por DESENHO, pois o objeto "Enum" nunca reserva essas chaves). Verifiquei contra o dump pinado:
não ocorre hoje. O cabeçalho já é honesto ("verificado nesta tarefa", não "garantido"), então não
é divergência silenciosa — só uma lacuna de defesa em profundidade.
Correção (opcional, não bloqueante): um teste/asserção no `generate-enums.luau` que aborta se
algum item colidir com os nomes de método reservados, do mesmo jeito que já aborta por
`Version ~= 1`.

## O que NÃO achei errado (verificado, não só lido)

Fábrica única respeitada (nenhum `newproxy` fora de `Userdata.luau`), imutabilidade (sem
`SetProperty`, correto para esta leva), estado em side-table não exposta, `__eq`/`__metatable`
herdados corretamente da fábrica já aprovada, construção preguiçosa e memoizada real (medida,
não só lida), internamento real (rawequal, múltiplos caminhos), mensagens de erro e nível 3
corretos e verificados por script independente, dump/commit/hash batendo exatamente, contagens
629/3611/283 batendo contra o dump cru (não só contra o spec do coder), zero vazamento de escopo,
`Catalog.luau`/`Catalog.spec.luau` exatamente como alegado.

## Veredito

**APROVADO COM RESSALVAS.** Nenhum achado GRAVE (fábrica/território/mutabilidade intactos). Um
ALTO real (violação de regra "sem exceção" de `any` em teste, evitável e evitada em todo o resto
do território na mesma leva) que deveria virar tarefa de correção antes de fechar a leva 40; um
MÉDIO de documentação (gap real vs. estimativa não reconciliado, self-report impreciso nesse
ponto específico); um BAIXO de robustez futura, não bloqueante.
