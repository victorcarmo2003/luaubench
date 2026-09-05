# Revisão — task-valuetypes-007 (Decode.luau + init.luau)

Data: 2026-09-05. Revisor: `revisor-valuetypes`, read-only. Todos os achados abaixo foram
reproduzidos pessoalmente (não é self-report do coder aceito sem verificação).

## Evidência reproduzida

1. **325/325 specs, exato.** Rodei os 12 specs do território um a um (`lune run`):
   `Catalog.spec.luau`=15, `Decode.spec.luau`=19, `Float32.spec.luau`=10, `Userdata.spec.luau`=33,
   `init.spec.luau`=10, `types/CFrame.spec.luau`=63, `types/Color3.spec.luau`=24,
   `types/Enum.spec.luau`=30, `types/UDim.spec.luau`=17, `types/UDim2.spec.luau`=24,
   `types/Vector2.spec.luau`=38, `types/Vector3.spec.luau`=42. Soma = 325. Baseline (10 specs
   antigos) = 296, exatamente como alegado. Todos exit 0, zero falha.

2. **Vector3 vs Color3 do mesmo array — tipos diferentes, confirmado.** Script próprio:
   `Decode.FromRojoJson("Vector3","DataType",{1,2,3})` → `Userdata.TypeNameOf` = `"Vector3"`;
   `Decode.FromRojoJson("Color3","DataType",{1,2,3})` → `"Color3"`. Não é só numericamente
   parecido — são tipos userdata distintos de verdade (fábricas diferentes).

3. Array de 12 → `CFrame` (tostring `"0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1"`); string `"Plastic"`
   com alvo `Material`/`Enum` → `EnumItem` real (`tostring` = `"Enum.Material.Plastic"`); item de
   enum inexistente (`"MaterialQueNaoExiste"`) → `DecodeFailure` com motivo legível, sem crash.

4. **5 formas inválidas testadas sem `pcall`, nenhuma crashou**: `raw=5` pra Vector3, array
   `{1,2}` (tamanho errado), `{1,"x",3}` (elemento não-numérico), `nil`, e `valueCategory="Group"`
   (não testada no spec, testei eu mesmo). Todas devolveram `DecodeFailure` com mensagem citando o
   problema específico. Confirmei também por `grep` que as únicas ocorrências de `pcall` em
   `Decode.luau`/`Decode.spec.luau` são comentários explicando a ausência deliberada — zero uso
   real.

5. **`BuildGlobals()` tabela nova a cada chamada**, confirmado por identidade (`g1 ~= g2`) e por
   não-vazamento (mutar `g1` não aparece em `g2`/terceira chamada). Chaves batem EXATAMENTE com
   `Catalog.SimulatedNames()` (7 nomes: CFrame, Color3, Enum, UDim, UDim2, Vector2, Vector3) —
   testei nos dois sentidos (nenhuma falta, nenhuma sobra).

6. **A guarda de sincronização em `BuildGlobals()` é código VIVO, não morto.** Como `Catalog`
   é congelado e `CONSTRUCTOR_BY_NAME` é upvalue privada, não dá pra forçar o caminho de fora sem
   editar arquivo — copiei o corpo exato da função para um arquivo temporário (apagado depois),
   removi a entrada `UDim2` de `CONSTRUCTOR_BY_NAME` mantendo o resto idêntico, e a chamada
   `error()` disparou de fato, citando `'UDim2'` corretamente. Não é comentário decorativo.

7. **`TypeNameOf` delega de verdade.** `ValueTypes.TypeNameOf(v) == Userdata.TypeNameOf(v)` para
   os 7 tipos (Vector3/Vector2/Color3/UDim/UDim2/CFrame/Enum) — testado par a par, sempre igual.
   Lendo o código, `ValueTypes.TypeNameOf` é uma função de uma linha que só chama
   `Userdata.TypeNameOf` — não reimplementa.

8. **Color3 em 0-1: decisão razoável, não deveria ter sido tratada como ambígua.** A evidência
   citada (`Lighting.Ambient=[0.5,0.5,0.5]` do `default.project.json` real) é anedótica sozinha,
   mas há um argumento mais forte que o próprio coder não citou: o formato de arquivo Roblox
   (`rbxlx`/`rbxm`) e o `rbx_dom_weak` (que o Rojo usa por baixo) armazenam `Color3` como floats
   `[0,1]` nativamente — é a representação canônica do datatype na serialização, não uma escolha
   de UI (0-255 é só exibição do Studio). Ou seja, a decisão bate com o mecanismo real, não é só
   um palpite sorte com um exemplo. Marcar como `DecodeFailure`/ambíguo seria pior: o `$properties`
   de qualquer projeto Rojo real com `Color3` pararia de funcionar por uma cautela desnecessária.
   Concordo com a decisão; sugiro só engrossar a citação de evidência no comentário (mencionar o
   formato de serialização do DOM, não só o exemplo do `default.project.json`) numa iteração
   futura — não bloqueia esta tarefa.

9. **Fábrica/contrato confirmado.** `init.luau` só atribui os módulos existentes
   (`ValueTypes.Vector3 = Vector3Module`, etc.) e define duas funções finas de composição
   (`BuildGlobals`, `TypeNameOf`) — nenhuma lógica de tipo é reimplementada. `services`/`cli`
   poderão fazer `require("../valuetypes")` sem tocar módulo interno (confirmado lendo os 7
   `require("./valuetypes/types/Xxx")` — todos ficam privados, só a superfície é reexportada).

10. **`--!strict` presente nos 4 arquivos** (`Decode.luau`, `Decode.spec.luau`, `init.luau`,
    `init.spec.luau`), confirmado por grep. **Zero `any` real** — as únicas 3 ocorrências da string
    `any` são comentários explicando o uso de `unknown`/vitrines tipadas para EVITAR `any` (ex.:
    "Vitrine tipada SEM `any` pra indexar...").

11. **Território limpo.** `git status`/`git diff --stat`: só os 4 arquivos esperados aparecem como
    novos em `src/valuetypes/`. `grep -r valuetypes src/runtime/` e `src/cli/` vazios (exit 1) —
    grafo acíclico intacto. Há mudanças não relacionadas em `src/services/generated/*`,
    `src/services/datastore/` e `tools/coverage.luau` (trabalho de outra tarefa, DataStore —
    `task-runtime-033`/afim, já em `done` no board) — não tocam `valuetypes`, fora do escopo desta
    revisão, sinalizado só por completude.

12. **Achado de tooling reproduzido de verdade, não é desculpa.** Rodei eu mesmo
    `require("./src/valuetypes/init")` de fora → erro real do Lune:
    `"could not resolve child component 'init' (ambiguous)"`. Trocando para
    `require("./src/valuetypes/")` → funciona normalmente. Mesmo padrão documentado no cabeçalho
    de `init.luau` (uso de `require("./valuetypes/Xxx")` em vez de `require("./Xxx")` de dentro do
    próprio arquivo, pelo deslocamento de base de resolução quando o chunk é carregado no "estilo
    diretório"). Consistente com o mesmo gotcha já registrado em `runtime`/`services`/`cli`.

## Achados

Nenhum GRAVE ou ALTO.

**BAIXO** `src/valuetypes/Decode.luau:147-176` (`asNumberArray`)
Problema: a contagem de "tamanho do array" usa `for key in asGeneric do length += 1 end`, que
conta QUALQUER chave numérica presente, não verifica que as chaves são contíguas `1..N`. Um `raw`
patológico como `{[2]=5,[3]=6,[4]=7}` (3 chaves numéricas, mas sem a chave `1`) passa a checagem de
tamanho (`length == expectedLength`) e só falha depois, no loop de elementos, quando
`asGeneric[1]` vem `nil`. O resultado final ainda é corretamente um `DecodeFailure` (nunca um
sucesso incorreto), só que a mensagem seria "elemento 1 é nil" em vez de identificar a causa raiz
mais precisa (índice ausente).
Cenário de falha: nunca alcançável via JSON real (o parser de `cli/JsonValue.luau` só produz
arrays contíguos `1..N`) — é um caminho teórico caso `Decode` seja chamado de outro lugar futuro
com uma tabela Luau montada à mão de forma não-contígua.
Correção: opcional, baixa prioridade — se quiser mensagem mais precisa, validar contiguidade
explicitamente. Não bloqueia a tarefa; contrato "nunca lança / nunca finge sucesso" está intacto.

**BAIXO** `src/valuetypes/Decode.luau` (cabeçalho, "Depende de")
Problema: o cabeçalho do módulo e a nota de dependências do desenho arquitetural (seção 3.1) dizem
que `Decode` depende de `Catalog.luau`, mas o `Decode.luau` real não importa `Catalog` em lugar
nenhum (usa `generated/EnumData` diretamente para o índice de nomes de enum, o que é correto e
até melhor — evita uma dependência desnecessária). É só documentação levemente desalinhada com o
desenho original, não um bug de comportamento.
Correção: nenhuma ação necessária; observação de cortesia caso o cabeçalho seja revisado depois.

## Veredito

## APROVADO
