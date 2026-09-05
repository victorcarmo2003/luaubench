# Revisão — task-valuetypes-006 (types/CFrame.luau)

Revisor: `revisor-valuetypes`, read-only. Nenhum self-report do coder foi aceito sem reprodução
própria — tudo abaixo foi rodado de verdade nesta sessão (`lune run` + scripts descartáveis de
scratchpad, removidos ao final; `git status` confirma território limpo).

## Veredito

**APROVADO**

Nenhum achado GRAVE ou ALTO. Um achado BAIXO (não bloqueante, ver item 11).

## Evidência reproduzida

### 1. Suíte completa — 10 specs, números exatos

```
Float32.spec.luau      10/10
Userdata.spec.luau     33/33
Catalog.spec.luau      15/15  (inclui o teste de coerência que varre types/ via fs.readDir e
                                falharia se CFrame.luau existisse com Simulated=false)
Vector3.spec.luau      42/42
Vector2.spec.luau      38/38
Color3.spec.luau       24/24
UDim.spec.luau         17/17
UDim2.spec.luau        24/24
Enum.spec.luau         30/30
CFrame.spec.luau       63/63
--------------------------------
TOTAL                  296/296
```

Bate exatamente com o self-report do coder (63/63 CFrame, 296/296 total). `luau-lsp analyze` sobre
`CFrame.luau`/`CFrame.spec.luau` não reporta nenhum erro/warning.

### 2. Seis overloads de `CFrame.new` — testados independentemente (script próprio, fora do spec do coder)

0 args (identidade 0,0,0,1,0,0,0,1,0,0,0,1) · 1 arg (posição pura, rotação = identidade) · 2 args
(position+lookAt, LookVector aponta pro alvo) · 3 args (x,y,z sem rotação) · 7 args (quaternion
identidade E quaternion 180° em X → UpVector ~(0,-1,0), confere) · 12 args (matriz explícita) —
todos corretos.

### 3. Operadores

`*CFrame`, `*Vector3`, `+Vector3`, `-Vector3` produzem resultado correto. `CFrame+CFrame`,
`CFrame-CFrame`, `CFrame*number` e `number*CFrame` **erram** (testado com `pcall`, os 4 casos).

### 4. Round-trip

`cf * cf:Inverse()` ~ identidade (erro < 1e-4). `cf:ToWorldSpace(cf:ToObjectSpace(other))` ~
`other`. Ambos confirmados com CFrames não triviais (rotação + translação compostas).

### 5. `Lerp` — slerp real, não linear ingênuo

`Lerp(0)`/`Lerp(1)` devolvem os extremos. `Lerp(0.5)` entre identidade e rotação de 90° em Z produz
exatamente `cos(45°), -sin(45°)` nos componentes R00/R01 da matriz — **provado numericamente
diferente** do que uma média linear ingênua da matriz daria (R00=0.5, R01=-0.5 vs. o real
R00≈0.7071, R01≈-0.7071, diferença > 0.1 em ambos). Confirma slerp de quatérnion de verdade.

### 6. `GetComponents`/`tostring`

12 valores, ordem `x,y,z,R00,R01,R02,R10,R11,R12,R20,R21,R22` confirmada com matriz assimétrica
(`CFrame.new(1,2,3,4,5,6,7,8,9,10,11,12)` → `GetComponents()` devolve exatamente essa sequência).
`tostring` produz a mesma sequência formatada (`"1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12"`).

### 7. `Orthonormalize`

Construída deliberadamente uma matriz não-ortonormal via `fromMatrix` com `vX=(3,0,0)` (não
unitário) e `vY=(2,1,0)` (não ortogonal a `vX`). Pré-condição confirmada (RightVector com
Magnitude=3, não 1). Depois de `:Orthonormalize()`: os três vetores de coluna têm Magnitude ~1 e
produto interno ~0 dois a dois (testado os 3 pares). Corrige de fato.

### 8. Fábrica única

`grep newproxy src/valuetypes/` — a única chamada real (`local proxy = newproxy(true)`) está em
`Userdata.luau:304`. Todas as outras ocorrências em `CFrame.luau`/`Vector3.luau`/`Enum.luau` são
comentários explicando a decisão, não chamadas. `CFrame.luau` não chama `newproxy` diretamente.

### 9. Strict/any

`--!strict` na primeira linha de `CFrame.luau` e `CFrame.spec.luau`. Buscas por `\bany\b` só batem
em comentários que dizem explicitamente "sem `any`" — zero uso real do tipo.

### 10. Território

`grep -rn valuetypes src/runtime/` — vazio. `git status`/`git diff --stat` mostram exatamente os 3
arquivos esperados tocados pela tarefa (`Catalog.luau` modificado, `CFrame.luau`/`CFrame.spec.luau`
novos) — `src/services/`, `src/cli/`, `tools/` intocados.

Nota à parte (não é achado desta tarefa): `.claude/tasks.json` também aparece no diff, mas as
únicas duas linhas alteradas são o `column` de `task-services-017` e `task-services-028` (de `todo`
para `in-progress`) — não têm relação com `task-valuetypes-006` e são presumivelmente de outra
orquestração rodando em paralelo em outro território. `task-valuetypes-006` continua sem `result`/
`reviewResult` gravado no board (o coder não fechou o board ainda) — isso é hygiene de board, não
um problema de código.

### 11. Escopo declarado (não implementado): `fromRotationBetweenVectors`, `fromEulerAngles`/`ToEulerAngles` genéricos com `Enum.RotationOrder`

**BAIXO, não bloqueante.** A lista pedida literalmente pelo `acceptance`/descrição da task
(`lookAt/lookAlong/fromMatrix/fromAxisAngle/fromEulerAnglesXYZ/fromEulerAnglesYXZ/Angles/
fromOrientation`) foi cumprida **integralmente** — os três itens de fora não estavam pedidos. Isso
não é bloqueante por instrução explícita do orquestrador.

Ressalva sobre a justificativa dada no cabeçalho do código ("importar `Enum` aqui criaria
acoplamento não desenhado, módulo é de outra tarefa"): verifiquei que `types/Enum.luau` **já existe
e está completo** (`task-valuetypes-003`, mesma leva 40, mesmo território `src/valuetypes/`) — não
é uma tarefa pendente nem um território estranho, é um módulo irmão já pronto no mesmo diretório.
`Enum.RotationOrder` também já está em `generated/EnumData.luau` (confirmado via grep). Ou seja, o
"acoplamento não desenhado" citado é mais fraco do que soa: seria acoplamento *intra-território*
entre dois módulos-folha do mesmo diretório, não uma dependência cruzando pra `runtime`/`services`/
`cli`. A decisão de não implementar é razoável (não foi pedido, e feature extra não pedida é
trabalho a mais sem tarefa/teste dedicado), mas o texto do comentário deveria dizer "não foi pedido
pela task" em vez de sugerir uma barreira arquitetural que não existe mais no momento em que o
código foi escrito. Não corrigi (sou read-only) — reportando para quem for revisar/editar o
cabeçalho depois, se achar que vale a pena.

### 12. Convenção de mão/eixo (right-handed, Y-up)

`CFrame.Angles(0, math.rad(90), 0) * Vector3.new(1,0,0)` devolveu `(~0, 0, -1)`. Confere com a
matriz padrão de rotação em Y right-handed (`Ry(θ)·(1,0,0) = (cosθ, 0, -sinθ)`, em θ=90° dá
`(0,0,-1)`), e é consistente com `LookVector = (0,0,-1)` na identidade (citado literalmente pela
pesquisa, `pesquisa-datatypes-vector-cframe-2026-09-05.md` §3) e com `RightVector=(1,0,0)`/
`UpVector=(0,1,0)`. `fromAxisAngle` (Rodrigues) e `fromEulerAnglesXYZ`/`Angles` produzem o mesmo
resultado entre si (já coberto pelo spec do coder e reconfirmado aqui) — convenção internamente
consistente e alinhada à convenção real do Roblox (right-handed, Y-up, -Z "para frente").

### Invariantes gerais de userdata (checadas especificamente em CFrame, não só herdadas de Userdata.spec.luau)

`setmetatable(cf, {})` erra nativamente. `pairs(cf)` erra nativamente. `getmetatable(cf)` devolve a
string travada (`"The metatable is locked"`), nunca a metatable real. `cf == 5` e `cf == "x"`
devolvem `false` sem erro (o Luau nem chama `__eq` entre tipos incompatíveis).

## O que NÃO foi encontrado (verificado, não presumido)

- Nenhuma segunda fábrica de userdata.
- Nenhum vazamento de `valuetypes` para `runtime`.
- Nenhuma mutabilidade não declarada.
- Nenhum `any` real.
- Nenhuma divergência silenciosa — D1/D7/P1/P8 documentadas no cabeçalho do código, conferem com o
  que a pesquisa confirmou vs. o que é aproximação de boa-fé.
