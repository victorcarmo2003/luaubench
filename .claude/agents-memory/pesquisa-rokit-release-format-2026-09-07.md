# Pesquisa — formato de GitHub Release que o Rokit espera (2026-09-07)

**Fonte:** código-fonte real de [rojo-rbx/rokit](https://github.com/rojo-rbx/rokit), clonado via `git clone --depth 1` em 2026-09-07.
**Commit inspecionado:** `2f2618428ef31279e2fc80b0b1d73485bc929dd` (branch `main`, commitado 2026-05-09).
**Versão do Rokit correspondente:** `1.2.0` (de `Cargo.toml` raiz, linha `version = "1.2.0"` — não confirmado se é exatamente a versão publicada mais recente no momento do clone, mas é o HEAD de `main`).

Tudo abaixo vem do código-fonte real (arquivo:linha), não de doc de terceiros nem de generalização de outro projeto.

---

## 1. Formato do nome do asset zip — Rokit NÃO exige um "target triple" fixo

**Fato central:** Rokit não faz parsing estrito de um padrão de nome de arquivo. Ele varre **todos** os assets da release e tenta detectar OS + arquitetura por **busca de palavra-chave** (substring/full-word) dentro do nome do arquivo. Não existe formato único obrigatório — existe um vocabulário de palavras-chave reconhecidas.

### Onde isso acontece
- `lib/sources/artifact/mod.rs:161-197` (`sort_by_system_compatibility_inner`) — para cada asset, chama `Descriptor::detect(nome_do_asset)`; se retornar `None` (não conseguiu achar OS), o asset é descartado da lista de candidatos.
- `lib/descriptor/mod.rs:54-66` (`Descriptor::detect`) — chama `OS::detect` (obrigatório) e `Arch::detect` (opcional — pode ficar `None`).

### Palavras-chave de OS reconhecidas (`lib/descriptor/os.rs:9-23`)
```
Substring (basta aparecer em qualquer lugar do nome, case-insensitive):
  Windows -> "windows"
  MacOS   -> "macos", "darwin", "apple"
  Linux   -> "linux", "ubuntu", "debian", "fedora"

Palavra inteira (separada por "-"/"_"/etc, não pode ser substring de outra palavra):
  Windows -> "win", "win32", "win64"
  MacOS   -> "mac", "osx"
  Linux   -> (nenhuma além das substrings acima)
```

### Palavras-chave de arquitetura reconhecidas (`lib/descriptor/arch.rs:10-25`)
```
Substring:
  Arm64 -> "aarch64", "arm64", "armv9"
  X64   -> "x86-64", "x86_64", "amd64", "win64", "win-x64"
  Arm32 -> "arm32", "armv7"
  X86   -> "i686", "i386", "win32", "win-x86"

Palavra inteira:
  X64   -> "x64", "win"
  Arm32 -> "arm"
  X86   -> "x86"
```
- Se **nenhuma** arquitetura for detectada, `arch` fica `None` — o asset ainda é aceito (macOS "universal" cai nesse caso e vira `X64` via regra especial, `arch.rs:89-104`).
- Extensão do arquivo tem que ser uma das reconhecidas para o formato ser identificado: `zip`, `tar`, `gz`, `tgz`, `xz`, `txz`, com até 2 segmentos de extensão (cobre `.tar.gz`/`.tar.xz`) — `lib/sources/artifact/util.rs:3-4`.

### Convenção real usada pelo próprio Rokit (dogfooding, não é obrigação — é o padrão de fato do ecossistema)
Confirmado em `.github/workflows/release.yaml:53-81` e `scripts/zip-release.sh`:
```
rokit-<version>-windows-x86_64.zip
rokit-<version>-windows-aarch64.zip
rokit-<version>-linux-x86_64.zip
rokit-<version>-linux-aarch64.zip
rokit-<version>-macos-x86_64.zip
rokit-<version>-macos-aarch64.zip
```
Padrão: `<nome-do-repo>-<versão-sem-v>-<os>-<arch>.zip`. `<os>` usa exatamente `windows`/`linux`/`macos`; `<arch>` usa `x86_64`/`aarch64`. Isso é o padrão testado nos próprios testes unitários do Rokit (`lib/descriptor/os.rs:180-199`, `arch.rs:222-245` — casos reais incluem `lune-0.6.7-windows-aarch64`, `darklua-linux-aarch64`, `rojo-0.6.0-alpha.1-win64`).

**Não confirmado / não existe:** não há suporte ou exigência de "target triple" completo estilo Rust (`x86_64-pc-windows-msvc`) — funciona por acaso porque contém as substrings certas (`x86_64`, `windows`), mas Rokit não exige esse formato nem o reconhece como unidade.

### Plataformas/arquiteturas esperadas por convenção
- **OS:** Windows, macOS, Linux (`lib/descriptor/os.rs:30-34`, enum `OS` com apenas essas 3 variantes — `#[non_exhaustive]`).
- **Arch:** `Arm64` (aarch64), `X64` (x86_64, default quando arch não detectada — `arch.rs:38-40`), `Arm32` (arm/armv7), `X86` (i686/i386/win32).
- Compatibilidade cruzada especial (`lib/descriptor/mod.rs:117-133`):
  - Windows x64 roda binário x86.
  - Linux x64 roda binário x86.
  - macOS Apple Silicon (arm64) roda binário x64 (via Rosetta) **como fallback**, mas nativo arm64 é sempre preferido quando existe (`sort_by_preferred_compat`, `mod.rs:145-166`).

### O que acontece se faltar uma plataforma
Confirmado em `src/util/artifacts.rs:9-42` (`find_most_compatible_artifact`, chamado pelo CLI ao instalar): se nenhum asset compatível com o sistema atual for encontrado (nem por match exato, nem pela heurística de fallback parcial), o erro é **por usuário/plataforma**, não global:
```rust
artifact_opt.with_context(|| format!("No compatible artifact found for {tool_id}"))
```
Ou seja: se você publicar só o build Windows, usuários Windows instalam normalmente; usuários macOS/Linux recebem um erro claro "No compatible artifact found for victorcarmo2003/luaubench" ao rodar `rokit add`/`rokit install` — **não quebra a instalação de quem está na plataforma coberta**.

---

## 2. O que precisa estar DENTRO do zip

**Resposta curta: só o binário. Nada mais.**

Confirmado de duas formas independentes:

### a) O script de release oficial do próprio Rokit (`scripts/zip-release.sh`, linhas 39-52)
```bash
mkdir -p staging
cp "$TARGET_DIR/$BIN_NAME$BIN_EXT" staging/
cd staging
# zip/7z de tudo dentro de staging/ — só o binário está lá
```
Nenhum `LICENSE`, `README`, manifest ou qualquer outro arquivo é incluído.

### b) A lógica de extração do Rokit (`lib/sources/extraction.rs`)
- `extract_zip_file`/`extract_tar_file` (linhas 134-186, 193-245) procuram, dentro do arquivo, o **melhor candidato** para um arquivo chamado `<nome-da-ferramenta><EXE_SUFFIX>` (`.exe` no Windows, nada no Unix — `std::env::consts::EXE_SUFFIX`).
- `<nome-da-ferramenta>` vem de `self.tool_spec.name()` (`extraction.rs` não mostra isso diretamente, mas é passado por `artifact/mod.rs:82` — `let file_name = self.tool_spec.name().to_string();`) — ou seja, é o **nome do repositório**, exatamente como aparece em `owner/repo`. Para `victorcarmo2003/luaubench`, o Rokit procura por um arquivo `luaubench` (ou `luaubench.exe` no Windows) dentro do zip.
- Sistema de pontuação de candidato (`Candidate::score`, `extraction.rs:109-116`): soma pontos por caminho completo idêntico, nome de arquivo idêntico (exato ou case-insensitive), permissão de execução (Unix), extensão `.exe` (Windows) e conteúdo reconhecível como executável do OS atual (`Descriptor::detect_from_executable`, via assinatura binária PE/ELF/Mach-O). **Só entra na lista se pontuação > 0** (`extraction.rs:166`, `226`).
- Depois de extrair, há uma checagem extra: se o binário extraído tiver uma assinatura de executável reconhecível e o OS dela não bater com o OS atual, Rokit rejeita com `ExtractError::OSMismatch` (`artifact/mod.rs:117-129`).

**Implicação prática:** o binário dentro do zip precisa se chamar exatamente `luaubench` (Linux/macOS) ou `luaubench.exe` (Windows) para pontuação máxima e match garantido — nome diferente (`luaubench-cli`, `bin/luaubench`, etc.) arrisca não pontuar e falhar a extração silenciosamente (`FileMissing` error, `extraction.rs:29-33`). Um arquivo dentro de subpasta também funciona (o match usa `file_name()`, não exige raiz do zip), mas a convenção do próprio Rokit é raiz do zip, sem subpasta.

---

## 3. Formato da tag da release

**Resposta curta: Rokit aceita `v1.2.3` OU `1.2.3` (prefixo `v` opcional, sempre tolerado).**

### Para `rokit add`/instalação da **última** versão (`lib/sources/artifact/mod.rs:132-160`, método `get_latest_release`)
```rust
let version_str = release.tag_name.trim_start_matches('v');
let version_str_xyz = to_xyz_version(version_str);   // "1.2" -> "1.2.0"
let version = version_str_xyz.parse::<Version>()...
```
Usa `/releases/latest` da API do GitHub e simplesmente remove um `v` inicial se houver, antes de fazer parse semver. Aceita `v1.2.3`, `1.2.3`, `v1.2`, `1.2` (normalizado para `x.y.0` por `to_xyz_version`, `lib/tool/util.rs:3-16`).

### Para instalação de versão **específica** (`get_specific_release`, `artifact/mod.rs:166-206`)
Tenta, em ordem, **ambas** as variações de tag:
```
GET /repos/{owner}/{repo}/releases/tags/v{tag}
GET /repos/{owner}/{repo}/releases/tags/{tag}
```
E se a versão pedida for `x.y.0` (patch zero, sem pre-release/build), também tenta a tag curta `x.y` (sem o `.0`) nas duas variações — cobre projetos que taggeiam `v1.2` em vez de `v1.2.0`.

**Conclusão prática:** usar `vMAJOR.MINOR.PATCH` (ex.: `v1.0.0`) — como já documentado na regra `04-cli-rokit.md` do projeto — funciona sem ambiguidade e é o padrão que o próprio Rokit usa nas suas releases (`tag_name: v${{ needs.init.outputs.version }}` em `release.yaml:131`). Não usar sufixos exóticos: a versão precisa ser semver válido depois de tirar o `v` (`x.y.z`, com pre-release/build opcionais tipo `1.0.0-alpha.1` — visto em `lib/tool/spec.rs` tests).

---

## 4. `rokit.toml` do projeto do usuário — não precisa de nada especial

Confirmado em `lib/manifests/rokit.rs`:
- O manifesto do **usuário** (quem instala) é só `[tools]` + `alias = "author/name@version"` (linhas 18-25, formato default; `add_tool`, linhas 118-133, grava exatamente essa string via `spec.to_string()` que é `"{id}@{version}"`, `lib/tool/spec.rs:117-121`).
- `rokit add victorcarmo2003/luaubench` (sem versão) resolve a última release via `get_latest_release` e grava `luaubench = "victorcarmo2003/luaubench@X.Y.Z"` automaticamente — nenhuma configuração manual extra é necessária, desde que a release esteja no formato certo (zip com nome reconhecível de OS/arch, binário certo dentro).
- `ToolId::from_str` (`lib/tool/id.rs:87-123`) aceita opcionalmente um prefixo de provider (`github:owner/repo`), mas o **default é GitHub** (`ArtifactProvider::default()`, linha 95) — então `owner/repo` puro, sem prefixo, já resolve para GitHub. `rokit add victorcarmo2003/luaubench` funciona puro, como intuído.

**Não confirmado / fora do escopo do código lido:** não há nada no lado do **repositório publicador** (luaubench) que precise de um `rokit.toml` próprio — esse manifesto é do consumidor, não do publicador. O repositório `luaubench` não precisa conter nenhum arquivo Rokit-specific; a única coisa que importa é a GitHub Release em si (assets certos, tag certa).

---

## 5. Ferramenta auxiliar recomendada pelo ecossistema para gerar o zip

**Não existe uma Action/ferramenta oficial do Rokit para isso.** O próprio Rokit empacota sua release com:
- Um script bash próprio, escrito à mão: `scripts/zip-release.sh` (usa `zip`/`7z` direto, sem lib de empacotamento) — `.github/workflows/release.yaml:100-101`.
- `softprops/action-gh-release@v2` (Action de terceiros, genérica de GitHub Releases — não é Rokit-specific) para efetivamente criar a release e subir os arquivos — `release.yaml:126-134`.
- `scripts/unpack-releases.sh` só reorganiza os artifacts baixados do matrix build antes do upload.

Não há menção no `README.md` nem no `CHANGELOG.md` do repositório a nenhuma ferramenta dedicada tipo "rokit-package" ou Action oficial para terceiros empacotarem suas próprias tools. O padrão do ecossistema é: cada projeto escreve seu próprio pipeline de CI que gera `<nome>-<versão>-<os>-<arch>.zip` com o binário dentro, replicando manualmente a convenção que o Rokit sabe detectar por keyword-matching.

**Incerto:** posso ter perdido alguma Action comunitária de terceiros (não-oficial) no marketplace do GitHub Actions — não pesquisei o GitHub Marketplace, só o repositório oficial `rojo-rbx/rokit`. Se quiser, posso pesquisar isso separadamente, mas não é fonte primária do Rokit em si.

---

## Resumo executivo (para desbloquear a release do LuauBench)

1. **Nome do zip:** algo como `luaubench-1.0.0-windows-x86_64.zip` (ou `win64`/`windows-x64`, qualquer combinação que contenha uma keyword de OS + uma de arch reconhecida pelas listas acima). Padrão recomendado (o mesmo que o Rokit usa em si): `luaubench-<versao>-<os>-<arch>.zip` com `<os>` = `windows`/`macos`/`linux` e `<arch>` = `x86_64`/`aarch64`.
2. **Dentro do zip:** só o binário, nomeado exatamente `luaubench.exe` (Windows) — sem `LICENSE`, sem manifest, sem subpastas.
3. **Tag:** `v1.0.0` (com `v`) é seguro e é o padrão usado pelo próprio Rokit.
4. **`rokit.toml` do usuário:** nada especial — `rokit add victorcarmo2003/luaubench` sozinho resolve tudo, desde que a release esteja no formato acima.
5. **Ferramenta de empacotamento:** nenhuma oficial — escrever um script próprio (equivalente ao que já existe em `tools/build.luau`/pipeline darklua+lune do projeto) que gera o zip nomeado corretamente, um por plataforma, e sobe via `gh release create`/`softprops/action-gh-release` ou manualmente.

**Se o LuauBench (via `lune build`) só compila para a plataforma atual (sem cross-compile nativo do Lune):** cada plataforma precisa ser buildada no seu próprio runner de CI (Windows runner gera o `.exe`, Linux runner gera o binário Linux, macOS runner gera o binário macOS) — mesmo padrão de matrix build que o `release.yaml` do próprio Rokit usa. Isso é uma inferência baseada no pipeline observado do Rokit, não uma confirmação de como `lune build` cross-compila — se precisar dessa confirmação (`lune build --target` ou equivalente), é pesquisa separada sobre o Lune, não sobre o Rokit.
