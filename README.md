# Apache Superset - Zenith Analytics

Self-hosted Apache Superset instance on Railway for Zenith data visualization and dashboarding.

## Setup

### Environment Variables (Railway)

| Variable | Description |
|---|---|
| `ADMIN_USERNAME` | Superset admin username |
| `ADMIN_EMAIL` | Superset admin email |
| `ADMIN_PASSWORD` | Superset admin password |
| `DATABASE` | SQLAlchemy URI for Superset's metadata database |
| `SECRET_KEY` | Flask secret key |
| `PORT` | Server port |

### Feature Flags

Configured in `config/superset_config.py`:

- `DECK_GL_CHARTS` - deck.gl map visualizations
- `DASHBOARD_CROSS_FILTERS` - clicking a chart filters all other charts on the dashboard
- `DRILL_TO_DETAIL` / `DRILL_BY` - click into data points to see raw rows
- `ENABLE_EXPLORE_DRAG_AND_DROP` - improved chart builder UI
- `ALERT_REPORTS` - email/slack alerts when metrics hit thresholds
- `DASHBOARD_NATIVE_FILTERS` - sidebar filter UI
- `ENABLE_TEMPLATE_PROCESSING` - Jinja template variables in SQL

## MCP Server Integration (Claude Code)

Dashboards, datasets, and charts are managed programmatically via the [superset-mcp](https://www.npmjs.com/package/superset-mcp) MCP server connected to Claude Code.

### Configuration

In the project's `.mcp.json`:

```json
"superset": {
  "command": "npx",
  "args": ["-y", "superset-mcp"],
  "env": {
    "SUPERSET_BASE_URL": "https://superset.zenithwellness.health",
    "SUPERSET_USERNAME": "<admin_username>",
    "SUPERSET_PASSWORD": "<admin_password>"
  }
}
```

### How It Works

The MCP server exposes Superset's REST API as tools that Claude Code can call directly:

- **`execute_sql`** - Run queries against connected databases to test/validate data
- **`create_dataset`** - Create virtual datasets (SQL queries) that power charts
- **`create_chart`** - Create charts with specific viz types, metrics, and formatting
- **`update_chart`** - Modify chart params, viz type, color scheme, etc.
- **`add_chart_to_dashboard`** - Wire charts into dashboards
- **`update_dashboard_config`** - Set dashboard layout (`position_json`), title, CSS overrides, and publish state
- **`list_databases`** / **`list_datasets`** / **`list_charts`** / **`list_dashboards`** - Query existing resources
- **`get_chart_params`** - Get the required parameter schema for each viz type before creating charts
- **`refresh_dataset_schema`** - Sync dataset columns after SQL changes

### Workflow

1. **Datasets** are virtual SQL queries against the Zenith production Postgres (connected as "Zenith Railway Production" in Superset)
2. **Charts** are created on top of datasets with specific viz types (`funnel`, `pie`, `big_number_total`, `echarts_timeseries_line`, `treemap_v2`, `world_map`, etc.)
3. **Dashboards** arrange charts in a grid layout via `position_json` — each chart gets a width (out of 12 columns) and height (in grid units)
4. Dashboard **CSS overrides** can be applied for styling fixes (e.g., label colors)

### Dashboard Styling Conventions

Follow these patterns when creating or modifying dashboards to maintain consistency.

#### Layout Structure

Every dashboard follows the same top-down layout:

1. **KPI row** -- 4 `big_number_total` cards across the top, width 3 each (3+3+3+3 = 12), height 20
2. **Trend/chart rows** -- side-by-side charts at width 6 each, height 50
3. **Full-width charts** -- bar charts, heatmaps at width 12, height 50-60
4. **Detail tables** -- searchable tables at width 12 or width 6 (side by side), height 40-50

#### Chart Type Reference

| Use case | Viz type | Notes |
|---|---|---|
| Single KPI number | `big_number_total` | Uses singular `metric`, not `metrics` |
| Pie/donut | `pie` | Uses singular `metric`, not `metrics`. Set `label_type: "key_percent"`, `labels_outside: true`, `sort_by_metric: true` |
| Time series line | `echarts_timeseries_line` | Uses `x_axis` for time column, `metrics` array |
| Time series bar | `echarts_timeseries_bar` | Same as line. Use `stack: true` for stacked. Set `orientation: "horizontal"` for horizontal bars |
| Cohort heatmap | `heatmap_v2` | Uses `x_axis`, `groupby`, singular `metric`. Set `value_bounds: [0, 100]` for percentages |
| Data table | `table` | Use `query_mode: "raw"` with `all_columns` for pre-aggregated datasets. Set `include_search: true`, `show_cell_bars: true` |

**Important:** The legacy `bar` viz type is NOT registered. Always use `echarts_timeseries_bar` instead.

#### Dataset Conventions

- Virtual datasets (custom SQL) are preferred over physical table references
- Always join `user_config` for user names (not `users.first_name` which comes from Apple and is often null/relay email)
- Use `::numeric` cast before `ROUND()` in Postgres (e.g., `ROUND(AVG(col)::numeric, 1)`)
- Name datasets descriptively: `weekly_activity_trend`, `retention_cohort`, `at_risk_users`
- Add descriptions to every dataset explaining what it powers

#### Dashboard Layout JSON

Dashboards use `position_json` to arrange charts in a grid. The grid is 12 columns wide. Key structure:

```json
{
  "DASHBOARD_VERSION_KEY": "v2",
  "ROOT_ID": { "type": "ROOT", "children": ["GRID_ID"] },
  "GRID_ID": { "type": "GRID", "children": ["ROW-kpi", "ROW-charts"], "parents": ["ROOT_ID"] },
  "ROW-kpi": {
    "type": "ROW",
    "children": ["C-1", "C-2", "C-3", "C-4"],
    "meta": { "background": "BACKGROUND_TRANSPARENT" }
  },
  "C-1": {
    "type": "CHART",
    "meta": { "width": 3, "height": 20, "chartId": 1, "sliceName": "Chart Name" }
  }
}
```

- Row IDs: use descriptive names like `ROW-kpi`, `ROW-trends`, `ROW-tables`
- Chart node IDs: use `C-{chartId}` format
- Charts must be associated with the dashboard (via `dashboards` param on create, or `update_chart` with `dashboards: [id]`) before they appear in the layout
- After updating dataset SQL, call `refresh_dataset_schema` to sync columns
- Dashboard creation requires direct REST API call (MCP tool doesn't have `create_dashboard`):
  ```bash
  curl -X POST "$SUPERSET_URL/api/v1/dashboard/" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"dashboard_title": "Name", "slug": "slug", "published": true}'
  ```

#### Common Gotchas

- `pie` uses singular `metric`, `echarts_timeseries_*` uses `metrics` array, `big_number_total` uses singular `metric`
- Always call `get_chart_params` for a viz type before creating/updating charts to verify the schema
- The legacy `bar` viz type throws "not registered" -- use `echarts_timeseries_bar`
- After updating a dataset's SQL, you must call `refresh_dataset_schema` or charts will error with "columns missing"
- `get_dataset` returns 405 in this Superset version -- can't read existing dataset SQL via MCP
- To create a dashboard via MCP, you need to login via REST API first (the MCP tool only has update, not create)

### Current Dashboards

**User Growth & Onboarding** (`/superset/dashboard/user-growth/`)
- KPI cards: Total Users, New (30d/7d), Active (7d/30d), Onboarded %, Connected %
- User Activity donut, New Users Over Time, Onboarding Funnel
- Garmin Permissions donut, Country & Timezone treemaps

**Activity & Engagement** (`/superset/dashboard/activity-engagement/`)
- KPI cards: Total Activities, Activities (7d), Active Users (7d), Avg Activities/User (7d)
- Weekly Active Users trend, Activities by Type (stacked bar)
- Activity Type Distribution pie, User Engagement Buckets pie
- Most Active Users table

**Community** (`/superset/dashboard/community/`)
- KPI cards: Total Follows, Total Likes, Total Comments, % Users With Follow, Pending Follows
- Community Engagement Over Time, Community Adoption Funnel
- Community Engagement Leaderboard (ranked by engagement score)

**Affiliate Program** (`/superset/dashboard/affiliate-program/`)
- KPI cards: Active Affiliates, Total Referred Users, Referrals in Window, Referrals (7d)
- Affiliate Payout Table, Affiliate Leaderboard (bar), Affiliate Referrals Detail
- Access Override Users table (all free Pro bypasses)

**User Retention** (`/superset/dashboard/user-retention/`)
- KPI cards: Retention Rate (7d/30d), At-Risk Users, Churned Users
- Retention Cohort Heatmap (signup week vs weeks since signup)
- At-Risk Users Detail table, Weekly Retention Trend line
- User Data Freshness table (activity/sleep freshness per user)

**Provider & Data Health** (`/superset/dashboard/provider-health/`)
- KPI cards: Garmin Active, Garmin Errors, Strava Connected, Manual Activity Users
- Connection Status pie, Provider Distribution pie
- Daily Webhook Volume (bar), Stale Connections table

**Lifting Analytics** (`/superset/dashboard/lifting-analytics/`)
- KPI cards: Total Lifters, Total Sessions, Total Volume (kg), Sessions (7d)
- Weekly Lifting Volume (bar), Muscle Group Distribution (horizontal bar)
- Exercise Popularity table, Top Lifters table

**Strain, Recovery & Sleep** (`/superset/dashboard/strain-recovery-sleep/`)
- KPI cards: Avg Recovery, Avg Sleep Score, Avg Strain, Avg HRV (all 30-day population averages)
- Strain vs Recovery Trend (triple line, 90 days), HRV & RHR Trend (dual line, 90 days)
- Sleep Quality Distribution pie (Excellent/Good/Fair/Poor), Sleep Stage Breakdown pie (Deep/REM/Light/Awake)
- Recovery Leaderboard (users ranked by avg recovery with all health metrics)

## Architecture

- **Base image**: `apache/superset:latest`
- **Database drivers**: `psycopg2-binary` (Postgres), `mysqlclient` (MySQL)
- **Metadata store**: Separate Postgres instance on Railway (stores dashboards, charts, datasets, user accounts)
- **Data source**: Zenith production Postgres (queried for chart data)
- **Admin user**: Auto-created on startup via `superset_init.sh`
