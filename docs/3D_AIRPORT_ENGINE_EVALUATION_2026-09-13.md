# Editable 3D airport: engine evaluation

Research date: 13 September 2026. Status: recommendation, not an adopted architecture decision. Validation consists of repository inspection and current official documentation; no comparative engine benchmark or playable prototype was run.

## Recommendation

For the existing iPhone/iPad Airline Empire app, prototype **RealityKit with the current Swift simulation core and SwiftUI interface**. This is the lowest-disruption route to an editable, animated airport whose decisions affect the existing airline business.

For a deliberate rebuild into a larger airport construction game targeting mobile and PC, choose **Unity 6 LTS with Universal Render Pipeline (URP)**. Its integrated game authoring workflow is a better starting point for that wider product. Unity is not a drop-in replacement for this app's map.

For a browser-first product, shortlist **Babylon.js before Three.js**: Babylon supplies more integrated game-oriented facilities. Three.js remains a strong choice when custom web UI and a deliberately assembled rendering stack are the priority.

The user confirmed that iPhone/iPad remains the primary target. Platform expansion would change the recommendation. These rankings are engineering judgments about this project, not measured performance rankings.

## What the repository actually contains

- `AirlineEmpireApp/project.yml` targets iOS 17.0. The application is SwiftUI.
- `AirlineEmpireApp/Sources/Map/MapView.swift` renders the world using `SwiftUI.Canvas` and `TimelineView`; there is no existing 3D airport renderer to extend.
- `AirlineEmpireCore` is a Swift package. `Domain/GameState.swift` owns authoritative simulation state; `Simulation/Command.swift` defines validated player actions.
- `World/AirportSpec.swift` describes airport location, runway class, capacity and fees. `Domain/WorldState.swift` currently gives `AirportRuntime` slot allocations, not editable buildings, local coordinates or traffic networks.
- `docs/ARCHITECTURE.md` separates rendering from deterministic simulation, preserves versioned saves and aggregates passengers. That separation is useful for a 3D expansion.

Consequently, this is both a new presentation layer and a new simulation feature. None of the engines automatically turns the current airport capacity numbers into a functioning construction game.

## Options compared

| Option | Fit for this request | Main advantage | Main cost or limitation | Verdict |
|---|---|---|---|---|
| RealityKit + SwiftUI | Native 3D airport inside the existing app | Direct reuse of Swift core, saves and native interface | More custom game authoring tools, placement logic and traffic systems; Apple platform focus | Best first prototype for the current product |
| Unity + URP | Airport construction as the central game, mobile and PC | Integrated scenes, reusable prefabs, animation, profiling and navigation tools | Swift integration or a simulation port; greater migration and release complexity | Best choice for a full cross-platform rebuild |
| Godot | Independent stylized airport game | Open-source engine, scene workflow and built-in 3D navigation | Also needs a Swift bridge or port; web export has specific restrictions | Credible alternative when engine ownership and licensing simplicity carry more weight |
| Babylon.js | Browser-first airport game | Scene graph, picking, animation, audio, GUI, physics integration and web graphics support | Native-app integration and Swift reuse remain custom work | Preferred web shortlist candidate |
| Three.js | Custom web experience with 3D airport content | Flexible renderer and extensive composable web tooling | More assembly around simulation, game tooling, asset workflow and persistence | Capable, but not the default for this native project |
| Unreal Engine | High-fidelity PC airport world | Strong visual production tools | Mobile rendering compromises and a large workflow change for this project | Consider only if a demanding PC visual experience becomes the primary objective |

### Verified facts that affect the choice

**RealityKit can render a fully virtual airport.** AR and camera access are not required when using non-AR mode. Apple documents runtime addition and modification of scene content. The native renderer can present the airport while SwiftUI handles build menus and inspectors. [RealityKit](https://developer.apple.com/documentation/realitykit), [non-AR mode](https://developer.apple.com/documentation/realitykit/arview/cameramode-swift.enum/nonar).

**The iOS version matters.** `RealityView` starts at iOS/iPadOS 18, verified from Apple's documentation metadata. Retaining this project's iOS 17 target means using an `ARView` in non-AR mode wrapped for SwiftUI, or introducing an availability-specific presentation path. Do not assume new RealityKit features work on every supported phone. [RealityView](https://developer.apple.com/documentation/realitykit/realityview), [metadata](https://developer.apple.com/tutorials/data/documentation/realitykit/realityview.json).

**Unity supplies relevant components, not a finished airport editor.** URP targets a range of platforms including mobile; AI Navigation includes navigation meshes and dynamic obstacles. We still implement player placement, connectivity, traffic reservations and airport economics. [URP](https://docs.unity3d.com/6000.3/Documentation/Manual/universal-render-pipeline.html), [AI Navigation](https://docs.unity3d.com/Packages/com.unity.ai.navigation@2.0/manual/index.html).

**Embedding Unity has material constraints.** Unity's library documentation lists full-screen rendering for the normal mobile integration, retained memory after unloading, and an iOS runtime restart limitation after quitting. A full-screen airport mode is possible, but this is a substantial native integration. [Unity as a Library](https://docs.unity3d.com/6000.3/Documentation/Manual/UnityasaLibrary.html).

**Godot is a real contender.** It has 3D navigation and an MIT-licensed engine. Its stable documentation currently limits Godot 4 web export to WebGL 2 Compatibility rendering and says C# projects cannot export to web. That restriction does not disqualify a native GDScript game. [Navigation](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_3d.html), [license](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html), [web export](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html).

**Three.js is technically capable of the interactions.** TransformControls supports object manipulation, and InstancedMesh supports repeated geometry efficiently. Its WebGPU renderer documents WebGL 2 fallback. These features establish feasibility, not a guaranteed airport size or frame rate. [TransformControls](https://threejs.org/docs/pages/TransformControls.html), [InstancedMesh](https://threejs.org/docs/pages/InstancedMesh.html), [WebGPU renderer](https://threejs.org/manual/en/webgpurenderer).

**Babylon has a broader integrated web feature set.** Its specifications list picking, collisions, animation, audio, GUI and WebGPU/WebGL support; a separate open-source visual editor is available. Developer scene editing still does not supply the player's construction rules. [Specifications](https://www.babylonjs.com/specifications/), [editor](https://editor.babylonjs.com/documentation).

**Unreal's flagship desktop lighting is not an iPhone advantage.** Epic documents separate mobile rendering paths and states that Lumen does not work on iOS/iPadOS. A stylized Unreal airport is possible, but there is little project-specific reason to accept this migration cost. [Mobile rendering](https://dev.epicgames.com/documentation/unreal-engine/mobile-rendering-features-in-unreal-engine), [Lumen compatibility](https://dev.epicgames.com/documentation/unreal-engine/using-lumen-global-illumination-on-mobile-in-unreal-engine).

**SceneKit should not start a new implementation.** Apple marks it deprecated and directs developers to RealityKit. [SceneKit](https://developer.apple.com/documentation/scenekit/).

For engine cost, Godot's MIT license is attractive. Unity states that the Runtime Fee was canceled, and its current licensing page describes a USD 200,000 Unity Personal financial threshold. This does not price third-party airport art or development effort. [Runtime Fee cancellation](https://unity.com/blog/terms-update-runtime-fee-cancellation), [Unity eligibility](https://unity.com/pages/license-compliance).

## Proposed game experience

### User-supplied visual target

The user supplied an airport reference image after confirming iPhone/iPad first. Treat this image as the visual direction: an elevated isometric-style view, detailed modular terminals, blue glass facades, dark roofs, repeated gates and jet bridges, aircraft parked on marked stands, concrete apron panels, yellow taxiway markings, ground equipment and a control tower. The image does not establish its original rendering engine or whether every depicted object is interactive.

Aim for a detailed, readable airport miniature with realistic proportions and simplified materials. Start with an orthographic or long-lens camera and compare the composition against the reference. Favor a fixed viewing angle, pan and pinch zoom; optional stepped rotation can follow. Roofs can remain closed for the initial exterior construction scope.

Let players place terminal modules, add gates and jet bridges, move service facilities, replace building variants and connect roads. Match markings and attachment points to the constructed layout. Aircraft occupancy, jet-bridge alignment and service access need to remain valid after an edit. Decorations can have freer placement than operational structures.

The first visual slice should reproduce the reference's density at a smaller scale: one terminal frontage, four stands with jet bridges, several aircraft, one service road and animated service vehicles. Prioritize convincing ground markings, aircraft proportions, contact shadows and consistent building detail before expanding the map. Use original or licensed modular assets inspired by this direction, rather than reproducing the reference's exact artwork.

This reference keeps RealityKit on the shortlist for the native product; it does not prove device performance. Match the scene in the playable device prototype before confirming production scope. A full game editor remains a tooling advantage for Unity if the asset and construction workflow becomes the dominant constraint.

Start with one player-controlled home hub, reached from the global airline map. Other airports continue to use aggregate simulation. This connects airport construction to the existing airline game and makes content production manageable.

Use a stylized miniature airport with a tilted camera, pinch zoom, pan and optional orbit. Let players get close enough to watch aircraft turnaround. Use a clear overhead camera for construction. Recognizable aircraft, readable buildings, good lighting and purposeful movement should carry the atmosphere.

| Player action | Visible consequence | Management consequence |
|---|---|---|
| Add or upgrade a gate | More stands become available | More simultaneous turnarounds, with staffing and maintenance costs |
| Move a service depot | Vehicles take different routes | Service travel time changes |
| Improve access to a terminal module | Shorter visible queues and routes | Higher effective throughput |
| Add a baggage or fuel facility | New service activity | Removes a specific turnaround bottleneck |
| Add landscaping, signs and liveries | Airport gains a personal identity | Optional satisfaction effects, clearly separated from operational capacity |

Make construction satisfying: a transparent placement preview, grid snapping, rotation, valid/invalid feedback with reasons, price preview, confirm/cancel and undo for uncommitted plans. Moving or replacing operational buildings should have defined cost and downtime rules. Avoid unrestricted scaling of buildings whose footprints and capacities carry gameplay meaning.

Add engine sounds, service vehicle movement, boarding activity, runway lights and a restrained day/night cycle. Tie operational animations to simulation state. Limit decorative passenger counts and retain aggregate passenger economics.

A useful first loop is: observe a turnaround bottleneck, move the depot or improve access, watch vehicles take the new route, then see the next flight depart sooner. This is a testable fun hypothesis, not an established outcome.

## Architecture and migration

For the native path, extend the existing core with an `AirportLayout` state slice, stable object IDs, catalog definitions, grid positions, orientations, footprints and connection points. Add validated place/move/replace/remove commands through `GameSession`. Save the layout with a versioned migration; existing campaigns receive a valid default hub without losing their finances or fleet.

The scene renderer consumes snapshots and submits commands. A dragged preview is temporary presentation state until the core accepts it. Airport meshes and renderer object references never become authoritative save data. Capacity calculations need runtime effective values where layouts can modify today's static airport specifications.

Use connected lane graphs for taxiways and service roads, with deterministic routing and reservations at conflicts. Generic navigation meshes do not enforce aircraft turning constraints, stand clearance or runway priorities. Reserve free-walking navigation for limited passenger/staff visuals. Update affected paths after a committed edit, rather than rebuilding the entire airport during every drag frame.

Keep simulation timing separate from rendering. Interpolate visible movement between scheduled events; do not multiply the global simulation work by the rendering frame rate. Define coarse offscreen behavior and consistent resumption when returning to the hub.

For Unity/Godot, first choose whether the Swift core stays behind a native boundary or is ported. Neither engine imports this Swift package as ordinary gameplay code. A Unity iOS bridge could exchange commands and snapshots; a multi-platform port should preserve expected command outcomes, save semantics and deterministic replay fixtures. Unity alone does not make gameplay deterministic.

Create modular source assets with consistent dimensions, pivot locations and connection points. Repeated objects need shared meshes/materials, lower-detail variants and inexpensive collision shapes. Do not bake permanent shadows for objects the player can move. Retain original asset files so renderer changes do not require recreating the art.

## Concrete validation before committing production

Build one small playable hub in the recommended engine. The first version needs one runway, a terminal, four gates, a service depot, editable road connections and a complete arrival-to-departure sequence. Demonstrate adding, moving, rotating, replacing and removing objects, including invalid placements and save/reload.

Use these proposed acceptance checks; the numbers are workload targets, not measured capabilities:

1. **Touch usability:** select a small gate reliably; pan and zoom without accidental placement; cancel a move; understand a disconnected-road rejection.
2. **Gameplay:** a layout improvement measurably changes turnaround or throughput, and players can explain why.
3. **Correctness:** overlap, insufficient funds and disconnected operational facilities reject cleanly; interrupted moves and app backgrounding do not corrupt layouts or charge twice.
4. **Persistence:** layout, money and operational state survive reload; an existing campaign migrates successfully; replay gives the same authoritative outcome.
5. **Device performance:** stress a scene with roughly 500 placed objects, 20 aircraft, 40 ground vehicles and 100 visible passenger proxies. On the oldest agreed supported iPhone, target a sustained 30 fps minimum through a 15-minute play/edit session; aim for 60 fps on stronger devices. Record frame-time distribution, peak memory, thermal state and interaction hitches with the economy running.
6. **Scale behavior:** confirm that fast-forward, leaving the airport and returning produce consistent results without simulating every visible person globally.

If RealityKit meets these checks, continue the native expansion. If game authoring friction or an actual device bottleneck remains after profiling and a bounded optimization pass, reproduce the same slice in Unity before migrating. If mobile-plus-PC is the chosen product direction, start that Unity slice directly. If browser-first is chosen, compare Babylon and Three using the same assets, scene, interactions and browser devices.

This Windows workspace cannot run Apple's native graphics stack or Instruments. Documentation and source inspection establish technical feasibility and migration fit; real device testing must establish performance, visual quality and fun.
