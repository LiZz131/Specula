# Generation preflight (static only)

- SANY: base.tla, MC.tla, Update.tla parse and lint without errors
  (`cd spec && timeout 120 java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar tla2sany.SANY <M>.tla`).
- VAV (mcp spec_analyzer run_vav_analysis) on base.tla: 0 issues, 27 variables, 64 operators.
  The tool could not resolve `EXTENDS base` for MC.tla (module search path), so MC wrappers
  were checked by SANY and by review: every wrapper conjoins a base Action and assigns
  `counters`/`seen` explicitly.
- Static cfg operator resolution: every SPECIFICATION/INVARIANT/PROPERTY/SYMMETRY/CONSTRAINT
  name in base.cfg, MC*.cfg, Update*.cfg resolves to a definition in the module that the cfg
  is run against (Update-discharge.cfg corrected to `UpdFullSpec` because Update declares the
  `everCommitted` observer).
- No BFS/simulation/trace replay was run during Generation.
