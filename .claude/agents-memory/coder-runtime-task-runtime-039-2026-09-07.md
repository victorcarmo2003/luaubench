# task-runtime-039 — MemberDescriptor.ScriptVisible

**Data:** 2026-09-07
**Território:** `src/runtime/` (só `Instance.luau`, `Instance.spec.luau`; `init.luau` recebeu só uma entrada no changelog de cabeçalho, sem mudança de código/tipo).

## O que foi feito

1. **`MemberDescriptor` (Instance.luau:96-133)** ganhou o campo `ScriptVisible: boolean?`, aditivo puro: `nil`/`true` = comportamento de hoje (visível ao script); `false` = membro existe estruturalmente na classe mas é invisível ao script. Comentário documenta a correspondência 1:1 com `rbx_reflection::Scriptability` (`None→false`, `Read→true+ReadOnly=true`, `ReadWrite→true+false`) e explica por que o nome é `ScriptVisible` (eixo de EXISTÊNCIA) e não `ScriptAccessible` (`ReadOnly` já é o eixo de ESCRITA).

2. **`InstanceMeta.__index`, passo 5** (Instance.luau ~658-674): resolve o descritor e trata `descriptor.ScriptVisible == false` como se `classSchema[key]` fosse `nil`. Resto do caminho (passo 7 — resolução de filho por nome; passo 8 — erro `"is not a valid member of"`) intocado.

3. **`InstanceMeta.__newindex`, passos 7/8** (Instance.luau ~786-800): mesma neutralização — `local descriptor: MemberDescriptor? = classSchema[key]`, zerado para `nil` se `ScriptVisible == false`, caindo no mesmo ramo de erro do passo 8. (Precisou anotar o tipo `MemberDescriptor?` explicitamente na declaração local para permitir a reatribuição a `nil` em `--!strict` — sem isso o checker infere o tipo não-opcional a partir da primeira atribuição.)

4. **`Instance.SetClassSchema`** (Instance.luau ~1085-1145):
   - Validação de forma: `ScriptVisible` aceita `boolean` ou `nil`; qualquer outro tipo erra com `"Instance.SetClassSchema: ScriptVisible de '{key}' precisa ser boolean ou nil, recebeu {tipo}"` (mesma família de `Kind`/`ReadOnly`).
   - Semeadura: `for key, descriptor in schema` agora pula (`continue`) entradas com `descriptor.ScriptVisible == false` — não grava `Default` nem cria `Signal.new()` para elas.

5. **`init.luau`**: só um parágrafo novo no changelog de cabeçalho (mesmo padrão da entrada de task-runtime-032) explicando que `MemberDescriptor` ganhou o campo via o alias existente, sem export novo.

## API pública exposta

- `Runtime.MemberDescriptor.ScriptVisible: boolean?` (via `export type MemberDescriptor = InstanceModule.MemberDescriptor` em `init.luau`, propagado estruturalmente).
- Nenhuma função nova. `GetPropertyRaw`/`SetPropertyRaw` (já públicas) continuam sendo a única via que ignora o schema por completo — confirmado por teste que elas seguem funcionando sobre uma chave `ScriptVisible == false`.

## Fidelidade

- Correspondência 1:1 com `rbx_reflection::Scriptability`, documentada no tipo — cross-check com a pesquisa `.claude/agents-memory/pesquisa-rojo-properties-security-2026-09-07.md`.
- Neutralidade observável é NEUTRALIDADE DE VERDADE, não aproximação: prova por igualdade de string byte-a-byte (não só `string.find`) entre o erro de uma chave `ScriptVisible=false` e o erro de uma chave ausente, usando duas instâncias com mesmo `ClassName`/`Name` e funções `pcall` compartilhadas (mesma linha de source, já que `error(msg, 2)` embute o `arquivo:linha` do site de chamada — comparar direto duas closures inline em linhas diferentes teria dado falso-negativo por causa só do prefixo de localização, não do conteúdo da mensagem; corrigido usando uma função helper única chamada duas vezes).

## Testes

`lune run` em todas as 9 specs de `src/runtime/`:

```
ClassRegistry.spec.luau   33/33
DataModel.spec.luau       29/29
Instance.spec.luau        70/70  (64 pré-existentes intactas + 6 novas)
Integration.spec.luau      9/9
Sandbox.spec.luau         25/25
Scheduler.spec.luau       16/16
Signal.spec.luau           8/8
TypeNameResolver.spec.luau 4/4
init.spec.luau             7/7
```

6 testes novos em `Instance.spec.luau` (bloco "Testes NOVOS da task-runtime-039", logo após os testes de task-runtime-018 e antes dos de task-runtime-027):

1. `ScriptVisible=false: leitura e escrita erram com a MESMA string, byte-a-byte, que uma chave ausente do schema produziria` — cobre (a) e (b) do aceite.
2. `ScriptVisible=false: existindo um FILHO com o mesmo nome, a leitura devolve o filho` — cobre (c).
3. `ScriptVisible=false: GetPropertyRaw/SetPropertyRaw continuam funcionando sobre a chave invisível` — cobre (d).
4. `SetClassSchema NÃO semeia Default nem Signal para entrada ScriptVisible=false` — via `GetPropertyRaw` provando `data.properties[key] == nil` para uma `Property` com `Default` não-nil e para um `Event`.
5. `SetClassSchema rejeita ScriptVisible que não é boolean nem nil`.
6. `ScriptVisible=true explícito é idêntico ao padrão (nil)` — reforço extra, não exigido literalmente pelo aceite mas fecha a alegação de "aditivo puro".

`makeSchema` (helper de teste) ganhou o campo opcional `ScriptVisible` — aditivo, nenhuma chamada existente precisou de edição (confirmado pelos 64 testes pré-existentes passando sem alteração).

Type-check: `luau-lsp analyze --platform=standard --settings=.luaurc` limpo (exit 0) em todos os arquivos do território, exceto `init.spec.luau` isolado, que já tem uma pendência de tooling PRÉ-EXISTENTE e documentada no próprio cabeçalho do arquivo (falso-positivo do `luau-lsp` 1.69.0 para qualquer arquivo cujo nome comece com `init`, nada a ver com esta tarefa — `lune run` nele passa 7/7). Zero uso de `any` (só a menção em comentário "nunca `any`").

## Pendências

Nenhuma dentro do escopo desta tarefa. Próximos passos do board (fora deste território): `task-services-035` (bifurcar `classifySchemaMember` para emitir `ScriptVisible`) e `task-cli-038` (hidratação de `$properties` via `SetPropertyRaw`), ambos dependentes desta.
