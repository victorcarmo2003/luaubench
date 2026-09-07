# Rojo: aplicação de `$properties` vs Security.Read/Write e vs Serialization.CanLoad/CanSave

**Escopo:** task-cli-037. Não repete a investigação de causa raiz no LuauBench (já confirmada). Só responde, com fonte, como o Rojo REAL se comporta.

**Versões verificadas** (mesma fixação já usada em `pesquisa-formato-projeto-rojo-2026-09-05.md`):
- Rojo `v7.7.0` — binário real testado (`C:\Users\hakor\.rokit\bin\rojo.exe`, resolvido via `rokit.toml` do projeto `Tiktok`, que fixa `rojo-rbx/rojo@7.7.0`) e código-fonte baixado do tag `v7.7.0` (`src/project.rs` reaproveitado do scratch da pesquisa anterior — `diff` contra o arquivo já usado em 2026-09-05 deu vazio, ou seja, é a mesma leitura; `src/resolution.rs` baixado agora do mesmo tag).
- `rbx_reflection` `v7.0.0` e `rbx_reflection_database` `v3.0.0+roblox-728` — versões EXATAS que o `Cargo.lock` do Rojo `v7.7.0` fixa (`Cargo.lock` linha 1831-1846, baixado do tag `v7.7.0`). Baixei `rbx_reflection/src/database.rs` e `property_tag.rs` de `rojo-rbx/rbx-dom@master` e confirmei por `diff` byte-a-byte contra o tag exato `rbx_reflection-v7.0.0` — **idênticos**, então não há deriva de versão entre o que li e o que o Rojo 7.7.0 realmente embute.
- Plugin do Rojo (lado Lua/Studio, usado por `rojo serve`) — mesmo tag `v7.7.0`, arquivos `plugin/src/Reconciler/setProperty.lua` e `plugin/rbx_dom_lua/PropertyDescriptor.lua`.

## Resposta curta

**Pergunta 1 — CONFIRMADA, por código-fonte E por teste empírico reproduzido:** `rojo build` (o caminho que o `TreeMaterializer` do LuauBench precisa espelhar) é um caminho de **deserialização direto no DOM que nunca consulta Security/Scriptability**. O código que resolve e aplica `$properties` (`src/resolution.rs` + `src/snapshot_middleware/project.rs`) só enxerga o TIPO da propriedade (`DataType`) para validar o JSON e a EXISTÊNCIA do nome na hierarquia de classes — o campo `scriptability` (o equivalente do `Security.Read`/`Security.Write` do dump) nunca é lido nesse caminho. Isso é estruturalmente idêntico a como o engine real carrega um `.rbxl` (hidratação de estado, não é "script escrevendo") — só que no caso do `rojo build` é mais extremo ainda: não existe motor Lua nenhum envolvido, é um binário Rust puro escrevendo direto numa struct `rbx_dom_weak::WeakDom`.

Só o **plugin** (`rojo serve`, sync ao vivo dentro do Studio) tem um mecanismo DIFERENTE que verifica `scriptability` — mas é um segundo eixo (Scriptability, não Security propriamente) e mesmo assim é só um guard client-side antes de fazer uma escrita real (`instance[prop] = value`) na própria Instance do Studio, cujo sucesso/falha final é decidido pelo motor real (identidade/capacidade do plugin), não pelo código do Rojo. Isso não é o caminho que o LuauBench precisa reproduzir (o `TreeMaterializer` do LuauBench é offline/batch, equivalente ao `rojo build`, não ao plugin ao vivo).

**Pergunta 2 — CONFIRMADA, por código-fonte E por teste empírico reproduzido:** `Serialization`/`CanLoad`/`CanSave` (no dump interno do rbx_reflection isso é `PropertyKind::Canonical { serialization: PropertySerialization }`) **nunca é consultado em nenhum dos dois caminhos** (nem `rojo build`, nem o plugin) no momento de aplicar `$properties`. Não há skip-com-aviso nem erro fatal — a propriedade é escrita normalmente, como qualquer outra. `Workspace.FilteringEnabled` (que no `Full-API-Dump.json` usado pelo LuauBench tem `Serialization={CanLoad:false,CanSave:false}` e `Tags=[Hidden,NotReplicated,Deprecated]`) foi escrita com sucesso total, sem nenhum aviso, no teste empírico abaixo.

## Fatos verificados

### 1. Teste empírico reproduzido — `rojo build` real contra o template `rojo init` (`Tiktok`)

Comando executado (read-only quanto ao projeto `Tiktok` — output foi para o scratchpad, `default.project.json` nunca foi editado):

```
cd C:\Users\hakor\Documents\Roblox-Games\Tiktok
rojo build default.project.json -o <scratch>/tiktok-build.rbxlx -vv
```

Resultado:
- `rojo --version` → `Rojo 7.7.0` (resolvido pelo `rokit.toml` do próprio projeto `Tiktok`, que fixa `rojo-rbx/rojo@7.7.0` — mesma versão já usada na pesquisa de 2026-09-05).
- **Exit code 0**, build bem-sucedido, mesmo em `-vv` (nível `TRACE`, o mais verboso que o Rojo tem) — nenhuma linha de log menciona `Technology`, `FilteringEnabled`, `Security` ou `Serialization`. Nenhum warning, nenhum erro.
- Inspecionei o `.rbxlx` (XML) resultante diretamente (não é binário opaco — dá pra grepar texto):
  ```xml
  <!-- dentro do Item Lighting -->
  <token name="Technology">1</token>

  <!-- dentro do Item Workspace -->
  <bool name="FilteringEnabled">true</bool>

  <!-- dentro do Item SoundService -->
  <bool name="RespectFilteringEnabled">true</bool>
  ```
  As três propriedades do `.project.json` original do `Tiktok` (`Lighting.Technology="Voxel"` → token 1, `Workspace.FilteringEnabled=true`, `SoundService.RespectFilteringEnabled=true`) foram materializadas com sucesso total no DOM de saída.

Isso é evidência direta e reprodutível: o binário real do Rojo, na versão fixada pelo próprio projeto de referência, aceita e aplica sem erro/aviso tanto uma propriedade com `Security.Read=Security.Write=RobloxScriptSecurity` (`Technology`) quanto uma com `Serialization.CanLoad=CanSave=false` e `Tags=[Hidden,NotReplicated,Deprecated]` (`FilteringEnabled`).

### 2. Por que isso acontece — código-fonte do resolvedor (`src/resolution.rs`, tag `v7.7.0`)

- `find_descriptor(class_name, prop_name)` (linhas 294-309): sobe a cadeia de superclasses do `rbx_reflection_database` procurando **só pelo nome** da propriedade (`class.properties.get(prop_name)`). Não olha `scriptability`, não olha `tags`, não olha `kind`/`serialization` — só existência.
- `AmbiguousValue::resolve` (linhas 150 em diante) e `UnresolvedValue::resolve`/`resolve_unambiguous`: o único campo do `PropertyDescriptor` consultado depois de achar o descriptor é `property.data_type` (`DataType::Enum(...)` vs `DataType::Value(VariantType)`), usado só para casar o JSON (`AmbiguousValue::Bool`/`Number`/`String`/etc.) com o tipo esperado e converter pra `Variant`. Não há nenhuma referência a `scriptability`, `security` ou `serialization`/`canload` em todo o arquivo (`grep -i "scriptab\|security"` no arquivo baixado não retornou nada).

### 3. Por que isso acontece — código-fonte de quem aplica no nó da árvore (`src/snapshot_middleware/project.rs`, tag `v7.7.0`, mesmo arquivo já lido em 2026-09-05)

Loop que aplica `$properties` de cada nó (linhas 234-260, verbatim relevante):

```rust
for (key, unresolved) in &node.properties {
    let value = unresolved.clone().resolve(&class_name, key)...?;

    match key.as_str() {
        "Name" | "Parent" => {
            log::warn!("Property '{}' cannot be set manually, ignoring. ...", key, ...);
            continue;
        }
        _ => {}
    }

    properties.insert(*key, value);
}
```

- O **único** caso especial hardcoded é `"Name"`/`"Parent"` — por razões estruturais óbvias (nome e pai são geridos pela árvore do projeto, não por `$properties`), com um `log::warn!` e `continue` (skip não-fatal).
- Qualquer outra chave, depois de resolvida por tipo (seção 2), é inserida direto em `properties: HashMap<Ustr, Variant>` **sem nenhuma outra checagem**. Nem `Security`, nem `Serialization`/`CanLoad`, nem `Tags` (`Deprecated`/`Hidden`/`NotReplicated`) entram nessa decisão — confirmado por `grep -i "security\|scriptab\|serializ\|canload"` no arquivo inteiro: zero ocorrências fora dos comentários sobre reserialização de patch (que é sobre "quando precisa regravar o arquivo de projeto", não sobre elegibilidade de propriedade).

### 4. O que `Scriptability`/`Serialization` REALMENTE são no `rbx_reflection` (fonte: `rbx_reflection/src/database.rs`, tag `rbx_reflection-v7.0.0` — idêntico ao `master` atual, `diff` deu vazio)

```rust
pub struct PropertyDescriptor<'a> {
    pub name: &'a str,
    pub scriptability: Scriptability,   // linha 155 -- equivalente ao Security do dump, MAS COLAPSADO
    pub data_type: DataType<'a>,        // linha 158 -- único campo usado por resolution.rs
    pub tags: HashSet<PropertyTag>,     // linha 162 -- Deprecated/Hidden/NotReplicated/etc; nunca lido na aplicação
    pub kind: PropertyKind<'a>,         // linha 165 -- contém PropertySerialization (CanLoad/CanSave)
}

pub enum Scriptability {   // linhas 238-256, doc: "Defines how Lua can access a property, if at all."
    None, ReadWrite, Read, Write, Custom,
}

pub enum PropertySerialization<'a> {   // linhas 197-214
    Serializes, DoesNotSerialize, SerializesAs(&'a str), Migrate(PropertyMigration<'a>),
}
```

- `Scriptability` é a forma como o `rbx_reflection` **resume** o `Security.Read`/`Security.Write` granular do dump da Roblox (`None`/`LocalUserSecurity`/`PluginSecurity`/`RobloxScriptSecurity`/`RobloxSecurity`) num enum de 5 valores só sobre "dá pra Lua ler/escrever ou não" — não preserva QUAL nível de segurança era exigido. Esse campo existe na base de dados, mas **nenhum código do `rojo build`/`resolution.rs`/`project.rs` o lê**.
- `PropertySerialization` é o equivalente ao `Serialization.CanLoad`/`CanSave` do dump. Também existe na base, também **nunca é lido** pelo caminho de aplicação de `$properties`.
- `PropertyTag` (`property_tag.rs`, tag `v7.7.0`, idêntico ao master): `Deprecated | Hidden | NotBrowsable | NotReplicated | NotScriptable | ReadOnly | WriteOnly` — bate exatamente com os `Tags` do `Full-API-Dump.json` que o LuauBench usa. Também presente na base, também nunca consultado por `resolution.rs`/`project.rs`.

Conclusão da seção: os TRÊS eixos (Scriptability, Serialization, Tags) existem na base de reflection que o Rojo embute, mas **o caminho de aplicação de `$properties` do `rojo build` não consulta nenhum dos três** — só usa `data_type` pra validar forma, e a existência do nome pra validar que a propriedade existe. Isso bate 100% com o resultado empírico da seção 1.

### 5. O caminho do PLUGIN (`rojo serve`, sync ao vivo) é DIFERENTE — não é o que o LuauBench precisa espelhar, mas documentado por completude

Fonte: `plugin/src/Reconciler/setProperty.lua` (tag `v7.7.0`):

```lua
local function setProperty(instance, propertyName, value)
    local descriptor = RbxDom.findCanonicalPropertyDescriptor(instance.ClassName, propertyName)
    if descriptor == nil then
        Log.trace("Skipping unknown property ...")
        return true
    end

    if descriptor.scriptability == "None" or descriptor.scriptability == "Read" then
        return false, Error.new(Error.UnwritableProperty, {...})
    end

    local writeSuccess, err = descriptor:write(instance, value)
    if not writeSuccess then
        if err.kind == RbxDom.Error.Kind.Roblox and err.extra:find("lacking permission") then
            return false, Error.new(Error.LackingPropertyPermissions, {...})
        end
        return false, Error.new(Error.OtherPropertyError, {...})
    end
    return true
end
```

E `plugin/rbx_dom_lua/PropertyDescriptor.lua`, método `write`:
```lua
function PropertyDescriptor:write(instance, value)
    if self.scriptability == "ReadWrite" or self.scriptability == "Write" then
        local success, err = xpcall(set, debug.traceback, instance, self.name, value)
        -- set(container, key, value) = "container[key] = value" (atribuição Lua literal)
        ...
    end
    ...
end
```

- Aqui SIM existe uma checagem de `scriptability` (linha "if `descriptor.scriptability == "None"` or `"Read"`... return false, Error.UnwritableProperty") — mas é um guard client-side sobre o eixo `Scriptability` (não sobre `Security` granular), e serve só pra dar um erro limpo e recuperável (`Error.UnwritableProperty`/`Error.LackingPropertyPermissions`) em vez de deixar a atribuição Lua estourar sem contexto.
- A escrita de fato (`container[key] = value`) é uma **atribuição Lua real dentro da própria Instance do Studio**, rodando no contexto de execução do PLUGIN (que tem identidade/capacidade mais alta que um `Script`/`LocalScript` comum). Se o motor real rejeitar por falta de permissão, o erro Lua é capturado via `xpcall` e reclassificado como `Error.LackingPropertyPermissions` (str match em `"lacking permission"`) — de novo, um erro limpo, não um crash.
- **Não testável aqui sem uma sessão real do Studio** — não afirmo se um plugin consegue ou não escrever `Lighting.Technology`/`Workspace.FilteringEnabled` na prática (isso depende da capacidade real que a Roblox concede a Plugins para propriedades `RobloxScriptSecurity`, que é um fato sobre o motor da Roblox, não sobre o Rojo). Fica marcado como **incerto/não verificado** — mas também **irrelevante para a decisão do LuauBench**, porque o `TreeMaterializer` do LuauBench é o análogo direto do `rojo build` (processamento batch de `.project.json` → DOM em memória, sem motor, sem Lua "ao vivo"), não do plugin.
- Também não há, nesse caminho do plugin, nenhuma checagem de `Serialization`/`CanLoad`/`PropertyTag` — mesma conclusão da seção 4.

## Exemplo mínimo (reprodução)

```bash
# resolve rojo 7.7.0 via rokit.toml do próprio projeto Tiktok
cd C:\Users\hakor\Documents\Roblox-Games\Tiktok
rojo build default.project.json -o out.rbxlx -vv
grep -n "Technology\|FilteringEnabled" out.rbxlx
# -> <token name="Technology">1</token>
# -> <bool name="FilteringEnabled">true</bool>
```

## Limites e pegadinhas

- **Achado principal para a decisão do `arquiteto`/`coder-services`+`coder-cli`**: a causa raiz já identificada no LuauBench (`classifySchemaMember` misturando `Security` como gate de existência no schema) diverge do Rojo real em DOIS pontos, não um: (1) o Rojo real nunca usa `Security`/`Scriptability` para decidir se uma propriedade pode vir de `$properties` — só usa o TIPO; (2) o Rojo real também nunca usa `Serialization.CanLoad`/`CanSave` pra esse fim. Ou seja, a hipótese do achado ("dois eixos diferentes, hoje misturados em um só") está correta, mas o eixo certo pro caminho de carga de projeto não é "usar `Serialization.CanLoad` como gate" — o Rojo real **não usa gate nenhum** nesse caminho, além de checar que a propriedade existe e que o JSON bate com o tipo. Isso é uma informação importante pro redesenho: fidelidade total ao Rojo real significaria **não ter Security nem Serialization como bloqueio na materialização de `$properties`** — só validação de nome+tipo.
- Isso não quer dizer que o LuauBench deva ignorar `Security` para TODO uso — `Security` continua relevante pro caminho de **script em runtime lendo/escrevendo** (`instance.Foo = x` dentro de um `Script`/`ModuleScript` do projeto do usuário), que é um caminho diferente do `$properties` de projeto. É exatamente essa distinção de dois caminhos (carga de arquivo de projeto vs. escrita de script em runtime) que o achado original já apontou — a pesquisa aqui confirma que o Rojo real trata esses dois caminhos com regras totalmente diferentes (o de carga de projeto não tem NENHUM gate de segurança; o de script real do Roblox, fora do escopo do Rojo, obviamente tem).
- `Workspace.FilteringEnabled` é hoje, na prática, sempre `true` em jogos modernos (Roblox tornou FilteringEnabled obrigatório desde ~2018) — isso pode explicar por que a Roblox nunca se preocupou em bloquear essa propriedade especificamente no dump/reflection para ferramentas de build, mesmo estando marcada `CanLoad=false`/`Deprecated` no dump vivo. Isso é inferência minha sobre o "porquê" histórico, não fato verificado — não veio de nenhuma fonte primária lida nesta pesquisa.
- O template usado (`rojo init` padrão, presente literalmente em `Tiktok/default.project.json`) prova que esse NÃO é um caso de borda raro — é o comportamento de todo projeto Rojo novo. Reforça a prioridade alta da task.

## Incerto

- Se um Plugin real do Studio (`rojo serve` ao vivo) consegue de fato escrever `Lighting.Technology`/`Workspace.FilteringEnabled` sem erro de permissão — depende da capacidade real que a Roblox concede a plugins pra propriedades `RobloxScriptSecurity`/`PluginSecurity`, um fato do motor da Roblox que não dá pra confirmar sem uma sessão real do Studio (fora do escopo de pesquisa sem-Studio deste ambiente). Não afeta a decisão do LuauBench porque o `TreeMaterializer` espelha o caminho `rojo build`, não o plugin.
- Não abri o gerador da `rbx_reflection_database` (o script que converte o dump oficial da Roblox pro banco de dados compilado que o `rbx_reflection_database` crate embute) pra confirmar SE `Scriptability`/`PropertySerialization` são derivados 1:1 de `Security`/`Serialization` do `Full-API-Dump.json`, ou se passam por alguma correção manual. Não era necessário pra responder as duas perguntas (o fato relevante é que esses campos, deriving de onde vierem, simplesmente não são lidos na aplicação de `$properties`), mas fica marcado como não verificado caso surja dúvida sobre a correspondência exata de valores no futuro.
