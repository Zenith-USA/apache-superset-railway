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

### Current Dashboards

**User Growth & Onboarding** (`/superset/dashboard/user-growth/`)
- KPI cards: Total Users, New (30d/7d), Active (7d/30d), Onboarded %, Connected %
- User Activity donut (recency buckets)
- New Users Over Time (weekly line chart)
- Onboarding Funnel (Signed Up -> Onboarding Complete -> Connected Provider -> Backfill Complete -> Data Received)
- Garmin Permissions donut
- Country & Timezone treemaps

### Datasets

| Dataset | Description |
|---|---|
| `users_overview` | Joined `users` + `user_config` + `app_activity_log` - one row per user |
| `onboarding_funnel` | Pre-aggregated funnel stage counts |
| `garmin_permissions_summary` | Garmin permission status breakdown |
| `user_activity_buckets` | User recency buckets (Today, 1-2 days, 3-4 days, etc.) |
| `kpi_overview` | Single-row KPI summary |

## Architecture

- **Base image**: `apache/superset:latest`
- **Database drivers**: `psycopg2-binary` (Postgres), `mysqlclient` (MySQL)
- **Metadata store**: Separate Postgres instance on Railway (stores dashboards, charts, datasets, user accounts)
- **Data source**: Zenith production Postgres (queried for chart data)
- **Admin user**: Auto-created on startup via `superset_init.sh`
