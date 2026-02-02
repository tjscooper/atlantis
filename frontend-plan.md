# Plan: Frontend Application

## Tech Stack
- **Vite** + React 18 + TypeScript
- **Tailwind CSS** for styling
- **Recharts** for dashboard charts
- **D3.js** for uncertainty scatter + dimensionality reduction plots
- **3Dmol.js** for crystal structure visualization
- **React Router v6** for client-side routing
- **lucide-react** for icons
- Mock data layer (swappable for real API later)

## Directory Structure

```
frontend/
  Dockerfile                          # multi-stage: npm build → nginx
  package.json
  tsconfig.json
  vite.config.ts                      # @/ alias, dev proxy for /api
  index.html
  postcss.config.js
  tailwind.config.js
  nginx.conf                          # (already exists)
  src/
    main.tsx
    App.tsx                            # Routes
    index.css                          # Tailwind directives

    api/
      index.ts                         # Re-exports (swap point for real API)
      client.ts                        # fetch wrapper (future use)
      types.ts                         # TS interfaces matching DB schema
      mock/
        data.ts                        # Static mock datasets (~200 materials, 800 predictions, etc.)
        materials.mock.ts
        predictions.mock.ts
        candidates.mock.ts
        validations.mock.ts
        active-learning.mock.ts
        dashboard.mock.ts

    components/
      layout/
        AppShell.tsx                   # Sidebar + top bar + content
        Sidebar.tsx
        TopBar.tsx
      common/
        DataTable.tsx                  # Generic sortable/filterable table
        StatusBadge.tsx                # Colored pill for candidate status
        LoadingSpinner.tsx
        SearchInput.tsx
        Pagination.tsx
      dashboard/
        MetricCard.tsx                 # KPI card (number + trend arrow)
        PipelineHealthChart.tsx        # Candidates over time by status
        PredictionDistribution.tsx     # Histogram of predicted values
        RecentActivityFeed.tsx
        StatusBreakdownPie.tsx
      candidates/
        CandidateTable.tsx
        CandidateFilters.tsx           # Status tabs + score range
        FlagCandidateModal.tsx         # Flag + notes + researcher name
        CandidateDetailPanel.tsx       # Slide-over with full detail
      materials/
        MaterialCard.tsx
        StructureViewer.tsx            # 3Dmol.js viewer
        PropertiesTable.tsx            # JSONB → key-value table
        PredictionHistory.tsx          # Recharts line chart
      active-learning/
        ConvergencePlot.tsx            # Best score per iteration
        ExplorationExploitationChart.tsx
        RunHistoryTable.tsx
      predictions/
        UncertaintyScatter.tsx         # D3: predicted value vs uncertainty
        DimensionalityReductionPlot.tsx # D3: t-SNE/UMAP colored by property
        CalibrationPlot.tsx            # Predicted vs actual

    pages/
      DashboardPage.tsx
      CandidatesPage.tsx
      MaterialsListPage.tsx
      MaterialDetailPage.tsx
      ActiveLearningPage.tsx
      PredictionsPage.tsx

    hooks/
      useApiQuery.ts                   # Wraps async calls with loading/error
      usePagination.ts
      useSortable.ts

    utils/
      formatters.ts
      constants.ts                     # Status colors, CPK colors, labels
```

## Routes

| Route | Page | Purpose |
|---|---|---|
| `/` | DashboardPage | Pipeline KPIs, status breakdown, recent activity |
| `/candidates` | CandidatesPage | Ranked table, filtering, flag/review actions |
| `/materials` | MaterialsListPage | Searchable list of all materials |
| `/materials/:id` | MaterialDetailPage | 3Dmol viewer, properties, prediction history |
| `/active-learning` | ActiveLearningPage | Convergence plots, iteration history |
| `/predictions` | PredictionsPage | Uncertainty scatter, t-SNE/UMAP, calibration |

## Mock Data Layer

The `src/api/` directory is the boundary between UI and data. All pages import from `@/api`. Mock functions return `Promise`-wrapped data with small delays so loading states render.

**Mock dataset scope:**
- ~200 materials (real catalyst formulas: TiO2, ZnO, BiVO4, SrTiO3, etc.)
- ~30 materials with `structure_json` for 3Dmol rendering (real lattice constants)
- ~800 predictions across 5 model runs
- ~150 candidates (60% ranked, 15% flagged, 10% in_validation, 10% validated, 5% rejected)
- ~20 validation results
- 8 active learning runs showing convergence over time

When the real API exists, change the imports in `api/index.ts` to point at `client.ts`-based functions. Nothing outside `api/` changes.

## Implementation Order

1. **Scaffold** — Vite init, deps, Tailwind config, Dockerfile, verify build
2. **Types + mock data** — `api/types.ts`, all mock files, `api/index.ts`
3. **Layout shell** — AppShell, Sidebar, TopBar, route placeholders
4. **Dashboard** — MetricCard, charts, activity feed
5. **Candidates** — DataTable, filters, flag modal, detail panel
6. **Materials** — List page, detail page with 3Dmol.js StructureViewer
7. **Active learning** — Convergence plot, exploration/exploitation chart, run table
8. **Predictions** — D3 scatter plots, calibration chart
9. **Polish** — Loading states, error boundaries, empty states

## Verification
- `npm run build` produces `dist/` with no errors
- `docker build -t atlantis-frontend .` succeeds
- All 6 routes render with mock data
- 3Dmol.js viewer renders a crystal structure on material detail page
- Candidate flagging updates status in-memory
- D3 plots render without console errors
