# Macker — Contexto Completo do Projeto

> Documento de conhecimento acumulado: arquitetura, fatos técnicos não-óbvios,
> estado atual do runtime e trabalho realizado. Atualizado em 2026-08-13.

---

## 1. Visão geral

**macker** é um substituto do Docker Desktop construído sobre o runtime
nativo de containers da Apple (`apple/container`). Containers Linux rodam como
VMs leves no Apple Silicon via Virtualization.framework. O projeto entrega:

- **GUI nativa macOS (SwiftUI)** — Dashboard, Containers, Images, Volumes,
  Networks, Compose, Settings, menu bar.
- **CLI shim compatível com `docker` / `docker-compose`** — um único binário
  com dois modos (sem argumentos = GUI; com argumentos = CLI).
- **Engine de Compose própria** — parser YAML, resolução de `depends_on`,
  orquestrador com recriação por config-hash, DNS por nome de serviço via
  `/etc/hosts`, health checks.
- **Hot reload** — ponte FSEvents → inotify sintético para bind mounts
  virtiofs (padrão Colima/Lima).

**Workspace:** repo root (SPM, macOS 15+, arm64).

**Protocolo XPC pinado:** apple/container **1.2.2** (`containerVersion` em
`Package.swift`). `container-apiserver` precisa estar rodando.

---

## 2. Arquitetura em camadas

```
┌─────────────────────────────────────────────────────────────┐
│                    PRESENTATION LAYER                       │
│  Views (SwiftUI puro)  ←  AppState (@Observable)           │
├─────────────────────────────────────────────────────────────┤
│                    SERVICE LAYER                            │
│  AppState (polling, state aggregation)                      │
│  ContainerService | ComposeEngine | HotReloadService        │
├─────────────────────────────────────────────────────────────┤
│                    BACKEND LAYER                            │
│  XPCClient (primary) | ProcessRunner (fallback)             │
│  LaunchdManager (daemon lifecycle)                          │
├─────────────────────────────────────────────────────────────┤
│                    PLATFORM LAYER                           │
│  container-apiserver (XPC) | container CLI | virtiofs/VZ    │
└─────────────────────────────────────────────────────────────┘
```

**Princípios:**
1. **XPC-first, CLI-fallback** — comunicação primária via XPC com
   `container-apiserver`. CLI só para operações sem API equivalente (daemon
   lifecycle, imagens, builder).
2. **Protocol abstraction** — `ContainerServiceProtocol` permite trocar a
   implementação XPC por `ContainerClientKit` da Apple sem tocar nas camadas
   superiores.
3. **Single binary, dual mode** — dispatch em `Main.swift`.
4. **Compose como engine first-class** — parser, planner, orchestrator,
   health checker, hosts sync próprios.

### Módulos (SPM)

| Módulo | Propósito |
|--------|-----------|
| `MackerApp` | GUI SwiftUI + dispatch dual-binary |
| `MackerCLI` | ArgumentParser root + shim `docker`/`compose` |
| `ContainerBackend` | XPC client leve (sem gRPC/NIO), modelos tipados, serviços |
| `ComposeEngine` | Parser YAML, resolver, orquestrador, `/etc/hosts`, health checks |
| `HotReloadService` | FSEvents → inotify bridge para virtiofs |

---

## 3. Status do roadmap

**Todas as 9 fases do plano estão completas** (plano em
`docs/roadmap.md`):

- Fase 0 — Fundação (SPM, XPC client, CLI, CI) ✅
- Fase 1 — Core Backend Services (containers, imagens, redes, volumes, stats, logs) ✅
- Fase 2 — GUI básica (Dashboard, Containers, Images, Menu bar) ✅
- Fase 3 — Compose Engine + Hot Reload ✅
- Fase 4 — Docker CLI Shim ✅
- Fase 5 — Polimento e distribuição (Settings, Keychain, Charts, signing) ✅

---

## 4. Fatos técnicos não-óbvios (gotchas que custaram tempo de debug)

### 4.1 Protocolo XPC

- **Route key:** `com.apple.container.xpc.route`
- **Error key:** `com.apple.container.xpc.error`
- **Service:** `com.apple.container.apiserver`
- **Fluxo de bootstrap:** `bootstrap(id:stdio:dynamicEnv:)` cria o processo init
  em estado "created" → `containerStartProcess` inicia → `containerWait` bloqueia
  até o exit. Pipes de stdio DEVEM ser passados ao bootstrap para capturar o
  output do init.
- **`dynamicEnv` vazio:** não enviar `{}` — o servidor falha o bootstrap com
  EOPNOTSUPP. Só enviar quando não-vazio.

### 4.2 Image inspect (crítico)

- `container image inspect` coloca Cmd/Entrypoint/Env/WorkingDir em
  `variants[0].config.config` (ANINHADO), NÃO em `variants[0].config`.
- Errar isso faz `docker run`/compose rodar `/bin/sh` silenciosamente e sair
  com 0.
- **Annotations:** `configuration.descriptor.annotations` — imagens locais têm
  (`com.apple.containerization.image.name` etc.), imagens puxadas podem não ter.
  `parseImageInspect` deve copiá-las para o `Descriptor`, senão `createContainer`
  falha com "descriptor mismatch".

### 4.3 Merge Entrypoint/Cmd (semântica Docker)

- **Sem entrypoint:** `arguments = Array(cmd.dropFirst())` — o primeiro elemento
  do Cmd é o executável. Bug antigo duplicava o primeiro elemento
  (`cat /hello.txt` → `cat cat /hello.txt`).
- **Com entrypoint:** `arguments = Array(entrypoint.dropFirst()) + cmd`.
- **Command override** (compose `command:` / `docker run image cmd`):
  - Sem entrypoint em efeito → o comando substitui o processo inteiro.
  - Com entrypoint → o comando vira os args do entrypoint (o entrypoint é
    PRESERVADO, não substituído).
- **String command** deve ser dividida em args individuais
  (`postgres -c max_connections=50` → `["postgres","-c","max_connections=50"]`),
  senão o `exec "$@"` do entrypoint falha com exit 127.

### 4.4 Compose — campos dual-shape

- `depends_on` e `environment` aceitam forma lista OU mapa — decoders custom
  (`DependsOnMap`, `EnvironmentMap`).
- Declarações vazias (`volumes: {data:}`) parseiam como null — normalizar para
  dict vazio antes do JSON decode.
- Campos string-ou-lista:
  - `build` (string ou dict)
  - `command`/`entrypoint` (string dividida via `CommandList` shell tokenizer,
    ou lista)
  - `healthcheck.test` (string mantida INTEIRA como comando shell via
    `StringOrList`, ou lista)
  - `networks` (lista ou mapa via `NetworkList`)
  - `ports` (lista de strings ou lista de mapas via `PortList`)
- **`CommandList.shellSplit`** respeita aspas simples/duplas e escapes com
  backslash — `sh -c "npm install && npm run dev"` →
  `["sh","-c","npm install && npm run dev"]`. Um split ingênuo por espaço
  quebra `sh -c "..."`.

### 4.5 Bootstrap — EOPNOTSUPP e "storage device attachment is invalid"

Causas confirmadas de falha de bootstrap (todas corrigidas):

1. **Volume nomeado com `source` = nome puro** → EOPNOTSUPP. O servidor precisa
   do CAMINHO COMPLETO da imagem do volume
   (`~/Library/Application Support/com.apple.container/volumes/<name>/volume.img`).
   Fix: `resolveVolumeSources` chama `inspectVolume(name)` e usa `volume.source`.
2. **Limites de recursos explícitos + volume nomeado** → "storage device
   attachment is invalid". Fix: `Resources.cpus`/`memoryInBytes` são opcionais e
   omitidos quando não especificados (o servidor aplica seus próprios defaults).
3. **`user: root` explícito + volume nomeado** → "storage device attachment is
   invalid". Fix: usar `userString: ""` (default da imagem), como o CLI faz.
4. **MTU não definido** → EOPNOTSUPP. O CLI sempre define `mtu: 1280` nas
   opções de rede. O app deve fazer o mesmo.
5. **Env duplicado** (ex.: PGDATA da imagem + do compose) → quebra o bootstrap.
   Fix: `deduplicateEnv` (último vence, ordem de primeira aparição).
6. **Healthcheck string** — Docker trata string como CMD-SHELL (roda via
   `sh -c`). O app executava a string inteira como executável. Fix:
   `runHealthcheck` roda teste de 1 elemento via `["sh", "-c", first]`.

### 4.6 Bind mounts

- **Resolução de source relativo:** `./:/app:rw` deve resolver o source contra o
  diretório do compose file (`resolvePath`), senão o virtiofs monta o caminho
  errado read-only (EROFS no `npm install`).
- **`resolvePath` é `static`** — chamá-lo como método de instância falha o build
  SILENCIOSAMENTE e deixa um binário STALE (o compose up reusa/cria containers
  com o comportamento antigo). Sempre rodar `swift build` e checar erros antes
  de testar.
- **Source relativo `.` / `..`** — um mount `.:/app` era tratado como volume
  nomeado `.` (o parser só excluía prefixos `/`, `./`, `../`, `~/`), gerando
  "references undefined volume '.'". Fix: `namedVolumes` (ComposeParser) e
  `parseVolumeSpec` (ComposeOrchestrator) também excluem os sources exatos
  `.` e `..` como bind mounts.
- **`docker run -v` auto-cria:** volumes nomeados que não existem são criados
  (semântica Docker) e diretórios de bind mount que não existem são criados.
  Ambos são necessários ou o bootstrap falha (EOPNOTSUPP para nome puro, errno 2
  para source de bind ausente).

### 4.7 DockerCommand parser

- Flags são armazenadas pela chave literal sem hífens: `-v` → `"v"`,
  `--volume` → `"volume"`. Chamadores DEVEM checar as duas formas — helpers
  `value(short:long:)` e `has(short:long:)`.
- Bug antigo: `docker run -v` mounts eram descartados porque o tradutor lia
  `flags["volume"]` (só casava `--volume`).
- Flags booleanas precisam estar em `booleanFlagSpecs[subcommand]`, senão o
  parser as trata como value-taking (consome o próximo token). Ex.: `--builder`
  no `system prune` precisou ser adicionado ao set.

### 4.8 Config-hash recreation

- SHA256 do JSON do `ServiceConfig` armazenado como label
  `com.macker.compose.config-hash`.
- `up` recria containers cujo hash mudou.
- Transformações de runtime (resolução de source de mount) NÃO fazem parte do
  hash — containers podem ser reutilizados com configs stale.

### 4.9 /etc/hosts DNS

- Após compose up, pegar o IP de cada container do network attachment e rodar
  `sh -c "printf ... >> /etc/hosts"` dentro de cada container via
  createProcess/startProcess/waitForProcess.

### 4.10 Swift 6 / SwiftUI

- `AppState` é `@MainActor @Observable` com `nonisolated init` (para `@State
  private var state = AppState()` funcionar no App struct).
- Ações de view usam `Task { @MainActor in await state.xxx() }`.
- Scenes condicionais (`if showMenuBar { MenuBarExtra }`) disparam um bug do
  compilador ("failed to produce diagnostic") — manter MenuBarExtra
  incondicional.
- **MenuBarExtra força `.accessory` activation policy** — sem ícone no Dock,
  sem Cmd+Tab, janela esconde ao clicar. Fix: `@NSApplicationDelegateAdaptor`
  + `NSApp.setActivationPolicy(.regular)` + `activate(ignoringOtherApps: true)`
  em `applicationDidFinishLaunching` (roda DEPOIS do setup das scenes).
- **Empty List overlay não centraliza** — usar `ContentUnavailableView` (macOS
  14+) em vez de `.overlay` em List vazia.
- **ContainerRow layout** — IDs longos sem `lineLimit` expandem a linha e
  quebram responsividade. Fix: `.lineLimit(1)` + `.truncationMode(.middle)`.

### 4.11 Testes

- **XCTest NÃO está disponível localmente** (CommandLineTools não o inclui) —
  `swift build --build-tests` falha com "no such module 'XCTest'". Testes rodam
  no CI com Xcode completo. Verificar código com `swift build` apenas.

### 4.12 Hot reload

- FSEvents → guest agent touch → inotify ATTRIB sintético (padrão Colima/Lima).
- Guest agent é C source em `Resources/guest-agent/guest-agent.c`, build via
  `Scripts/build-guest-agent.sh` (precisa toolchain aarch64 Linux — não
  disponível localmente).
- Limitações: só ATTRIB (sem MODIFY/CREATE/DELETE); deleções no host não
  propagam; debounce de 100ms.

### 4.13 Disk usage (route XPC não implementada)

- A rota XPC `systemDiskUsage` NÃO é implementada pelo apiserver: `send`
  responde sem a chave `.diskUsageStats`, e `ContainerAPIClient.systemDiskUsage`
  devolvia `SystemDiskUsage()` vazio — Settings Storage mostrava `-` no
  Total/Reclaimable.
- Fix: `ContainerService.systemDiskUsage` segue o padrão XPC-first,
  CLI-fallback — tenta a rota XPC; se `totalSize`/`reclaimableSize` vierem nil,
  faz `container system df --format json` via `ProcessRunner` e agrega
  `sizeInBytes` (total) e `reclaimable` (imagens+containers+volumes). Em
  qualquer falha devolve vazio (não quebra o refresh).
- `container system df` NÃO tem API XPC equivalente; a fonte de verdade é o CLI.
- O CLI shim `docker system df` reusa a mesma fonte — passou a imprimir valores
  reais (ex.: Total 27.69 GB, Reclaimable 3.12 GB).

---

## 5. Trabalho da sessão atual (2026-08-13)

### 5.1 Compose com `build:` — stack de exemplo funcionando

Um compose file de exemplo com 3 serviços (postgres, uma API com `build:`
e pgadmin) agora funciona end-to-end:

- **`example_postgres_dev`** (postgres:14.5) — running, healthcheck passou
  (gate `service_healthy`).
- **`example_api`** (build: context . + Dockerfile) — running: `npm install`
  → migrations → seed → servidor HTTP em `0.0.0.0:3333` → **HTTP 200**.
- **`example_pgadmin_dev`** (dpage/pgadmin4:6.13) — running, HTTP 302 (login).

**Correções aplicadas nesta sessão:**
1. **Build quebrado** — `resolvePath` era `static` mas chamado como método de
   instância em 3 pontos (linhas 418, 526, 527 do ComposeOrchestrator). O build
   falhava e o binário usado era stale (sem o fix do bind mount). Fix:
   `Self.resolvePath`.
2. **Bind mount resolvido** — após rebuild, o container recriado tem
   `source: "/path/to/example-api"` (antes
   `"."`). EROFS eliminado.
3. **DockerTranslator short-flag bug** — `-v`/`-p`/`-e` agora resolvem via
   `value(short:long:)`.
4. **DockerTranslator volume resolution** — volumes nomeados resolvidos para o
   caminho da imagem + auto-criação de volumes e diretórios de bind mount.

### 5.2 Feature de limpeza de armazenamento

O processo que liberou espaço (deletar builder do buildkit + `container image
prune -a`) agora está exposto na GUI e no CLI:

**Backend:**
- `ImageService.prune(all:)` — `all` adiciona `-a` ao `container image prune`.
- `ContainerService.deleteBuildkitBuilder()` — encontra container com
  `id == "buildkit"` e deleta com force (recriado no próximo build).

**CLI:**
- `macker system prune [--all] [--builder]` — novo subcomando.
- `docker system prune [-a] [--builder]` — o shim agora realmente limpa
  (antes só imprimia aviso). `--builder` é extensão macker.

**GUI (Settings → aba Storage):**
- Disk usage (Total / Reclaimable via `systemDiskUsage`).
- Botões: "Prune unused images" (dangling, sem confirmação), "Prune all
  images", "Delete buildkit builder", "Full cleanup" (builder + prune all) —
  os destrutivos com `confirmationDialog`.
- `isCleaning` desabilita botões + mostra `ProgressView`.

**Testes:** `system prune` exit 0; `--builder` deleta o buildkit; shim
`docker system prune --builder` funciona; GUI lança sem crash; stack compose
intacto.

---

## 6. Estado atual do runtime (2026-08-13)

### Containers

| Container | Imagem | Status |
|-----------|--------|--------|
| `example_postgres_dev` | docker.io/library/postgres:14.5 | running |
| `example_api` | example-api-example_api:latest | running |
| `example_pgadmin_dev` | docker.io/dpage/pgadmin4:6.13 | running |

> O builder do buildkit foi deletado durante os testes da feature de limpeza —
> será recriado no próximo `container build`.

### Imagens

| Repositório | Tag | Tamanho |
|-------------|-----|---------|
| docker.io/dpage/pgadmin4 | 6.13 | 246.3 MB |
| docker.io/library/node | 22.21.0-alpine3.22 | 56.7 MB |
| docker.io/library/postgres | 14.5 | 1.03 GB |
| example-api-example_api | latest | 117.6 MB |

### Volumes

- `example-api_example_pgadmin_dev_data`
- `example-api_example_postgres_dev_data`

### Serviços

- API de exemplo: **HTTP 200** em `http://127.0.0.1:3333/`
- pgadmin: **HTTP 302** em `http://127.0.0.1:16543/`

---

## 7. Superfície CLI

```bash
macker version                    # versão client + daemon
macker selftest [--strict]        # valida XPC end-to-end
macker system status              # health do daemon
macker system prune [--all] [--builder]   # limpeza de armazenamento
macker docker ...                 # shim docker (ps/run/exec/logs/...)
macker compose ...                # engine de compose (up/down/ps/...)
```

**Docker shim suportado:** `ps/run/create/exec/logs/stop/start/restart/kill/rm/
stats/wait/port/prune/top/pause/unpause/events`, `images/pull/push/build/tag/
load/save/rmi/prune`, `volume create/ls/rm/inspect/prune`, `network
create/ls/rm/inspect/connect/disconnect/prune`, `system df/prune/info/version`,
`compose up/down/ps/logs/stop/start/restart/pull/build/create/exec/images/kill/
port/rm/run/version/config/ls`.

**Comandos sem equivalente no runtime apple/container** (falham com erro
informativo, não silencioso): `rename`, `update`, `attach`, `history`,
`compose top`. O runtime não expõe essas operações (rename, mutação de recursos
ao vivo, attach de stdio, histórico de camadas).

**Aproximações best-effort** (o runtime não tem API nativa, então são
implementados por aproximação):
- `docker top` — executa `ps` dentro do container (requer `ps` na imagem).
- `docker pause`/`unpause` — envia SIGSTOP/SIGCONT ao container.
- `docker events` — polling do estado dos containers a cada 1s, emitindo
  eventos docker-style (create/start/stop/die/destroy).

**Symlinks:** `ln -s /usr/local/bin/macker /usr/local/bin/docker` e
`docker-compose`.

**Dispatch transparente para o shim docker:** o binário é feito para ser
symlinkado como `docker`, então `docker ps`/`docker run`/etc. devem funcionar
diretamente. O shim vive sob o subcomando `docker`; em `Main.swift`, quando o
primeiro argumento não é um subcomando de topo conhecido (`version`, `selftest`,
`system`, `docker`, `help`, `--help`, `-h`, `--version`), o `docker` é
prependido automaticamente — tornando `macker ps` e `docker ps`
equivalentes. `macker compose ...` também roteia para o shim.

---

## 8. Superfície GUI

- **Dashboard** — cards de recursos, status do daemon, e gráficos de
  estatísticas (CPU, Memória, Block I/O) com filtro por container ou agregado
  (série derivada de `AppState.statsHistory`, 120 amostras).
- **Containers** — lista com busca, start/stop/restart por linha, detail pane
  (Info/Stats/Logs/Settings). A aba Settings edita redes, portas publicadas,
  memória/CPU, variáveis de ambiente e labels, aplicando via recriação do
  container (o runtime apple/container não suporta mutar um container em
  execução).
- **Images** — lista com pull sheet e delete.
- **Volumes / Networks** — listas com delete.
- **Compose** — file picker, lista de serviços, ações up/down/restart/logs,
  painel de log colapsável.
- **Settings** — General (polling, menu bar, startup/login, instalação do CLI),
  Runtime (daemon, recursos), Storage (disk usage + limpeza), Menu bar
  (métricas customizáveis).
- **Menu bar** — anéis de CPU/memória, métricas de texto configuráveis
  (memória usada/limite, contagens, disco), lista de containers agrupada por
  projeto compose, menu de ações por container (Logs/Restart/Stop/Recreate/
  Remove), controles do daemon (Parar serviço / Reiniciar / Fechar Apple
  Docker).

---

## 9. Convenções do projeto

- **Sem emojis/unicode** no código e na UI (preferência do usuário). Status
  usam SF Symbols (`checkmark.circle.fill` verde / `exclamationmark.triangle.
  fill` vermelho) via struct `StatusMessage`. Logs e CLI usam ASCII puro:
  `==>` para início de operação, `[OK]`/`[FAIL]`/`[ERROR]` para resultados.
- **SF Symbols não renderizam dentro de `Text` monospaced** — só como
  `Image(systemName:)`.
- **Compose progress + log panel:** `ComposeOrchestrator.up/down/...` aceitam
  `progress: AsyncStream<String>.Continuation?` e emitem passos, finalizando via
  `defer`. `AsyncStream.Continuation` é Sendable, cruza o orchestrator Sendable
  limpo; o closure `Task { @MainActor in }` da view NÃO é @Sendable (captura
  `@State` da view).
- **Daemon lifecycle:** `LaunchdManager` faz shell-out para
  `/usr/local/bin/container system start|stop|status` via ProcessRunner (sem
  equivalente XPC). `container system stop` é idempotente (exit 0 quando já
  parado), então restart funciona de qualquer estado.
- **Comunicação com o usuário em pt-BR.**

---

## 10. Pendências / próximos passos

- **Nenhuma tarefa pendente** — tasks #10–#14 concluídas.
- Features da sessão: menu bar customizável (MenuBarConfig), agrupamento por
  projeto compose, ações por container (Logs/Restart/Stop/Recreate/Remove),
  "iniciar com o sistema" (SMAppService), instalação do CLI com privilégios
  de administrador (osascript), aba Settings no detail do container
  (redes/portas/recursos/env/labels via recriação), e gráficos de estatísticas
  no Dashboard (CPU/Memória/I/O com filtro por container).
- Ideias futuras (do plano, não implementadas): `docker compose run
  --service-ports`, `docker cp -a`, `docker attach` interativo, `docker
  history`, `docker save/load` OCI, `deploy.replicas` (swarm), `network_mode:
  service:<name>`, auto-update Sparkle, notarização, fórmula Homebrew.
- Testes unitários rodam apenas no CI (XCTest indisponível localmente).

---

## 11. Referências

- Plano de implementação: `docs/roadmap.md`
- Runtime: [apple/container](https://github.com/apple/container) (protocolo 1.2.2)
- Compose file de teste: `docker-compose.yml` de exemplo

## Crash do Terminal (FileHandle)
- `XPCMessage.set(key:value: FileHandle)` NUNCA deve chamar `value.close()`.
  `xpc_fd_create` ja duplica o fd; fechar o handle original faz um acesso
  posterior a `fileDescriptor` lancar `NSFileHandleOperationException`
  (excecao ObjC, nao capturada por `try?`), crashando o app.
- Caso real: `ContainerTerminalView` passa o MESMO handle para stdout e
  stderr. O primeiro `set` fechava o handle; o segundo `set` crashava.
- Ciclo de vida dos handles e do chamador (closeOnDealloc: true).
