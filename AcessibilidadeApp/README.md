# App de Mobilidade Acessível — DF

Scaffold completo em SwiftUI + MapKit + CoreLocation + SwiftData, arquitetura MVVM.

## Estrutura

```
AcessibilidadeApp/
├── App/
│   └── AcessibilidadeApp.swift      # @main, configura o ModelContainer do SwiftData
├── Models/
│   └── TripRecord.swift             # @Model — histórico de viagens
├── Services/
│   ├── LocationManager.swift        # Wrapper observável do CoreLocation
│   └── AccessibleRouteService.swift # Cálculo de rota + heurística de acessibilidade
├── ViewModels/
│   └── MapViewModel.swift           # Busca, estado de navegação, persistência
├── Views/
│   ├── HomeView.swift
│   ├── MapView.swift
│   └── Components/
│       └── GlassComponents.swift    # Botão, painel e busca no estilo "Liquid Glass"
└── Utilities/
    └── Extensions.swift
```

## Como importar no Xcode

1. Crie um novo projeto **App** (SwiftUI, iOS 17+) no Xcode.
2. Copie as pastas `App`, `Models`, `Services`, `ViewModels`, `Views` e `Utilities` para
   dentro do seu projeto (arraste no Project Navigator, marcando "Copy items if needed").
3. Apague o `ContentView.swift` e o arquivo `@main` gerados automaticamente pelo Xcode —
   `App/AcessibilidadeApp.swift` já assume esse papel.
4. No `Info.plist` (ou na aba **Info** do target), adicione as chaves de permissão de
   localização, obrigatórias para o CoreLocation funcionar:
   - `NSLocationWhenInUseUsageDescription` — ex.: "Usamos sua localização para calcular
     rotas acessíveis até o seu destino."
   - `NSLocationAlwaysAndWhenInUseUsageDescription` (se pretender rastrear em segundo
     plano no futuro).
5. Target mínimo: **iOS 17.0** (o projeto usa `@Observable`, a nova API do `Map` e
   `MapCameraPosition`, disponíveis a partir do iOS 17).

## ⚠️ Sobre a "roteirização acessível"

O MapKit **não** expõe dados oficiais de acessibilidade (rampas, calçadas rebaixadas,
largura de passeio). `AccessibleRouteService` simula essa priorização: pede rotas
alternativas de caminhada ao MapKit e pontua cada uma pela proximidade a uma lista de
barreiras conhecidas (`AccessibilityBarrier`), hoje preenchida com **um único exemplo
fictício** no DF.

Para um app real, os próximos passos seriam:
- Substituir `AccessibleRouteService.sampleBarriers` por uma fonte de dados real (ex.:
  OpenStreetMap com tags de acessibilidade, ou uma base própria alimentada pela
  comunidade).
- Considerar um serviço de roteirização dedicado a pedestres com dados de acessibilidade,
  já que o `MKDirections` é genérico.

## Próximos passos sugeridos

- Testes unitários para `AccessibleRouteService` (pontuação de rotas) e `MapViewModel`.
- Tela de histórico completo de viagens (além do carrossel na Home).
- Modo de navegação com instruções passo a passo (`route.steps`).
- Feedback de acessibilidade colaborativo: permitir que o próprio usuário reporte
  barreiras encontradas no caminho.

---

## Fase 2 — navegação em tempo real

- `LocationManager` acumula a distância percorrida (ignora leituras com precisão pior que 20 m).
- `MapViewModel` expõe distância percorrida/restante/progresso; a câmera segue o usuário
  (`MapCameraPosition.userLocation(followsHeading:fallback:)`).
- Com trajeto ativo, o botão central da Home vira **"Voltar à Rota"** (reabre o mapa sem perder o progresso).
- Tocar numa viagem recente refaz o trajeto: recalcula a rota acessível até o mesmo destino.
- "Restante" é uma estimativa (distância da rota − distância percorrida); não recalcula desvios.

## Palácio da Memória

Quatro "salas" persistidas em SwiftData, todas somente no aparelho:

| Sala | Modelo | Alimentada por |
|---|---|---|
| Perfil & Mobilidade | `MobilityProfile` | tela de perfil (ícone na Home) |
| Mapa & Obstáculos | `ObstacleReport` | botão ⚠️ durante a navegação |
| Destinos & Estabelecimentos | `PlaceAccessibility` | tela de feedback pós-trajeto |
| Histórico de Rotas | `RouteFeedback` | tela de feedback pós-trajeto |

Ao calcular uma rota (`MapViewModel.calculateRoute`): 1) lê o Perfil, 2) lê os Obstáculos,
3) escolhe entre as rotas alternativas do MapKit a de menor pontuação, 4) monta o aviso
(`RouteAdvisor`) cruzando também Destinos e Histórico.

Limitações: o MapKit só devolve algumas rotas alternativas — se todas passarem por um obstáculo,
o app avisa, mas não consegue desviar. A inclinação máxima do perfil ainda não é usada (sem dados
de relevo). Os padrões do perfil são conservadores e devem ser ajustados pela pessoa.

---

## Fase 3 — múltiplas rotas, POIs e re-routing

- **Rotas:** `AccessibleRouteService.calculateAccessibleRoute` devolve até 3 `AccessibleRouteResult`
  (azul = ideal, verde = alternativa, laranja = contorno). A ideal é a de menor custo
  (duração + obstáculos ponderados pelo perfil + penalidade de bloqueio). Escolha por card ou
  tocando na linha no mapa. Sempre `.walking`.
- **Visual de pedestre:** contorno branco arredondado, linha pontilhada nas rotas não selecionadas,
  mapa base "muted" e sem trânsito. O MapKit não expõe geometria de faixas de pedestres, então elas
  não são destacadas individualmente.
- **POIs:** botões 💊 e 🛍 no topo do mapa ligam as camadas (busca na região visível). Toque num
  marcador abre um banner; "Incluir parada em farmácia próxima" traça primeiro a rota até a farmácia
  mais próxima do trajeto (até 300 m) e, ao chegar, segue para o destino.
- **Re-routing:** a cada leitura de GPS (precisão ≤ 25 m) mede-se a distância até a polilinha ativa;
  2 leituras seguidas a mais de 25 m disparam recálculo. Relatar um obstáculo no caminho também
  dispara. Cooldown: 20 s (desvio) e 5 s (obstáculo). O estado continua "navegando", a distância
  percorrida não zera e o `TripRecord` só é criado ao finalizar.
- **Distâncias:** `MetricDistance` (Extensions.swift) usa pt_BR + `.providedUnit`: sempre m ou km.

---

## Fase 4 — navegação passo a passo e atalhos

- **Recentralizar:** botão de vidro à direita, acima do painel, durante a navegação
  (`cameraPosition = .userLocation(followsHeading: true, fallback: .automatic)`).
- **Turn-by-turn:** `MapViewModel.refreshTurnInstruction` acha o passo atual (`MKRoute.Step`) e a próxima
  curva de verdade, somando trechos retos. A seta vem da mudança de rumo entre passos
  (`PolylineGeometry`, `TurnInstruction`); o texto do MapKit entra como complemento (nome da rua).
- **Métricas:** `[percorrido] • [tempo restante] • [restante]` (tempo no ritmo do perfil; m/km em pt_BR).
- **Atalhos da Home:** verde = farmácia mais próxima; âmbar = cadeira de rodas. Este último procura
  primeiro locais que a pessoa marcou com "Empréstimo de cadeira de rodas" (tela de feedback) e, se
  não houver, o shopping mais próximo (com aviso). Distância em linha reta, não a pé.

---

## Fase 5 — busca com ícones, painel retrátil, polilinha cortada e chegada automática

- **Ícones na busca:** `PlaceCategoryStyle` (PlaceItem.swift) mapeia `MKPointOfInterestCategory` → SF Symbols
  + tema de cor; `SearchResultRow`/`GlassPlaceIcon` (GlassComponents.swift) desenham o círculo de vidro.
  O autocompletar não informa categoria: os 6 primeiros resultados são resolvidos via `MKLocalSearch`
  (com atraso de 300 ms e cache); até lá vale um palpite pelo nome.
- **Painel de rotas retrátil:** `DetentBottomSheet` (3 alturas: recolhido 72 / compacto 200 / expandido 340),
  arraste na alça/cabeçalho, mola `response 0.35, damping 0.8`. Recolher não cancela a seleção.
- **Polilinha cortada:** `PolylineGeometry.trim` projeta o usuário perpendicularmente na rota e descarta o
  que ficou para trás; o progresso só avança (sem "pular" em rotas que passam perto de si mesmas).
- **Chegada automática:** a ≤ 25 m do destino final (2 leituras seguidas, após 10 m percorridos), a
  navegação encerra, vibra (sucesso) e abre o feedback; o `TripRecord` é salvo. Sem modo de localização
  em segundo plano, isso só acontece com o app aberto.

---

## Fase 6 — visual clean, vidro em camadas e Splash

- **Paleta:** `Utilities/ColorPalette.swift` define `Color.linen`, `.cream`, `.warmNude`, `.softTerracotta`,
  `.warmGraphite` (+ `.onTerracotta`, `.onWarmGraphite` para texto sobre preenchimento). Cada tom tem versão
  clara e escura. Use sempre com o prefixo `Color.`.
- **Cores funcionais intactas:** verde (farmácia), amarelo/âmbar (cadeira de rodas) e as cores das rotas
  não vêm da paleta.
- **Vidro e mola:** `SpringStyles.swift` — `Animation.homeSpring` (response 0.4, damping 0.8),
  `SpringPressButtonStyle` e `.homeGlass(...)` (base `cream` + material + sombras `.black.opacity(0.06)`).
- **Splash:** `SplashScreenView` + `RootView`. Pronto = dados iniciais + permissão de localização decidida +
  (primeira posição ou permissão negada), com mínimo de 2,2 s e teto de 10 s. A cadeira orbita o spinner,
  espirala até o centro e vira uma pessoa caminhando (`figure.roll` → `figure.walk`). Respeita
  "Reduzir Movimento".
- **Mudança de assinatura:** `HomeView(locationManager:)`; o `App` agora abre `RootView()`.

---

## Fase 7 — Configurações e Perfil

- `SettingsView`: tema (padrão do sistema / claro), mostrar trajetos recentes, apagar histórico e
  limpar obstáculos (ambos com `confirmationDialog`).
- `UserProfileView`: foto (só no aparelho), nome e histórico completo. `TripHistoryRow`: toque ou arraste
  para a esquerda revela **Repetir** e **Excluir**.
- A Live Activity / Dynamic Island desta fase foi **removida** do projeto (exigia uma extensão de widget,
  que é um target separado). O estado da navegação vive só em `MapViewModel` e `MapView`.

---

## Release Candidate — design system unificado

- **Mola elástica:** `SpringPressButtonStyle` (SpringStyles.swift) — cresce ao tocar e volta com mola solta
  (amortecimento 0,42) ao soltar. Aplicado em todos os botões personalizados do app. Não se aplica a
  controles do sistema (Toggle, Picker, botões de barra de navegação, alertas e diálogos).
- **Superfícies:** `homeGlass(wash:)` = lavagem quente (`cream`, `champagne`, `oatmeal`) + material + sombras
  suaves. `glassPanel`, `GlassCircleButton`, cards de rota, folha retrátil e banners usam essa base.
- **Fundo e formulários:** `AppBackground`, `themedForm()`, `themedSheet()`, `ThemedHeader`, `ThemedTitle`
  (ThemedBackground.swift). "Meu perfil" (MobilityProfileView), relato de obstáculo, feedback pós-trajeto,
  Configurações e Perfil do usuário seguem o mesmo padrão.
- **Tipografia:** `.fontDesign(.rounded)` e `.tint(softTerracotta)` no `RootView` valem para o app todo.
- **Autocomplete na Home:** `GlassSearchBar` (a mesma do mapa) + lista flutuante. Tocar numa sugestão
  resolve o endereço (`selectCompletion`), abre o mapa e as rotas são calculadas na hora.
